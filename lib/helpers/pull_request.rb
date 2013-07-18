class PullRequest
  def initialize(repository, pull_request_id)
    @repository = repository
    @pull_request_id = pull_request_id
  end
  
  def repository
    @repository
  end
  
  def pull_request_id
    @pull_request_id
  end
  
  def set_data(data)
    @data = data
  end
  
  def data
    @data
  end
end