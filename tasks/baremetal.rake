begin
  require 'yaml'
  require 'pp'

  namespace :baremetal do

    desc "scan all ISPs for baremetals"
    task :scan_isps do |t|
      baremetals_persist(baremetal_scan_isps)
    end

    desc "check configuration state of of baremetals"
    task :check_config do |t|
      metals = baremetals
      metals.each do |host_id, host|
        puts ">>>  #{host[:ipv4]}"
        ssh_detect(host)
        pp host[:fqdn]
      end
      baremetals_persist(metals)
    end

    desc "put host into rescue"
    task :rescue, :host do |t, args|
      baremetal_rescue(args.host)
    end
  end
rescue LoadError
  $stderr.puts "Baremetal API cannot be loaded. Skipping some rake tasks ..."
end
