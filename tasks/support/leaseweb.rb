def leaseweb_init
  ($conf[:leaseweb] || {}).each do |country, config|
    account_api = LeasewebAPI.new
    account_api.apiKeyAuth(config[:apikey])
    account_api.readPrivateKey(PRIVATE_SSH_KEY, false)
    account = "leaseweb.#{country}"
    ssh_key = File.read("#{PRIVATE_SSH_KEY}.pub")

    baremetal_isps[account] = Class.new do
      define_singleton_method :scan do |state|
        target_state = {}

        # check for cloud servers
        cloud_servers = account_api.getV2VirtualServers
        if cloud_servers['errorMessage']
          throw "#{account}: #{resp['errorMessage']}"
        end
        cloud = cloud_servers['virtualServers']

        # dedicated
        resp = account_api.getV2DedicatedServers
        if resp['errorMessage']
          throw "#{account}: #{resp['errorMessage']}"
        end

        metals=resp['servers']
        unless metals or cloud
          puts "no servers at leaseweb in #{account}?"
          next
        end

        if metals
         puts "#{metals.length} servers at Leaseweb in #{account}"
         metals.each do |info|
           host = baremetal_by_id(account, info['id'], state)

           details = nil
           begin
             details = account_api.getV2DedicatedServer(info['id']) until details && !details['errorCode']
           rescue
             print 'e'
             retry
           end

           # remove brand from chassis name
           if details['specs'].key? 'brand'
             details['specs']['chassis'].gsub!(/#{Regexp.escape(details['specs']['brand'])}/i, '')
           end

           host[:isp][:info] = "#{details['specs']['brand'].strip} #{details['specs']['chassis'].strip} #{details['specs']['cpu']['type'].split(' ').last} #{details['specs']['ram']['size']}#{details['specs']['ram']['unit']} #{details['specs']['hdd'].map{|hdd| "#{hdd['amount']}*#{hdd['size']}#{hdd['unit']} #{hdd['type']}"}.join(',')}"
           host[:isp][:dc] = info['location']['site']
           host[:isp][:rack] = info['location']['rack']
           host[:ipv4] = info['networkInterfaces']['public']['ip'].split('/').first rescue nil
           naming_convention = "#{details['specs']['chassis'].gsub(/[^A-Za-z0-9]+/, '')}-#{info['location']['rack'].gsub(/[^A-Za-z0-9]+/, '')}-#{info['location']['site'].gsub(/[^0-9]+/, '')}-#{info['contract']['internalReference'].gsub(/[^A-Za-z0-9]+/, '') rescue "nr"}.#{info['location']['site'].gsub(/[^A-Za-z]+/, '')}".downcase

           baremetal_id = baremetal_unique_id(naming_convention, host, state)

           # add this machine to old state to avoid some weird edge cases
           state[baremetal_id] = host
           target_state[baremetal_id] = host
         end
          puts ''
        end

        # process cloud
        unless cloud
          puts "no cloud servers at leaseweb in #{account}?"
        else
          puts "#{cloud.length} cloud servers at Leaseweb in #{account}"
          cloud.each do |info|
            host = baremetal_by_id(account, info['id'], state)

            hardware = info['hardware']
            host[:isp][:info] = "#{hardware['cpu']['cores']} core #{hardware['memory']['amount']} #{hardware['memory']['unit'].strip} memory #{hardware['storage']['amount']} #{hardware['storage']['unit'].strip} storage"
            host[:isp][:dc] = info['dataCenter']
            info['ips'].each do |ip|
              if ip['version'] == 4 && ip['visibility'] == 'PUBLIC'
                host[:ipv4] = ip['ip']
              end
            end
            naming_convention = "vs-#{info['dataCenter'].gsub(/[^0-9]+/, '')}-#{info['id']}.#{info['dataCenter'].gsub(/[0-9-]+/, '')}".downcase

            baremetal_id = baremetal_unique_id(naming_convention, host, state)
            target_state[baremetal_id] = host
          end
          puts ''
        end


        target_state
      end

      define_singleton_method :rescue do |hostparam|
        host = baremetal_by_human_input(hostparam)
        id = host[:isp][:id]
        puts "putting #{id} into rescue"
        task = account_api.postV2RescueMode(id, 'GRML', ssh_key)
        throw task['errorMessage'] if task['errorMessage']

        puts "waiting for #{host[:ipv4]} to reboot"
        wait_for_ssh(host[:ipv4])
        puts "#{id} in rescue now"
      end
    end
  end
end
