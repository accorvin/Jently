require 'bundler/setup'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new('spec')

namespace :jently do
  desc "Start Jently."
  task :start do
    sh 'ruby jently_control.rb start'
  end

  desc "Stop Jently."
  task :stop do
    sh 'ruby jently_control.rb stop'
  end
end
