def check_ping(ipaddress)
  %x(ping -c 1 -W 5 #{ipaddress})
  reachable = $?.exitstatus == 0
  sleep(1)
  reachable
end

def wait_with_ping(ipaddress, reachable)
  print "waiting for machine to #{reachable ? "boot" : "shutdown"} "

  while check_ping(ipaddress) != reachable
    print "."
  end

  print "\n"
end

def ssh_detect(host)
  File.chmod(0400, PRIVATE_SSH_KEY) # for good measure
  ssh_opts = %{-oBatchMode=yes -o "StrictHostKeyChecking no" -o "UserKnownHostsFile /dev/null" -o "GlobalKnownHostsFile /dev/null" #{host[:ipv4]} hostname -f 2>/dev/null}

  unless check_ping(host[:ipv4])
    host[:down] = true
    return
  end

  %x{nmap -p 22 -sT -Pn #{host[:ipv4]}| grep 'open  ssh'}
  unless $?.success?
    host[:down] = true
    return
  end

  host.delete(:down)

  fqdn = %x{ssh #{ssh_opts}}.chomp
  if $?.success?
    host[:fqdn] = fqdn
    return
  end

  fqdn = %x{ssh -l root -i #{PRIVATE_SSH_KEY} #{ssh_opts}}.chomp
  if $?.success?
    host[:rescue] = true
    return
  end
end

def wait_for_ssh(fqdn)
  wait_with_ping(fqdn, false)
  wait_with_ping(fqdn, true)
  print "waiting for ssh to be accessible "
  loop do
    print "."
    system("nmap -p 22 -sT -Pn #{fqdn} | grep 'open  ssh' &> /dev/null")
    break if $?.exitstatus == 0
    sleep 5
  end
  print "\n"
  sleep 5
end
