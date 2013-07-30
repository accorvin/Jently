require 'yaml'

module PullRequestsData
  def PullRequestsData.get_path
    "#{Dir.pwd}/db/pull_requests.yaml"
  end

  def PullRequestsData.read
    path = get_path
    data = YAML.load(File.read(path)) if File.exists?(path)
    data || {}
  end

  def PullRequestsData.write(data)
    path = get_path
    File.open(path, 'w') { |f| YAML.dump(data, f) }
  end

  def PullRequestsData.update(repo_name, pull_request_data)
    id = pull_request_data[:id]
    data = read
    
    if !data.has_key?(repo_name)
      data[repo_name] = Hash.new
    end
    if !data[repo_name].has_key?(id)
      data[repo_name][id] = pull_request_data
    end
    
    data[repo_name][id][id] = id
    data[repo_name][id][:priority] = get_new_priority(repo_name, pull_request_data)
    data[repo_name][id][:is_test_required] = test_required?(repo_name, pull_request_data)
    data[repo_name][id][:status] = pull_request_data[:status]
    write(data)
  end

  def PullRequestsData.remove_dead_pull_requests(open_pull_requests)
    open_pulls_hash = Hash.new

    open_pull_requests.each do |pull|
      repo_name = pull.repository.repository_name
      pull_id = pull.pull_request_id
      if (!open_pulls_hash.has_key?(repo_name))
        open_pulls_hash[repo_name] = Array.new
      end
      open_pulls_hash[repo_name].push(pull_id)
    end

    data = read

    data_copy = data
    existing_repositories = data_copy.keys
    existing_repositories.each do |repo|
      if (!open_pulls_hash.has_key?(repo))
        data.delete(repo)
      else
        open_repo_pulls = open_pulls_hash[repo]
        data_copy[repo].keys.each do |pull|
          if (!open_repo_pulls.include?(pull))
            data[repo].delete(pull)
          end
        end
      end
      
    end

    write(data)
  end

  def PullRequestsData.update_status(repo_name, pull_request_id, status)
    data = read
    data[repo_name][pull_request_id][:status] = status
    write(data)
  end

  def PullRequestsData.reset(repo_name, pull_request_id)
    data = read
    data[repo_name][pull_request_id][:priority] = -1
    data[repo_name][pull_request_id][:is_test_required] = false
    write(data)
  end

  def PullRequestsData.outdated_success_status?(repo_name, pull_request_data)
    data = read
    is_job_new = !data.has_key?(repo_name)
    if is_job_new
      is_new = true
    else
      job = data[repo_name]
      is_new = !job.has_key?(pull_request_data[:id])
    end

    has_outdated_success_status = !is_new &&
                                  pull_request_data[:status] == 'success' &&
                                  data[repo_name][pull_request_data[:id]][:status] == 'success' &&
                                  data[repo_name][pull_request_data[:id]][:base_sha] != pull_request_data[:base_sha]
  end

  def PullRequestsData.get_new_priority(repo_name, pull_request_data)
    data = read
    is_job_new = !data.has_key?(repo_name)
    
    if is_job_new
      is_new = true
    else
      job = data[repo_name]
      is_new = !job.has_key?(pull_request_data[:id])
    end
    
    if is_new
      priority = 0
    else
      priority = data[repo_name][pull_request_data[:id]][:priority] + 1
    end
    priority
  end

  def PullRequestsData.test_required?(repo_name, pull_request_data)
    return false if pull_request_data[:merged]

    data = read
    is_job_new = !data.has_key?(repo_name)
    
    if is_job_new
      is_new = true
    else
      job = data[repo_name]
      is_new = !job.has_key?(pull_request_data[:id])
    end

    is_waiting_to_be_tested = (is_new) ? false : data[repo_name][pull_request_data[:id]][:is_test_required]
    has_inconsistent_status = (is_new) ? false : data[repo_name][pull_request_data[:id]][:status] != pull_request_data[:status]

    if (!is_new)
        if (get_comment_status(repo_name, pull_request_data[:id]))
            return true
        end
    end

    if (pull_request_data[:status] == 'pending')
      return false
    end
    
    if (!is_new)
      pull_id = pull_request_data[:id]
      if (data[repo_name][pull_id][:status] == 'pending')
        client = Github.new_client
        Github.set_pull_request_status(repo_name, pull_id, {:status => 'pending', :description => 'Jenkins build started.'})
        return false
      end
    end
    
    has_invalid_status = ['error', 'undefined'].include?(pull_request_data[:status])
    has_valid_status = ['success', 'failure'].include?(pull_request_data[:status])

    was_updated = (is_new) ? false : (data[repo_name][pull_request_data[:id]][:head_sha] != pull_request_data[:head_sha]) ||
                                     (data[repo_name][pull_request_data[:id]][:base_sha] != pull_request_data[:base_sha])

    is_test_required = is_new || is_waiting_to_be_tested || has_inconsistent_status || has_invalid_status || (has_valid_status && was_updated)
  end
  
  def PullRequestsData.get_comment_status(repo_name, pull_id)
    comment_strings = [
      "I'd follow you anywhere. -Jently",
      "I am happy to oblige, sir. -Jently",
      "As you wish. -Jently"
    ]

    client = Github.new_client
    pull_request_comments = client.issue_comments(repo_name, pull_id)
    
    if (pull_request_comments.empty?)
      return false
    end
    
    pull_request_comments.each do |comment|
      body = comment[:body].downcase
      if (body.match('.*go.*jently.*'))
        new_body = comment_strings.sample
        client.delete_comment(repo_name, comment[:id])
        client.add_comment(repo_name, pull_id, new_body)
        return true
      end
    end
    
    return false
  end

  def PullRequestsData.get_pull_request_to_test(open_pull_requests)
    data = read
    config = ConfigFile.read
    pull_requests_that_require_testing = []
    testing_pulls_count = 0
    
    open_pull_requests.each do |pull|
      repo_name = pull.repository.repository_name
      if data[repo_name][pull.pull_request_id][:is_test_required]
        pull_requests_that_require_testing[testing_pulls_count] = pull
        testing_pulls_count += 1
      end
    end

    pull_request_to_test = (testing_pulls_count == 0) ? nil : get_highest_priority_pull_request(data, pull_requests_that_require_testing)
  end
  
  def PullRequestsData.get_highest_priority_pull_request(data, pull_requests_that_require_testing)
    max_priority_pull = nil
    pull_requests_that_require_testing.each do |pull|
      if max_priority_pull.nil?
        max_priority_pull = pull
      else
        if data[pull.repository.repository_name][pull.pull_request_id][:priority] > data[max_priority_pull.repository.repository_name][max_priority_pull.pull_request_id][:priority]
          max_priority_pull = pull
        end
      end
    end
    return max_priority_pull
  end
end
