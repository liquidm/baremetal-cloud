chef_zero.enabled true
local_mode false
chef_server_url   'http://127.0.0.1:8889'
node_name         'stickywicket'
client_key        "#{File.expand_path(File.join(File.dirname(__FILE__)))}/client.pem"

cookbook_path [
  "#{File.expand_path(File.join(File.dirname(__FILE__)))}/../cookbooks",
]