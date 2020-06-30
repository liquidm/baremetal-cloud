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

KNOWN_ISPS = {
  hetzner: {
    name: "Hetzner (hetzner.com)",
    keys: %i{user password},
  },
  ovh: {
    name: "OVH (ovh.com)",
    keys: %i{app_key app_secret consumer_key},
  },
  serverscom: {
    name: "Servers.com",
    keys: %i{mail token password},
  },
  leaseweb: {
    multiple: true,
    name: "Leaseweb (leaseweb.com)",
    keys: %i{apikey},
  },
}


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
  KNOWN_ISPS.each do |isp,isp_setup|
    if isp_setup[:multiple]
      puts "#{isp_setup[:name]} accounts configured: #{($conf[isp] && $conf[isp].keys.join(', ')) || "none"}"
    else
      puts "#{isp_setup[:name]}: #{!!$conf[isp]}"
    end
  end
end

def prompt(*args)
  print *args, ": "
  STDIN.gets.chomp
end

def yesno(*args)
  response = nil
  loop do
    response = prompt(*args," (Y/N)").upcase
    break if ['Y', 'N'].include? response
  end
  response == 'Y'
end

def prompt_config(isp_setup, isp_conf, isp_name)
  puts isp_name
  isp_setup[:keys].each do |isp_key|
    new_value = prompt("#{isp_key} (current '#{isp_conf[isp_key]}', blank to not touch, '.' to remove)")
    if new_value == '.'
      isp_conf.delete(isp_key)
    elsif new_value != ""
      isp_conf[isp_key] = new_value
    end
  end
end

desc "interactively setup a minimal config"
task :configure do
  local_conf = {}
  local_conf.deep_merge!(YAML.load_file(CONFIG_FILES[-1]).deep_symbolize_keys) if File.exist?(CONFIG_FILES[-1])

  KNOWN_ISPS.each do |isp, isp_setup|
    isp_conf = local_conf[isp] || ($conf[isp] || {})

    next unless yesno("Configure #{isp_setup[:name]}")

    if isp_setup[:multiple]
      loop do
        puts "#{isp_setup[:name]} - known accounts: #{isp_conf.keys.join(', ')}"
        subaccount = prompt "ID for subaccount (blank for done)"
        if subaccount != ""
          prompt_config(isp_setup, isp_conf[subaccount.to_sym] ||= {}, "#{isp_setup[:name]}[#{subaccount}]")
        else
          break
        end
      end
    else
      prompt_config(isp_setup, isp_conf, isp_setup[:name])
    end
    if isp_conf.values.all?{|r| r == ''}
      local_conf.delete(isp)
    else
      puts YAML.dump(isp_conf)
      if yesno("Keep this config for #{isp}")
        local_conf[isp] = isp_conf
      end
    end
  end

  %x{mkdir -p #{File.dirname(CONFIG_FILES[-1])}}
  File.write(CONFIG_FILES[-1],YAML.dump(local_conf))

  if File.exist?(PRIVATE_SSH_KEY)
    puts "SSH keys exists, keeping"
  else
    puts "No ssh key, generating now."
    puts "For OVH, please uploaded it in the web ui" if local_conf[:ovh]
    puts "Generating a private key. For OVH please upload it in the web ui"
    %x{mkdir -p #{File.dirname(PRIVATE_SSH_KEY)}}
    %x{ssh-keygen -t rsa -f #{PRIVATE_SSH_KEY} -N ''}
  end

  pem_file = "#{PRIVATE_SSH_KEY}.pub.pem"
  if !File.exist?(pem_file)
    puts "Also creating a PEM file for the SSH key"
    %x{ssh-keygen -f #{PRIVATE_SSH_KEY} -e -m pem > #{pem_file}}
  end
end
