module Core
  def Core.test_pull_request(pull_request_object)
    begin
      config = ConfigFile.read
      repo_name = pull_request_object.repository.repository_name
      jenkins_job_name = pull_request_object.repository.jenkins_job_name 
      pull_request = pull_request_object.data
      pull_id = pull_request_object.pull_request_id

      if pull_request[:mergeable] == false
        Github.set_pull_request_status(pull_id, {:status => 'failure', :description => 'Unmergeable pull request.'})
      end

      if pull_request[:mergeable] == true
        #Jenkins.wait_for_idle_executor

        Github.set_pull_request_status(repo_name, pull_id, {:status => 'pending', :description => 'Jenkins build started.', :url => "#{config[:jenkins_url]}/job/#{jenkins_job_name}"})
        Logger.log("Building #{config[:jenkins_url]}/job/#{jenkins_job_name}")
        job_id = Jenkins.start_job(jenkins_job_name, pull_id, pull_request[:head_branch], repo_name)
        state = Jenkins.wait_on_job(jenkins_job_name, job_id)

        Github.set_pull_request_status(repo_name, pull_id, state)
#        if timeout
#          Github.set_pull_request_status(pull_id, {:status => 'error', :description => 'Jenkins build timed out.'})
#        else
#          Github.set_pull_request_status(pull_id, thr.value)
#        end
      end
    rescue => e
      Github.set_pull_request_status(repo_name, pull_request_object.pull_request_id, {:status => 'error', :description => 'A Jenkins build error has occurred. This pull request will be automatically rescheduled for testing.'})
      Logger.log('Error when testing pull request', e)
    end
  end

  def Core.poll_pull_requests_and_queue_next_job
    open_pull_requests = Github.get_open_pulls
    PullRequestsData.remove_dead_pull_requests(open_pull_requests)

    open_pull_requests.each do |pull_request|
      pull_request_data = Github.get_pull_request_data(pull_request)
      repo_name = pull_request.repository.repository_name
      pull_request.set_data(pull_request_data)
      if PullRequestsData.outdated_success_status?(repo_name, pull_request_data)
        Github.set_pull_request_status(repo_name, pull_request_data[:id], {:status => 'success', :description => "This has been rescheduled for testing as the '#{pull_request_data[:base_branch]}' branch has been updated."})
      end
      PullRequestsData.update(repo_name, pull_request_data)
    end

    if !open_pull_requests.empty?
      pull_request_to_test = PullRequestsData.get_pull_request_to_test(open_pull_requests)
    end
    
    if !pull_request_to_test.nil?
      thr = Thread.new do
        test_pull_request(pull_request_to_test)
      end
    end
  end
end
