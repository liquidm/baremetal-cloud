def hetzner_init
  if $conf[:hetzner] && $conf[:hetzner][:user]
    h = Hetzner::API.new($conf[:hetzner][:user], $conf[:hetzner][:password])

    isp_id = 'hetzner'

    @isps[isp_id] = Class.new do
      define_singleton_method :scan do |state|
        target_state = {}

        hetzner_servers = h.servers?
        puts "#{hetzner_servers.length} servers at Hetzner"
        hetzner_servers.each do |e|
          s=e['server']
          tokens = s['dc'].scan(/(\w+)(\d)/)

          host = baremetal_by_id(isp_id, s['server_number'], state)
          host[:isp][:info] = s['product']
          host[:isp][:dc], host[:isp][:rack] = s['dc'].split('-') # TODO
          host[:ipv4] = s['server_ip']

          naming_convention =  "#{s['product'].split.last}-#{tokens[1][0]}#{tokens[0][1]}#{tokens[1][1]}-.#{tokens[0][0]}".downcase

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

        h.disable_rescue!(ip)
        # todo: it's just a hack, need to fork hetzner-api and clean it up
        rescue_state = h.enable_rescue!(ip, 'linux', 64, fingerprint)
        throw rescue_state if rescue_state['error']
        h.reset!(ip, :hw)
        wait_for_ssh(ip)
      end
    end
  end
end
