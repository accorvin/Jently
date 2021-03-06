require 'faraday'
require 'faraday_middleware'

module Jenkins
  def Jenkins.wait_for_idle_executor
    config = ConfigFile.read
    while true
      return if get_nb_of_idle_executors >= 1
      sleep config[:jenkins_polling_interval_seconds]
    end
  end

  def Jenkins.get_nb_of_idle_executors
    begin
      config = ConfigFile.read
      connection = Jenkins.new_connection("#{config[:jenkins_url]}/api/json", config, :use_json => true)

      response = connection.get do |req|
        req.params[:depth] = 1
        req.params[:tree] = 'assignedLabels[idleExecutors]'
      end
      response.body[:assignedLabels][0][:idleExecutors]
    rescue => e
      Logger.log('Error when getting nb of idle executors', e)
      sleep 5
      retry
    end
  end

  def Jenkins.new_job_id(pull_request_id)
    "#{pull_request_id}-#{(Time.now.to_f * 1000000).to_i}"
  end

  def Jenkins.start_job(jenkins_job_name, pull_request_id, branch_name, repo_name)
    begin
      config = ConfigFile.read
      connection = Jenkins.new_connection("#{config[:jenkins_url]}/job/#{jenkins_job_name}/buildWithParameters?delay=0sec", config)

      job_id = new_job_id(pull_request_id)
      connection.post do |req|
        req.params[:branch] = branch_name
        req.params[:id] = job_id
      end

      job_id
    rescue => e
      Logger.log('Error when starting job', e)
      Github.set_pull_request_status(repo_name, pull_request_id, {:status => 'error', :description => 'A Jenkins build error has occurred. This pull request will be automatically rescheduled for testing.'})
      sleep 5
      retry
    end
  end

  def Jenkins.wait_on_job(jenkins_job_name, job_id)
    config = ConfigFile.read
    while true
      state = get_job_state(jenkins_job_name, job_id)
      return state if !state.nil?
      sleep config[:jenkins_polling_interval_seconds]
    end
  end

  def Jenkins.get_job_state(jenkins_job_name, job_id)
    begin
      config = ConfigFile.read
      connection = Jenkins.new_connection("#{config[:jenkins_url]}/job/#{jenkins_job_name}/api/json", config, :use_json => true)

      response = connection.get do |req|
        req.params[:depth] = 1
        req.params[:tree] = 'builds[actions[parameters[name,value]],building,result,url]'
      end

      state = nil
      response.body[:builds].each do |build|
        begin
          if build[:actions][0][:parameters][1][:value] == job_id
            if !build[:building]
              url = build[:url]
              state = {:status => 'success', :description => Jenkins.get_success_status(), :url => url} if build[:result] == 'SUCCESS'
              state = {:status => 'failure', :url => url} if build[:result] == 'UNSTABLE'
              state = {:status => 'failure', :url => url} if build[:result] == 'FAILURE'
            end
          end
        rescue
        end
      end
      state
    rescue => e
      Logger.log('Error when getting job state', e)
      sleep 5
      retry
    end
  end
  
  def Jenkins.remove_pending_pulls(open_pull_requests)
    new_open_pulls = open_pull_requests
    data = JenkinsFile.read()
    
    open_pull_requests.each do |pull|
      repo_name = pull.repository.repository_name
      id = pull.pull_request_id
      if (data.has_key?(repo_name))
        if (data[repo_name].has_key?(id))
          new_open_pulls.delete(pull)
        end
      end
    end
    
    return new_open_pulls
  end
  
  def Jenkins.add_pull_to_file(pull)
    repo_name = pull.repository.repository_name
    id = pull.pull_request_id
    
    data = JenkinsFile.read()
    if (!data.has_key?(repo_name))
      data[repo_name] = Hash.new()
    end
    data[repo_name][id] = true
    JenkinsFile.write(data)
  end
  
  def Jenkins.remove_pull_from_file(pull)
    repo_name = pull.repository.repository_name
    id = pull.pull_request_id
    
    data = JenkinsFile.read()
    if (data.has_key?(repo_name))
      if (data[repo_name].has_key?(id))
        data[repo_name].delete(id)
      end
    end
    JenkinsFile.write(data)
  end

  def Jenkins.new_connection(url, config, opts = {})
    connection = Faraday.new(:url => url) do |c|
      c.use Faraday::Request::UrlEncoded
      c.use FaradayMiddleware::FollowRedirects
      c.use Faraday::Adapter::NetHttp
      if opts[:use_json]
        c.use FaradayMiddleware::Mashify
        c.use FaradayMiddleware::ParseJson
      end
    end

    if config.has_key?(:jenkins_login) && config.has_key?(:jenkins_password)
      connection.basic_auth(config[:jenkins_login], config[:jenkins_password])
    end
    connection
  end

  def Jenkins.get_success_status()
    statuses = [
      'By jove, old bean, I believe this build is a success!',
      'I say, old fruit, I cannot believe this is working!'
    ]

    return statuses.sample
  end
end

