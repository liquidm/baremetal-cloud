def scm_legacy_api_get_net_image(id, path)
  uri = URI("https://portal.servers.com/rest/hosts/#{id}/network_configuration.iso")

  req = Net::HTTP::Get.new(uri)
  req['Content-Type'] = "application/json"
  req['X-User-Email'] = $conf[:serverscom][:mail]
  req['X-User-Token'] = $conf[:serverscom][:token]

  Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) {|http|
    resp = http.request(req)
    open(path, "wb") do |file|
      file.write(resp.body)
    end
  }
end


def scm_legacy_api(method, uri)
  uri = URI(uri)

  if method == "POST"
    req = Net::HTTP::Post.new(uri)
    req.body = "{}"
  else
    req = Net::HTTP::Get.new(uri)
  end
  req['X-Sc-Verification'] = $conf[:serverscom][:password]
  req['Content-Type'] = "application/json"
  req['X-User-Email'] = $conf[:serverscom][:mail]
  req['X-User-Token'] = $conf[:serverscom][:token]

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) {|http|
    http.request(req)
  }

  return JSON.parse(res.body)['data']
end

def serverscom_init
  if $conf[:serverscom] && $conf[:serverscom][:mail]
    #h = serverscom::API.new($conf[:serverscom][:mail], $conf[:serverscom][:password])

    isp_id = 'serverscom'

    @isps[isp_id] = Class.new do
      define_singleton_method :scan do |state|
        target_state = {}

        serverscom_servers = scm_legacy_api("GET", "https://portal.servers.com/rest/hosts")
        puts "#{serverscom_servers.length} servers at servers.com"

        serverscom_servers.each do |s|
          tokens = s['location']['name'].scan(/(\w+)(\d)/)
          host = baremetal_by_id(isp_id, s['id'], state)
          host[:isp][:info] = s['conf']
          host[:isp][:dc], host[:isp][:rack] = tokens[0].join(), s['location']['id'] # TODO
          host[:ipv4] = s['networks'].select{|net| net['pool_type']=="public"}.first['host_ip']

          # old naming convention
          naming_convention =  "#{s['conf'].split[1].split("-")[0].first(5)}-#{s['location']['id']}-#{tokens[0].join()}-scm-.#{tokens[0][0]}".downcase

          # new naming convention
          # <max 5 chars for chassis type>-<rack-id>-<isp-id>.<dc>-<max 3  chars for isp>.lqm.io
          #naming_convention = "#{s['conf'].split[1].split("-")[0].first(5)}-#{s['location']['id']}-.#{tokens[0].join()}-scm".downcase

          target_state[baremetal_unique_id(naming_convention, host, target_state.merge(state))] = host
        end
        puts ''

        target_state
      end

      define_singleton_method :rescue do |hostparam|
        host = baremetal_by_human_input(hostparam)
        id = host[:isp][:id]
        ip = host[:ipv4]

        # idea:
        # set idrac public POST https://portal.servers.com/rest/hosts/50857/features/oob_public_access/activate
        # status check
        # GET https://portal.servers.com/rest/hosts/50857/features
        # wait for idrac
        # boot rescue system through idrac
        while (not (idrac_status = scm_legacy_api("GET", "https://portal.servers.com/rest/hosts/#{id}/features")
          .select{|i| i['name'] == "oob_public_access" }
          .first["state"]) == "activated")
          if idrac_status == "deactivated"
            # enabling idrac public access
            scm_legacy_api("POST", "https://portal.servers.com/rest/hosts/#{id}/features/oob_public_access/activate")
          end
          # waiting till idrac will be present in public
          puts "iDRAC still not in public mode (#{idrac_status})..."
          sleep 20
        end

        idrac_credentials = scm_legacy_api("GET", "https://portal.servers.com/rest/hosts/#{id}/drac_credentials")
        # servers.com not support DHCP, however they provide iso image with network settings for every server
        scm_legacy_api_get_net_image(id, "/tmp/scm-net-#{id}.iso")

        # prepare iso for boot

        #puts %x{racadm -r #{idrac_credentials['ip']} -u #{idrac_credentials['login']} -p #{idrac_credentials['password']} getsysinfo}
        #
        # sequence to boot from iso
        #puts %x{racadm -r #{idrac_credentials['ip']} -u #{idrac_credentials['login']} -p #{idrac_credentials['password']} set iDRAC.VirtualMedia.Attached Attached}
        #puts %x{racadm -r #{idrac_credentials['ip']} -u #{idrac_credentials['login']} -p #{idrac_credentials['password']} remoteimage -c -l http://1.2.3.4/your-server-with-bootloader/rescue.iso}
        #puts %x{racadm -r #{idrac_credentials['ip']} -u #{idrac_credentials['login']} -p #{idrac_credentials['password']} set iDRAC.VirtualMedia.BootOnce 1}
        #puts %x{racadm -r #{idrac_credentials['ip']} -u #{idrac_credentials['login']} -p #{idrac_credentials['password']} set iDRAC.ServerBoot.FirstBootDevice VCD-DVD}
        #puts %x{racadm -r #{idrac_credentials['ip']} -u #{idrac_credentials['login']} -p #{idrac_credentials['password']} serveraction powercycle}

        fingerprint = %x{ssh-keygen -E md5 -lf #{PRIVATE_SSH_KEY}.pub}.split[1].gsub(/^.*?\:/,'')
        puts "putting #{id} into rescue, ssh fingerprint #{fingerprint}"

        # command for putting to servers.com based rescuesystem to rescue mode
        # scm_legacy_api("POST", "https://portal.servers.com/rest/hosts/#{id}/enter_rescue_mode")

        wait_for_ssh(ip)
      end
    end
  end
end
