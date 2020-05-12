begin
  require 'yaml'
  require 'pp'

  namespace :baremetal do

    desc "scan all ISPs for baremetals. You can optional pass a subset of providers, use ':' as separator"
    task :scan_isps, :provider do |t, args|
      baremetals_persist(baremetal_scan_isps(args.provider))
    end

    desc "check configuration state of of baremetals"
    task :check_config do |t|
      metals = baremetals
      metals.each do |host_id, host|
        puts ">>>  #{host_id} - #{host[:ipv4]}"
        ssh_detect(host)
        pp host[:fqdn]
      end
      baremetals_persist(metals)
    end

    desc "put host into rescue"
    task :rescue, :host do |t, args|
      baremetal_rescue(args.host)
    end

    desc "puts rescue into tmux"
    task :tmux_rescue, :hostparam do |t, args|
      host = baremetal_by_human_input(args.hostparam)

      sh %Q{tmux new-window -t baremetal -n "#{host[:isp][:id]}"}
      sh %Q{tmux send-keys -t baremetal "cd #{ROOT}; rake baremetal:rescue[#{host[:id] || host[:ipv4]}]"}
      sh %Q{tmux send-keys -t baremetal Enter}
    end

    desc "bootstrap in tmux"
    task :tmux_bootstrap, :hostparam, :disklayout do |t, args|
      throw "needs a disklayout" unless args.disklayout
      host = baremetal_by_human_input(args.hostparam)

      require 'tmpdir'
      cmd_file = File.join(Dir.tmpdir(), "baremetal-#{host[:ipv4]}")
      File.open(cmd_file, 'w') do |f|
        f.puts ". onhost/disklayout/#{args.disklayout}"
        f.puts ". onhost/install/ubuntu-focal"
        f.puts "reboot"
      end

      ssh_opts = %Q{-l root -i #{PRIVATE_SSH_KEY} -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oGlobalKnownHostsFile=/dev/null}
      sh %Q{tmux new-window -t baremetal -n "#{host[:isp][:id]}"}
      sh %Q{tmux send-keys -t baremetal "cd #{ROOT}; rake baremetal:rescue[#{host[:ipv4]}]; cat #{cmd_file}| ssh #{ssh_opts} #{host[:ipv4]} /bin/bash -l -s"}
      sh %Q{tmux send-keys -t baremetal Enter}
    end

    desc "list unhandled"
    task :unhandled do |t|
      baremetals.each do |host_id, host|
        puts host_id unless host[:fqdn]
      end
    end

    desc "bootstrap with custom image"
    task :custom_bootstrap, :hostparam, :image, :revision, :disk_layout do |t, args|
      custom_install(args[:hostparam], args[:image], args[:revision], args[:disk_layout])
    end

  end
rescue LoadError
  $stderr.puts "Baremetal API cannot be loaded. Skipping some rake tasks ..."
end
