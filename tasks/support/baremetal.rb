require 'yaml'
require 'hetzner-api'
require 'ovh/rest'
require 'soyoustart/rest'
require 'leaseweb-rest-api'
require 'fileutils'

def sorted_hash(v)
  if v.is_a? Hash
    Hash[v.map{|k,v| [k, sorted_hash(v)]}.sort]
  else
    v
  end
end

def baremetal_isps
  unless @isps
    @isps = {}

    # TODO: generic bootstrap
    hetzner_init
    leaseweb_init
    soyoustart_init
    ovh_init
  end
  @isps
end

def baremetals
  state = Hash.new do |h,k|
    h[File.basename(k)] = YAML.load_file(k) rescue {}
  end

  puts "#{STATEDIR}/hosts/*"
  Dir.glob("#{STATEDIR}/hosts/*").each{|h| state[h] }

  state
end

def baremetals_persist(state)
  dirname="#{STATEDIR}/hosts"
  unless File.directory?(dirname)
    FileUtils.mkdir_p(dirname)
  end
  state.each do |host_id, host|
    File.open("#{dirname}/#{host_id}", 'w') {|f| f.write sorted_hash(host).to_yaml }
  end
end

def baremetal_unique_id(pattern, host_info, state = baremetals)
  existing_host_id, existing_host = state.find do |id,h|
    begin
      host_info[:isp][:id] == h[:isp][:id] && host_info[:isp][:name] == h[:isp][:name]
    rescue => e
      pp h
      pp host_info
      throw e
    end
  end

  if existing_host_id
    print "."
    return existing_host_id
  end

  host, dc = pattern.scan(/^(.+?)\.(.+)$/).first
  host_type, host_id = host.scan(/^(.+?)(\d*)$/).first
  isp_geo = dc.split('.').last

  assigned_ids = {}

  state.keys.each do |assigned_id|
    a_host, a_dc = assigned_id.scan(/^(.+?)\.(.+)$/).first
    a_host_type, a_host_id = a_host.scan(/^(.+?)(\d*)$/).first
    a_isp_geo = a_dc.split('.').last

    if isp_geo == a_isp_geo
      assigned_ids[assigned_id] = a_host_id.to_i
    end
  end

  if host_id == nil || host_id == 0 || host_id == ""
    check = ([0] + assigned_ids.values).uniq
    host_id = check.max % 128
    host_id += 1 while check.include? host_id
  end

  unique_id = "#{host_type}#{host_id}.#{dc}"
  print "+[#{unique_id}]"
  unique_id
end

def baremetal_by_id(isp, id, state = baremetals)
  state.values.find{|s| s[:isp] && s[:isp][:name] == isp && s[:isp][:id] == id} || {
    isp: {
      name: isp,
      id: id,
    },
  }
end

def baremetal_scan_isps(state = baremetals)
  puts "scannig isps, #{baremetals.size} in local state going in."
  target_state = {}
  known_ids = []

  baremetal_isps.each do |isp_account, isp_api|
    known_baremetals = isp_api.scan(state)
    known_baremetals.each do |baremetal_id, isp_host_info|
      target_state[baremetal_id] = (state.key?(baremetal_id) ? state[baremetal_id] : {}).merge(isp_host_info)
      target_state[baremetal_id][:id] = baremetal_id # helps to have it in the file
      known_ids << baremetal_id
    end
  end

  expired_hosts = state.keys - target_state.keys
  if expired_hosts.size > 0
    puts "There are #{expired_hosts.size} unknown nodes, removing them now"
    dirname="#{STATEDIR}/hosts"
    expired_hosts.each do |host_id|
      puts host_id
      target_state.delete(host_id)
      FileUtils.rm("#{dirname}/#{host_id}")
    end
  end

  puts "#{target_state.size} active baremetals in your accounts"
  target_state
end


def baremetal_by_human_input(hostparam)
  hostparam = YAML.load_file(hostparam) rescue hostparam

  if hostparam.is_a? Hash
    hostparam
  elsif hostparam.is_a? String
    bm = baremetals
    if bm.key? hostparam
      bm[hostparam]
    else
      bm.values.find do |h|
        h[:fqdn] == hostparam || h[:ipv4] == hostparam || h[:isp][:id] == hostparam
      end
    end
  end
end

def baremetal_rescue(hostparam)
  host = baremetal_by_human_input(hostparam)

  puts "Using #{host.to_yaml}"

  baremetal_isps[host[:isp][:name]].rescue(host)
  ssh_opts = %Q{-oBatchMode=yes -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oGlobalKnownHostsFile=/dev/null}
  loop do
    begin
      sh "scp -i #{PRIVATE_SSH_KEY} #{ssh_opts} -r #{ROOT}/onhost root@#{host[:ipv4]}:."
      sh "ssh -i #{PRIVATE_SSH_KEY} #{ssh_opts} root@#{host[:ipv4]} onhost/setup/rescue-env"
      break
    rescue
      puts "Looks like ssh isn't really up yet... retrying in 5"
      sleep 5
    end
  end
end

def custom_install(hostparam, image, revision, disk_layout)
  host = baremetal_by_human_input(hostparam)
  ssh_opts = %Q{-i #{PRIVATE_SSH_KEY} -oBatchMode=yes -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oGlobalKnownHostsFile=/dev/null}
  revision = revision || "master"
  disklayout = disklayout || "single-disk"

  raise "needs a host " unless host
  raise "needs an image" unless image

  if (File.exist?("../baremetal-state/images/#{image}"))
    image_support_files = File.expand_path("../baremetal-state/images/#{image}")
  else
    raise "image support files missing"
  end

  # copy image support files
  sh "scp #{ssh_opts} -r #{image_support_files} root@#{host[:ipv4]}:"
  # check if image dir has been copied
  sh "ssh #{ssh_opts} root@#{host[:ipv4]} [ -d /root/#{image} ] && echo 'image dir exists' || echo 'image dir does not exist'"

  script_path = File.join('', 'root' image)
  sh %{ssh #{ssh_opts} root@#{host[:ipv4]} `which test` -e #{script_path}} do |ok, _|
    raise "script path does not exist on destination machine" unless ok
  end

  env_vars = {
      custom_squash_fs_image_revision: revision,
      custom_squash_fs_image_script: File.join(script_path, 'install.sh'),
  }.map{|k, v| "export #{k.to_s.upcase}=#{v}"}

  cmd_file = File.join(Dir.tmpdir(), "baremetal-#{host[:ipv4]}")
  File.open(cmd_file, 'w') do |f|
    env_vars.each do |env|
      f.puts env
    end
    f.puts ". onhost/disklayout/#{disklayout}"
    f.puts ". onhost/install/ubuntu-bionic"
    f.puts "shutdown -r 1"
  end

  sh %Q{cat #{cmd_file}| ssh #{ssh_opts} root@#{host[:ipv4]} /bin/bash -l -s}

end
