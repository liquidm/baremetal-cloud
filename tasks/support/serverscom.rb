def serverscom_init
  if $conf[:serverscom] && $conf[:serverscom][:mail]
    #h = serverscom::API.new($conf[:serverscom][:mail], $conf[:serverscom][:password])

    isp_id = 'serverscom'

    @isps[isp_id] = Class.new do
      define_singleton_method :scan do |state|
        target_state = {}

        uri = URI("https://portal.servers.com/rest/hosts")
        req = Net::HTTP::Get.new(uri)
        req['Content-Type'] = "application/json"
        req['X-User-Email'] = $conf[:serverscom][:mail]
        req['X-User-Token'] = $conf[:serverscom][:token]

        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) {|http|
          http.request(req)
        }

        serverscom_servers = JSON.parse(res.body)['data']
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

        fingerprint = %x{ssh-keygen -E md5 -lf #{PRIVATE_SSH_KEY}.pub}.split[1].gsub(/^.*?\:/,'')
        puts "putting #{id} into rescue, ssh fingerprint #{fingerprint}"

        uri = URI("https://portal.servers.com/rest/hosts/#{id}/enter_rescue_mode")
        req = Net::HTTP::Post.new(uri)
        req['Content-Type'] = "application/json"
        req['X-User-Email'] = $conf[:serverscom][:mail]
        req['X-User-Token'] = $conf[:serverscom][:token]
        req['X-Sc-Verification'] = $conf[:serverscom][:password]
        req.body = "{}"

        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) {|http|
          http.request(req)
        }

        wait_for_ssh(ip)
      end
    end
  end
end
