def ovh_init
  if $conf[:ovh]
    puts "configuring OVH"
    ovh = OVH::REST.new($conf[:ovh][:app_key], $conf[:ovh][:app_secret], $conf[:ovh][:consumer_key])

    baremetal_isps["ovh"] = Class.new do
      define_singleton_method :scan do |state|
        target_state = {}

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
          host = baremetal_by_id('ovh', metal['name'], state)
          host[:isp][:info] = "#{details['description']} #{details['diskGroups'].map{|d| d['description']}.join(';')}"
          host[:ipv4] = metal['ip']

          dc, dc_id = metal['datacenter'].scan(/^(.+?)(\d*)$/).first

          metal['rack']

          details['description'].split(' ')[0].gsub(/\-/,'')

          naming_convention = "#{metal['commercialRange']}-.#{dc_id}-#{metal['rack']}.#{dc}".downcase
          baremetal_id = baremetal_unique_id(naming_convention, host, target_state)
          target_state[baremetal_id] = host
        end
        puts ''

        target_state
      end
    end
  end
end
