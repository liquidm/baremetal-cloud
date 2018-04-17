require 'yaml'
require 'hetzner-api'
require 'ovh/rest'
require 'fileutils'
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
  existing_host_id, existing_host = state.find{|id,h| host_info[:isp][:id] == h[:isp][:id] && host_info[:isp][:name] == h[:isp][:name]}
  return existing_host_id if existing_host_id

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

  "#{host_type}#{host_id}.#{dc}"
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
  target_state = {}
  known_ids = []

  baremetal_isps.each do |isp_account, isp_api|
    known_baremetals = isp_api.scan(state)
    known_baremetals.each do |baremetal_id, isp_host_info|
      target_state[baremetal_id] = (state[baremetal_id] || {}).merge(isp_host_info)
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
end
