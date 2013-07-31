require 'yaml'

module JenkinsFile
  def JenkinsFile.get_path
    "#{Dir.pwd}/db/jenkins_jobs.yaml"
  end

  def JenkinsFile.read
    path = get_path
    data = YAML.load(File.read(path)) if File.exists?(path)
    data || {}
  end

  def JenkinsFile.write(data)
    path = get_path
    File.open(path, 'w') { |f| YAML.dump(data, f) }
  end
end
