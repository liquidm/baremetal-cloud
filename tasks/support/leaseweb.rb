def leaseweb_init
  ($conf[:leaseweb] || {}).each do |country, config|
    account_api = LeasewebAPI.new
    account_api.apiKeyAuth(config[:apikey])
    account_api.readPrivateKey(PRIVATE_SSH_KEY, false)
    account = "leaseweb.#{country}"
    puts "Configuring #{account}"

    baremetal_isps[account] = Class.new do
      define_singleton_method :scan do |state|
        target_state = {}

        resp = account_api.getV2DedicatedServers
        if resp['errorMessage']
          throw "#{account}: #{resp['errorMessage']}"
        end

        metals=resp['servers']
        unless metals
          puts "no servers at leaseweb in #{account}?"
          next
        end
        puts "#{metals.length} servers at Leaseweb in #{account}"
        metals.each do |info|
          print '.'
          host = baremetal_by_id(account, info['id'], state)

          details = nil
          details = account_api.getV2DedicatedServer(info['id']) until details && !details['errorCode']

          host[:isp][:info] = "#{details['specs']['brand']} #{details['specs']['chassis']} #{details['specs']['cpu']['type'].split(' ').last} #{details['specs']['ram']['size']}#{details['specs']['ram']['unit']} #{details['specs']['hdd'].map{|hdd| "#{hdd['amount']}*#{hdd['size']}#{hdd['unit']} #{hdd['type']}"}.join(',')}"
          host[:ipv4] = info['networkInterfaces']['public']['ip'].split('/').first rescue nil

          naming_convention = "#{details['specs']['chassis'].gsub(/\s/,'')}-#{info['contract']['internalReference']}.#{info['location']['rack']}.#{info['location']['site'].scan(/\w+/).first}".downcase

          baremetal_id = baremetal_unique_id(naming_convention, host, target_state)
          target_state[baremetal_id] = host
        end
        puts ''

        target_state
      end
    end
  end
end
