#!/usr/bin/env ruby
# puppetizer
# =====
# SIMPLE way of installing PE over SSH


require 'inistyle'
require 'net/ssh/simple'
require 'escort'
require 'erb'
require 'tempfile'
module Puppetizer
  class Puppetizer < ::Escort::ActionCommand::Base

    @@install_puppet_template     = './templates/install_puppet.sh.erb'
    @@install_pe_master_template  = './templates/install_pe_master.sh.erb'
    @@puppet_status_template      = './templates/puppet_status.sh.erb'
    @@r10k_yaml_template          = './templates/r10k.yaml.erb'
    @@run_r10k_template           = './templates/run_r10k.sh.erb'
    @@csr_attributes_template     = './templates/csr_attributes.yaml.erb'
    @@setup_code_manager_template = './templates/setup_code_manager.sh.erb'

    @@puppet_path         = '/opt/puppetlabs/puppet/bin'
    @@puppet_etc          = '/etc/puppetlabs/'
    @@puppet_confdir      = "#{@@puppet_etc}/puppet"
    @@puppet_r10k_yaml    = "#{@@puppet_etc}/r10k/r10k.yaml"
    @@inifile = 'inventory/hosts'
    
    def initialize(options, arguments)
      @options = options
      @arguments = arguments
    
      @ssh_opts = {
        :user               => @options[:global][:options][:ssh_username], 
        :auth_methods       => [
          "none", 
          "publickey", 
          #"password"
        ],
        :operation_timeout  => 0,
        :timeout            => 20*60,
      }

      if File.exists?(@@inifile)
        @myini = IniStyle.new('inventory/hosts')
      else
        raise Escort::UserError.new("Inventory file not found at #{@@inifile}")
      end
    end

    def setup_csr_attributes(host, csr_attributes, data)
      challenge_password = @options[:global][:commands][command_name][:options][:challenge_password]
      if csr_attributes or challenge_password
        Escort::Logger.output.puts "Setting up CSR attributes on #{host}"
        f = Tempfile.new("puppetizer")
        begin
          f << ERB.new(read_template(@@csr_attributes_template), nil, '-').result(binding)
          f.close
          ssh(host, "mkdir -p #{@@puppet_confdir}")
          scp(host, f.path, "#{@@puppet_confdir}/csr_attributes.yaml")
        ensure
          f.close
          f.unlink
        end
      end
    end

    def install_puppet(host, csr_attributes = false, data={})
      Escort::Logger.output.puts "Installing puppet agent on #{host}" 
      puppetmaster = @options[:global][:commands][command_name][:options][:puppetmaster]
  #    challenge_password = @options[:global][:commands][command_name][:options][:challenge_password]
  #    csr_attributes |= challenge_password
      setup_csr_attributes(host, csr_attributes, data)    
      ssh(host, ERB.new(read_template(@@install_puppet_template), nil, '-').result(binding))
    end

    def find_pe_tarball
      tarballs = Dir.glob("./puppet-enterprise-20*.tar.gz")
      if tarballs.empty?
        raise Escort::UserError.new("Please download Puppet Enterprise and put the tarball in #{Dir.pwd}")
      else
        tarballs.last
      end
    end

    def read_template(template)
      File.open(template, 'r') { |file| file.read }
    end

    def install_pe(host, csr_attributes, data)
      Escort::Logger.output.puts "Installing Puppet Enterprise on #{host}"

      # variables in scope for ERB
      password = @options[:global][:commands][command_name][:options][:console_admin_password]
      deploy_code = data.has_key?('deploy_code')
      control_repo = @options[:global][:commands][command_context[0]][:options][:control_repo]


      # SCP the installer
      scp(host, find_pe_tarball, "/tmp/")

      setup_csr_attributes(host, csr_attributes, data)  


      # run the PE installer
      ssh(host, ERB.new(read_template(@@install_pe_master_template), nil, '-').result(binding))

      # run puppet to finalise configuration
      ssh(host, "#{@@puppet_path}/puppet agent -t")

      if deploy_code
        setup_code_manager(host)
      end
    end

    def defrag_line(d)
      # read the input line-wise (it *will* arrive fragmented!)
      (@buf ||= '') << d
      while line = @buf.slice!(/(.*)\r?\n/)
        # how to handle sudo http://stackoverflow.com/a/4235463
        #if data =~ /^\[sudo\] password for user:/
        #  channel.send_data 'your_sudo_password'
        #else
        Escort::Logger.output.puts line.strip #=> "hello stderr"
      end
    end

    def port_open?(ip, port)
      begin
        Timeout::timeout(1) do
          begin
            s = TCPSocket.new(ip, port)
            s.close
            return true
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError
            return false
          end
        end
      rescue Timeout::Error
      end

      return false
    end

    def scp(host, local_file, remote_file)
      if port_open?(host,22)
        begin
          # local variables are visible in instance-eval but instance ones are not...
          # see http://stackoverflow.com/questions/3071532/how-does-instance-eval-work-and-why-does-dhh-hate-it
          ssh_opts = @ssh_opts
          Net::SSH::Simple.sync do
            scp_put(host, local_file, remote_file, ssh_opts) do |sent, total|
              Escort::Logger.output.puts "Bytes uploaded: #{sent} of #{total}"
            end
          end
        rescue Net::SSH::Simple::Error => e
          if e.message =~ /AuthenticationFailed/
            error_message = "Authentication failed for #{ssh_opts[:user]}@#{host}, key loaded?"
          else
            error_message = e.message
          end
          Escort::Logger.error.error error_message
        end
      else
        Escort::Logger.error.error "host #{host} not responding to SSH"
      end
    end

    def ssh(host, cmd)
      if port_open?(host,22)
        begin
          ssh_opts = @ssh_opts
          r = Net::SSH::Simple.sync do
            ssh(host, cmd, ssh_opts) do |e,c,d|
              case e
                when :start
                  #puts "CONNECTED"
                when :stdout, :stderr
                  defrag_line(d)
                  :no_append
                # :exit_code is triggered when the remote process exits normally.
                # it does *not* trigger when the remote process exits by signal!
                when :exit_code
                  #puts d #=> 0
          
                # :exit_signal is triggered when the remote is killed by signal.
                # this would normally raise a Net::SSH::Simple::Error but
                # we suppress that here by returning :no_raise
                when :exit_signal
                  #puts d  # won't fire in this example, could be "TERM"
                  :no_raise
          
                  # :finish triggers after :exit_code when the command exits normally.
                   # it does *not* trigger when the remote process exits by signal!
                when :finish
                  #puts "we are finished!"
              end
            end
          end
        rescue Net::SSH::Simple::Error => e
          if e.message =~ /AuthenticationFailed/
            error_message = "Authentication failed for #{ssh_opts[:user]}@#{host}, key loaded?"
          else
            error_message = e.message
          end
          Escort::Logger.error.error "NNN" + error_message
        end
      else
        Escort::Logger.error.error "host #{host} not responding to SSH"
      end
    end

    

    # read the inventory
    def puppetize(section_key)
      if @myini.sections.include?(section_key)
        section = @myini[section_key.downcase]
        case section_key
        when "puppetmasters"
          @myini[section_key].each do |r|
            hostname, csr_attributes, data = InventoryParser::parse(r)
            install_pe(hostname, csr_attributes, data)
          end
        when "agents"
          @myini[section_key].each do |r|
            hostname, csr_attributes, data = InventoryParser::parse(r)
            install_puppet(hostname, csr_attributes, data)
          end
        else
          Escort::Logger.error.error "Unknown section: " + section
        end
      else
        Escort::Logger.error.error "NO SUCH SECTION #{section}"
      end 
    end

    def status()
      @myini.sections.each do |section|
        @myini[section].each do |k|
          print "host #{k} status: "
          ssh(k, ERB.new(read_template(@@puppet_status_template), nil, '-').result(binding))
        end
      end
    end

    def setup_r10k(host)
      Escort::Logger.output.puts "Setting up R10K on #{host}"
      control_repo = @options[:global][:commands][command_context[0]][:options][:control_repo]

      contents = ERB.new(read_template(@@r10k_yaml_template), nil, '-').result(binding)
      file = Tempfile.new('puppetizer')
      file.sync = true
      begin
        file.write(contents)
        scp(host, file.path, @@puppet_r10k_yaml)
        ssh(host, ERB.new(read_template(@@run_r10k_template), nil, '-').result(binding))
      ensure
        file.close
        file.unlink   # deletes the temp file
      end
    end

    def setup_code_manager(host)
      Escort::Logger.output.puts "Setting up Code Manager on #{host}"
      
      ssh(host, ERB.new(read_template(@@setup_code_manager_template), nil, '-').result(binding))

    end

    def action_setup_r10k()
      section_key = "puppetmasters"

      if @myini.sections.include?(section_key)
        section = @myini[section_key]
        @myini[section_key].each do |host,v|
          setup_r10k(host)
        end
      end
    end
  end

  class InventoryParser
    @@csr_attributes=[
      'pp_uuid',
      'pp_instance_id',
      'pp_image_name',
      'pp_preshared_key',
      'pp_cost_center',
      'pp_product',
      'pp_project',
      'pp_application',
      'pp_service',
      'pp_employee',
      'pp_created_by',
      'pp_environment',
      'pp_role',
      'pp_software_version',
      'pp_department',
      'pp_cluster',
      'pp_provisioner',
      'pp_region',
      'pp_datacenter',
      'pp_zone',
      'pp_network',
      'pp_securitypolicy',
      'pp_cloudplatform',
      'pp_apptier',
      'pp_hostname',
    ]

    def self.csr_attributes
      @@csr_attributes
    end

    # parse a space delimited row and return tuple:
    # - hostname
    # - csr_attributes (true if found else false)
    # - hash (hash of all found attributes)
    def self.parse(row)
      split_row = row.split(/\s+/)
      hash = {}
      hostname = split_row.shift  
      csr_attributes = false
      split_row.each do | s |
        if s.include?('=')
          kvp=s.split('=')
          hash[kvp[0]]=kvp[1]
          if self.csr_attributes.include?(kvp[0])
            csr_attributes = true
          end
        else
          hash[s]=true
        end
      end
      return hostname, csr_attributes, hash
    end

  end
end
