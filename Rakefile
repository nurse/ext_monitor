require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rake/extensiontask"

task :build => :compile

Rake::ExtensionTask.new("ext_monitor") do |ext|
  ext.lib_dir = "lib/ext_monitor"
end

task :default => [:clobber, :compile, :spec]
