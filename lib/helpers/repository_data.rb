class RepositoryData
  def initialize(repository_name, jenkins_job_name)
    @repository_name = repository_name
    @jenkins_job_name = jenkins_job_name
  end
  
  def repository_name
    @repository_name
  end
  
  def jenkins_job_name
    @jenkins_job_name
  end
end