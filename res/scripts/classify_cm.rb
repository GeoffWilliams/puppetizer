#!/opt/puppetlabs/puppet/bin/ruby

# Use the puppetclassify gem to register a new Puppet Enterprise Compile Master
# See https://github.com/puppetlabs/puppet-classify
#
# Usage:
# ======
# ./classify_cm.rb COMPILE_MASTER_FQDN
#
# Optionally, you may specify a loadbalancer to use to prevent errors from
# pe_repo:
# 
# ./classify_cm.rb COMPILE_MASTER_FQDN LOADBALANCER_FQDN

require 'puppetclassify'

if ARGV.empty?
  abort("Must specify hostname to mark as a compile master")
end
compile_master = ARGV[0]

if ARGV.length == 2
  lb = ARGV[1]
else
  lb = false
end


def initialize_puppetclassify
  hostname = %x(facter fqdn).strip
  port = 4433

  # Define the url to the classifier API
  rest_api_url = "https://#{hostname}:#{port}/classifier-api"

  # We need to authenticate against the REST API using a certificate
  # that is whitelisted in /etc/puppetlabs/console-services/rbac-certificate-whitelist.
  # (https://docs.puppetlabs.com/pe/latest/nc_forming_requests.html#authentication)
  #  
  # Since we're doing this on the master,
  # we can just use the internal dashboard certs for authentication
  ssl_dir     = '/etc/puppetlabs/puppet/ssl'
  ca_cert     = "#{ssl_dir}/ca/ca_crt.pem"
  cert_name   = hostname
  cert        = "#{ssl_dir}/certs/#{cert_name}.pem"
  private_key = "#{ssl_dir}/private_keys/#{cert_name}.pem"

  auth_info = {
    'ca_certificate_path' => ca_cert,
    'certificate_path'    => cert,
    'private_key_path'    => private_key,
  }

  # wait upto 5 mins for classifier to become live...
  port_open = false
  Timeout::timeout(300) do
    while not port_open
      begin
        s = TCPSocket.new(hostname, port)
        s.close
        port_open = true
        puts "Classifier signs of life detected, proceeding to classify..."
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
        puts "connection refused, waiting..."
        sleep(1)
      end
    end
  end

  puppetclassify = PuppetClassify.new(rest_api_url, auth_info)

  # return
  puppetclassify
end

puppetclassify = initialize_puppetclassify

# Get the PE Master group from the API
#   1. Get the id of the PE Master group
#   2. Use the id to fetch the group
pe_master_group_id = puppetclassify.groups.get_group_id('PE Master')
pe_master_group = puppetclassify.groups.get_group(pe_master_group_id)

# IF NEEDED, add the new hostname
update_needed = true
pe_master_group["rule"].each { | rule |
  if rule[2] == compile_master
    update_needed = false
  end
}

if update_needed
  pe_master_group["rule"].push(Array.new(["=", "name", compile_master]))
else
  puts "#{compile_master} already pinned as PE Master - no rule change needed"
end  

if lb
  pe_master_group["classes"]["pe_repo"]["compile_master_pool_address"] = lb
end

# Build the hash to pass to the API
group_delta = {
  'id'      => pe_master_group_id,
  'rule'    => pe_master_group["rule"],
  'classes' => pe_master_group["classes"]
}


# Pass the hash to the API to assign the pe_repo::platform classes
puppetclassify.groups.update_group(group_delta)

puts "Normal exit"
