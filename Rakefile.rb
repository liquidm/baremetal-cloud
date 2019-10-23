# encoding: utf-8

require 'rubygems'
require 'pp'
require 'json'
require 'yaml'
require 'active_support'
require 'active_support/core_ext'

if Process.euid > 0
  begin
    require 'bundler'
  rescue LoadError
    $stderr.puts "Bundler could not be loaded. Please make sure to run ./scripts/bootstrap"
    exit(1)
  end
  Bundler.setup if defined?(Bundler)
end

# The top of the repository checkout
ROOT = File.expand_path("..", __FILE__)
STATEDIR = File.expand_path("../baremetal-state", ROOT)
PRIVATE_SSH_KEY = File.expand_path("support/id_rsa", STATEDIR)

CONFIG_FILES = [
  File.join(ROOT, 'defaults.yml'),
  File.join(STATEDIR, 'config.yml'),
]

$conf = {}
CONFIG_FILES.each do |config_yml|
  $conf.deep_merge!(YAML.load_file(config_yml).deep_symbolize_keys) if File.exist?(config_yml)
end

# make rake more silent
RakeFileUtils.verbose_flag = false

# support files
Dir[ File.join(File.dirname(__FILE__), 'tasks', 'support', '*.rb') ].sort.each do |f|
  require f
end

# tasks
Dir[ File.join(File.dirname(__FILE__), 'tasks', '*.rake') ].sort.each do |f|
  load f
end

sh "tmux new-session -d -s 'baremetal'  2>/dev/null|| true"

task :default do
  puts "baremetal cloud"
  puts "---------------"
  puts "ROOT=#{ROOT}"
  puts "CONFIG_FILES"
  CONFIG_FILES.each do |config_yml|
    puts "  #{config_yml}: #{File.exist?(config_yml)}"
  end
  puts "STATEDIR=#{STATEDIR}: #{File.directory?(STATEDIR)}"
  puts "PRIVATE_SSH_KEY=#{PRIVATE_SSH_KEY}: #{File.exist?(PRIVATE_SSH_KEY)}"
  puts
  puts "Hetzner account configured:    #{!!$conf[:hetzner]}"
  puts "OVH account configured:        #{!!$conf[:ovh]}"
  puts "Soyoustart account configured: #{!!$conf[:soyoustart]}"
  puts "Leaseweb accounts configured:  #{($conf[:leaseweb] && $conf[:leaseweb].keys.join(', ')) || "none"}"
end
