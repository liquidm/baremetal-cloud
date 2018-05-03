def ovh_init
  if $conf[:ovh]
    ovh = OVH::REST.new($conf[:ovh][:app_key], $conf[:ovh][:app_secret], $conf[:ovh][:consumer_key])

    baremetal_isps["ovh"] = Class.new do
      define_singleton_method :scan do |state|
        target_state = {}

        ovh_servers = ovh.get('/dedicated/server')
        puts "#{ovh_servers.length} servers at OVH"
        ovh_servers.each do |id|
          status = ovh.get("/dedicated/server/#{id}/serviceInfos")['status']
          if status != 'ok'
            print "_"
            next
          end
          metal = ovh.get("/dedicated/server/#{id}")
          details = ovh.get("/dedicated/server/#{id}/specifications/hardware")
          host = baremetal_by_id('ovh', metal['name'], state)
          host[:isp][:info] = "#{details['description']} #{details['diskGroups'].map{|d| d['description']}.join(';')}"
          host[:isp][:dc] = metal['datacenter']
          host[:isp][:rack] = metal['rack']

          host[:ipv4] = metal['ip']

          dc, dc_id = metal['datacenter'].scan(/^(.+?)(\d*)$/).first

          details['description'].split(' ')[0].gsub(/\-/,'')

          naming_convention = "#{metal['commercialRange']}-#{dc_id}-#{metal['rack']}-.#{dc}".downcase
          baremetal_id = baremetal_unique_id(naming_convention, host, target_state.merge(state))
          target_state[baremetal_id] = host
        end
        puts ''

        target_state
      end

      define_singleton_method :rescue do |hostparam|
        host = baremetal_by_human_input(hostparam)
        name = host[:isp][:id]

        puts "putting #{name} into rescue"

        ovh.put("/dedicated/server/#{name}", 'bootId' => 1122, 'monitoring' => false)
        ovh.put("/dedicated/server/#{name}/serviceInfos", 'renew' => {'automatic' => true, 'forced' => false, 'period' => 1, 'deleteAtExpiration' => false})
        ovh.post("/dedicated/server/#{name}/reboot")
        wait_for_ssh(name)
        ovh.put("/dedicated/server/#{name}", 'bootId' => 1)
      end

    end
  end
end
