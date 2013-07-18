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
    data = read
    data[pull_request[repo_name][:id]] = pull_request_data[:id]
    data[pull_request[repo_name][:id]][:priority] = get_new_priority(repo_name, pull_request_data)
    data[pull_request[repo_name][:id]][:is_test_required] = test_required?(repo_name, pull_request_data)
    write(data)
  end

  def PullRequestsData.remove_dead_pull_requests(open_pull_requests)
    data = read
    dead_pull_requests_ids = data.keys - open_pull_requests_ids
    dead_pull_requests_ids.each { |id| data.delete(id) }
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
    
    priority = (is_new) ? 0 : (data[repo_name][pull_request_data[:id]][:priority] + 1)
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

    if ['pending'].include?(pull_request_data[:status])
      return false
    end
    
    has_invalid_status = ['error', 'undefined'].include?(pull_request_data[:status])
    has_valid_status = ['success', 'failure'].include?(pull_request_data[:status])

    was_updated = (is_new) ? false : (data[repo_name][pull_request_data[:id]][:head_sha] != pull_request_data[:head_sha]) ||
                                     (data[repo_name][pull_request_data[:id]][:base_sha] != pull_request_data[:base_sha])

    is_test_required = is_new || is_waiting_to_be_tested || has_inconsistent_status || has_invalid_status || (has_valid_status && was_updated)
  end

  def PullRequestsData.get_pull_request_id_to_test(open_pull_requests)
    data = read
    config = ConfigFile.read
    pull_requests_that_require_testing = []
    testing_pulls_count = 0
    
    open_pull_requests.each do |pull|
      repo_name = pull.repository.repository_name
      if data[repo_name][pull.pull_request_id][:is_test_required]
        pull_requests_that_require_testing[testing_pulls_count] = pull
      end
    end

    pull_request_id_to_test = (pull_requests_that_require_testing.empty?) ? nil : get_hightest_priority_pull_request(data, pullrequests_that_require_testing).pull_request_id
  end
  
  def get_hightest_priority_pull_request(data, pull_requests_that_require_testing)
    max_priority_pull
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
