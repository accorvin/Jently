require 'octokit'

module Github
  def Github.get_open_pulls
    begin
      client = Github.new_client
      repositories = Repository.get_repositories_to_test
      
      open_pulls = []
      pull_count = 0
      
      repositories.each do |repo|
        Logger.log("Checking for pull requests for #{repo.repository_name}")
        open_pull_requests = client.pull_requests(repo.repository_name, 'open')
        open_pull_requests_ids = open_pull_requests.collect { |pull_request| pull_request.number }
        open_pull_requests_ids.each do |id|
          open_pulls[pull_count] = PullRequest.new(repo, id)
          pull_count = pull_count + 1
        end
      end
#      repository_id = Repository.get_id

#      open_pull_requests = client.pull_requests(repository_id, 'open')
#      open_pull_requests_ids = open_pull_requests.collect { |pull_request| pull_request.number }

      return open_pulls
    rescue => e
      Logger.log('Error when getting open pull requests ids', e)
      sleep 5
      retry
    end
  end

  def Github.get_pull_request_data(pull_request)
    begin
      client = Github.new_client
      repository_id = pull_request.repository.repository_name

      pull_request_data = client.pull_request(repository_id, pull_request.pull_request_id)
      statuses = client.statuses(repository_id, pull_request_data.head.sha)

      data = {}
      data[:id] = pull_request_data.number
      data[:merged] = pull_request_data.merged
      data[:mergeable] = pull_request_data.mergeable
      data[:head_branch] = pull_request_data.head.ref
      data[:head_sha] = pull_request_data.head.sha

      data[:status] = statuses.empty? ? 'undefined' : statuses.first.state

      # Update base_sha separately. The pull_request call is
      # not guaranteed to return the last sha of the base branch.
      data[:base_branch] = pull_request_data.base.ref
      data[:base_sha] = client.commits(repository_id, data[:base_branch]).first.sha
      data
    rescue => e
      Logger.log('Error when getting pull request', e)
      sleep 5
      retry
    end
  end

  def Github.set_pull_request_status(repository_id, pull_request_id, state)
    begin
      head_sha = PullRequestsData.read[repository_id][pull_request_id][:head_sha]

      opts = {}
      opts[:target_url] = state[:url] if !state[:url].nil?
      opts[:description] = state[:description] if !state[:description].nil?

      client = Github.new_client
      client.create_status(repository_id, head_sha, state[:status], opts)

      PullRequestsData.update_status(repository_id, pull_request_id, state[:status])

      if state[:status] == 'success' || state[:status] == 'failure'
        PullRequestsData.reset(repository_id, pull_request_id)
      end
      
      if state[:status] == 'failure'
        comment = "The Jenkins build for this pull request failed. See #{opts[:target_url]} for more details."
      else if state[:status] == 'success'
        comment = "This pull request was successfully tested in Jenkins. see #{opts[:target_url]} for more details."
      end
      client.create_commit_comment(repository_id, head_sha, comment)
    rescue => e
      Logger.log('Error when setting pull request status', e)
      sleep 5
      retry
    end
  end

  def Github.new_client
    config = ConfigFile.read
    if config.has_key?(:github_api_endpoint)
      Octokit.configure do |c|
        c.api_endpoint = config[:github_api_endpoint]
        c.web_endpoint = config[:github_web_endpoint]
      end
    end

    if config.has_key?(:github_oauth_token)
      client = Octokit::Client.new(:login => config[:github_login], :oauth_token => config[:github_oauth_token])
    else
      client = Octokit::Client.new(:login => config[:github_login], :password => config[:github_password])
    end
    client
  end
end
