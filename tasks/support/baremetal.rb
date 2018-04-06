require 'yaml'
require 'hetzner-api'
require 'ovh/rest'
require 'fileutils'
require 'leaseweb-rest-api'

def leaseweb_api
  @leaseweb_api ||= Hash[($conf[:leaseweb] || {}).map do |account, config|
    account_api = LeasewebAPI.new
    account_api.apiKeyAuth(config[:apikey])
    account_api.readPrivateKey(PRIVATE_SSH_KEY, false)
    ["leaseweb.#{account}", account_api]
  end]
end

def baremetals
  state = Hash.new do |h,k|
    h[File.basename(k)] = YAML.load_file(k) rescue {}
  end

  Dir.glob("#{STATEDIR}/hosts/*").each{|h| state[h] }

  state
end

def baremetals_persist(state)
  dirname="#{STATEDIR}/hosts"
  unless File.directory?(dirname)
    FileUtils.mkdir_p(dirname)
  end
  state.each do |host_id, host|
    File.open("#{dirname}/#{host_id}", 'w') {|f| f.write host.to_yaml }
  end
end

def baremetal_unique_id(hostname, state = baremetals)
  host, dc = hostname.scan(/^(.+?)\.(.+)$/).first
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
  target_state = state.clone
  known_ids = []

  if $conf[:hetzner] && $conf[:hetzner][:user]
    h = Hetzner::API.new($conf[:hetzner][:user], $conf[:hetzner][:password])
    hetzner_servers = h.servers?
    puts "#{hetzner_servers.length} servers at Hetzner"
    hetzner_servers.each do |e|
      print '.'
      s=e['server']
      tokens = s['dc'].scan(/(\w+)(\d)/)

      host = baremetal_by_id('hetzner', s['server_number'], target_state)
      host[:isp][:info] = s['product']
      host[:ipv4] = s['server_ip']

      naming_convention =  "#{s['product']}-.#{tokens[1][0]}#{tokens[0][1]}#{tokens[1][1]}.#{tokens[0][0]}".downcase

      baremetal_id = baremetal_unique_id(naming_convention, target_state)
      target_state[baremetal_id] = host
      known_ids << baremetal_id
    end
    puts ''
  end

  leaseweb_api.each do |account, api|
    resp = api.getV2DedicatedServers
    if resp['errorMessage']
      puts resp['errorMessage']
      next
    end

    metals=resp['servers']
    unless metals
      puts "no servers at leaseweb in #{account}?"
      next
    end
    puts "#{metals.length} servers at Leaseweb in #{account}"
    metals.each do |info|
      print '.'
      host = baremetal_by_id(account, info['id'], target_state)

      details = nil
      details = api.getV2DedicatedServer(info['id']) until details && !details['errorCode']

      host[:isp][:info] = "#{details['specs']['brand']} #{details['specs']['chassis']} #{details['specs']['cpu']['type'].split(' ').last} #{details['specs']['ram']['size']}#{details['specs']['ram']['unit']} #{details['specs']['hdd'].map{|hdd| "#{hdd['amount']}*#{hdd['size']}#{hdd['unit']} #{hdd['type']}"}.join(',')}"
      host[:ipv4] = info['networkInterfaces']['public']['ip'].split('/').first

      naming_convention = "#{info['contract']['internalReference']}.#{info['location']['rack']}.#{info['location']['site'].scan(/\w+/).first}".downcase

      baremetal_id = baremetal_unique_id(naming_convention, target_state)
      target_state[baremetal_id] = host
      known_ids << baremetal_id
    end
    puts ''
  end

  if $conf[:ovh]
    ovh = OVH::REST.new($conf[:ovh][:app_key], $conf[:ovh][:app_secret], $conf[:ovh][:consumer_key])
    ovh_servers = ovh.get('/dedicated/server')
    puts "#{ovh_servers.length} servers at OVH"
    ovh_servers.each do |id|
      print '.'
      status = ovh.get("/dedicated/server/#{id}/serviceInfos")['status']
      if status != 'ok'
        print "(#{id}: #{status})"
        next
      end
      metal = ovh.get("/dedicated/server/#{id}")
      details = ovh.get("/dedicated/server/#{id}/specifications/hardware")
      host = baremetal_by_id('ovh', metal['name'], target_state)
      host[:isp][:info] = "#{details['description']} #{details['diskGroups'].map{|d| d['description']}.join(';')}"
      host[:ipv4] = metal['ip']

      dc, dc_id = metal['datacenter'].scan(/^(.+?)(\d*)$/).first

      metal['rack']

      details['description'].split(' ')[0].gsub(/\-/,'')

      naming_convention = "#{metal['commercialRange']}-.#{dc_id}-#{metal['rack']}.#{dc}".downcase
      baremetal_id = baremetal_unique_id(naming_convention, target_state)
      target_state[baremetal_id] = host
      known_ids << baremetal_id
    end
    puts ''
  end
  # todo: use known_ids to clean out expired servers
  target_state
end
