begin
  require 'yaml'
  require 'pp'

  namespace :baremetal do

    desc "scan all ISPs for baremetals"
    task :scan_isp do |t|
      baremetals_persist(baremetal_scan_isps)
    end

  end
rescue LoadError
  $stderr.puts "Baremetal API cannot be loaded. Skipping some rake tasks ..."
end
