#!/usr/bin/env ruby
# puppetizer
# =====
# SIMPLE way of installing PE over SSH


require 'inistyle'
require 'net/ssh/simple'
require 'escort'
require 'erb'
require 'tempfile'
require 'ruby-progressbar'
require 'time'

module Puppetizer
  class Puppetizer < ::Escort::ActionCommand::Base

    @@install_puppet_template     = './templates/install_puppet.sh.erb'
    @@install_pe_master_template  = './templates/install_pe_master.sh.erb'
    @@install_cm_template         = './templates/install_cm.sh.erb'
    @@pe_postinstall_template     = './templates/pe_postinstall.sh.erb'
    @@puppet_status_template      = './templates/puppet_status.sh.erb'
    @@r10k_yaml_template          = './templates/r10k.yaml.erb'
    @@run_r10k_template           = './templates/run_r10k.sh.erb'
    @@csr_attributes_template     = './templates/csr_attributes.yaml.erb'
    @@setup_code_manager_template = './templates/setup_code_manager.sh.erb'
    @@offline_gem_template        = './templates/offline_gem.sh.erb'
    @@sign_cm_cert_template       = './templates/sign_cm_cert.sh.erb'

    @@classify_cm_script          = './scripts/classify_cm.rb'

    @@puppet_path         = '/opt/puppetlabs/puppet/bin'
    @@puppet_etc          = '/etc/puppetlabs/'
    @@puppet_confdir      = "#{@@puppet_etc}/puppet"
    @@puppet_r10k_yaml    = "#{@@puppet_etc}/r10k/r10k.yaml"
    @@puppet_r10k_ssh     = "#{@@puppet_etc}/puppetserver/ssh"
    @@puppet_r10k_key     = "#{@@puppet_r10k_ssh}/id-control_repo.rsa"
    @@inifile = 'inventory/hosts'

    @@agent_local_path    = './agent_installers'
    @@agent_upload_path   = '/opt/puppetlabs/server/data/staging/pe_repo-puppet-agent-1.7.1/'
    @@gem_local_path      = './gems'

    def initialize(options, arguments)
      @options = options
      @arguments = arguments
      @ssh_username = @options[:global][:options][:ssh_username]
      @swap_user = @options[:global][:options][:swap_user]
      if ENV.has_key? 'PUPPETIZER_USER_PASSWORD'
        @user_password = ENV['PUPPETIZER_USER_PASSWORD']
      else
        @user_password = false
      end
      if ENV.has_key? 'PUPPETIZER_ROOT_PASSWORD'
        @root_password = ENV['PUPPETIZER_ROOT_PASSWORD']
      else
        @root_password = false
      end

      auth_methods = [
        "none",
        "publickey"
      ]
      if @user_password
        auth_methods.push("password")
      end

      @ssh_opts = {
        :user               => @ssh_username,
        :auth_methods       => auth_methods,
        :operation_timeout  => 0,
        :timeout            => 60*60, # nothing we do should take more then an hour, period
      }

      if @user_password
        @ssh_opts[:password] = @user_password
      end

      # if non-root, use sudo
      if @ssh_username == "root"
        @user_start = ''
        @user_end = ''
      else
        if @swap_user == 'sudo'
          @user_start = 'sudo'
          @user_end = ''
        elsif @swap_user == 'su'
          @user_start = 'su -c \''
          @user_end = '\''
        else
          raise Escort::UserError.new("Unsupported swap user method: #{@swap_user}")
        end

        if ENV.has_key? 'PUPPETIZER_USER_PASSWORD'
          @user_password = ENV['PUPPETIZER_USER_PASSWORD']
        else
          @user_password = false
        end
      end

      if File.exists?(@@inifile)
        @myini = IniStyle.new('inventory/hosts')
      else
        raise Escort::UserError.new("Inventory file not found at #{@@inifile}")
      end

      @action_log = "./puppetizer_#{Time.now.iso8601}.log"
    end

    def action_log(message)
      File.open(@action_log, 'a') do |file|
        file.write message + "\n"
      end
    end

    def setup_csr_attributes(host, csr_attributes, data)
      challenge_password = @options[:global][:commands][command_name][:options][:challenge_password]
      user_start = @user_start
      user_end   = @user_end

      if csr_attributes or challenge_password
        Escort::Logger.output.puts "Setting up CSR attributes on #{host}"
        f = Tempfile.new("puppetizer")
        begin
          f << ERB.new(read_template(@@csr_attributes_template), nil, '-').result(binding)
          f.close
          csr_tmp = "/tmp/csr_attributes.yaml"
          scp(host, f.path, csr_tmp)
          ssh(host,
            "#{user_start} mkdir -p #{@@puppet_confdir} #{user_end} && "\
            "#{user_start} mv #{csr_tmp} #{@@puppet_confdir}/csr_attributes.yaml #{user_end}")
        ensure
          f.close
          f.unlink
        end
      end
    end

    def install_puppet(host, csr_attributes = false, data={})
      message = "Installing puppet agent on #{host}"
      Escort::Logger.output.puts message
      action_log('# ' + message)

      puppetmaster = @options[:global][:commands][command_name][:options][:puppetmaster]
      user_start = @user_start
      user_end = @user_end
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

    def upload_needed(host, local_file, remote_file)
      local_md5=%x{md5sum #{local_file}}.strip.split(/\s+/)[0]
      remote_md5=ssh(host, "md5sum #{remote_file} 2>&1", true).stdout.strip.split(/\s+/)[0]

      needed = local_md5 != remote_md5
      if ! needed
        Escort::Logger.output.puts "#{local_md5} #{File.basename(local_file)}"
      end
      return needed
    end

    # Return the absolute filename of a named resource in this gem
    def resource_path(resource)
      File.join(
        File.dirname(File.expand_path(__FILE__)), "../res/#{resource}")
    end

    def read_template(template)
      # Override shipped templates with local ones if present
      if File.exist?(template)
        Escort::Logger.output.puts "Using local template #{template}"
        template_file = template
      else
        template_file = File.join(
          File.dirname(File.expand_path(__FILE__)), "../res/#{template}")
      end
      File.open(template_file, 'r') { |file| file.read }
    end

    def upload_agent_installers(host)
      user_start = @user_start
      user_end = @user_end
      if Dir.exists?(@@agent_local_path)
        # make sure the final location exists on puppet master
        ssh(host, "#{user_start} mkdir -p #{@@agent_upload_path} #{user_end}")
        Dir.foreach(@@agent_local_path) { |f|
          if f != '.' and f != '..'
            filename = @@agent_local_path + File::SEPARATOR + f
            scp(host, filename, "/tmp/#{f}", "Uploading #{f}")
            ssh(host, "#{user_start} cp /tmp/#{f} #{@@agent_upload_path} #{user_end}")
          end
        }
      end
    end

    def upload_offline_gems(host)
      user_start = @user_start
      user_end = @user_end
      gem_cache_dir = '/tmp/gems/'
      install_needed = false
      local_cache = @@gem_local_path + File::SEPARATOR + 'cache'
      if Dir.exists?(local_cache)
        ssh(host, "mkdir -p #{gem_cache_dir}")
        Dir.foreach(local_cache) { |f|
          if f != '.' and f != '..'
            filename = local_cache + File::SEPARATOR + f
            scp(host, filename, gem_cache_dir + f, "Uploading " + f)
            install_needed = true
          end
        }

        if install_needed
          ssh(host, ERB.new(read_template(@@offline_gem_template), nil, '-').result(binding))
        end
      end
    end

    def install_pe(host, csr_attributes, data)
      message = "Installing Puppet Enterprise on #{host}"
      Escort::Logger.output.puts message
      action_log('# ' + message)

      # variables in scope for ERB
      password = @options[:global][:commands][command_name][:options][:console_admin_password]

      # compile master installation?
      if data.has_key?('compile_master') and data['compile_master'] == "true"
        compile_master = true
        if data.has_key?('mom') and ! data['mom'].empty?
          mom = data['mom']
        else
          raise PuppetizerError, "You must specify a mom when installing compile masters.  Please set mom=PUPPETMASTER_FQDN"
        end

        if data.has_key?('lb') and ! data['lb'].empty?
          lb = data['lb']
        else
          lb = ''
        end
      else
        compile_master = false

        if data.has_key?('r10k_private_key') and ! data['r10k_private_key'].empty?
          r10k_private_key_path = Dir.pwd + File::SEPARATOR + data['r10k_private_key']
          if ! File.exists?(r10k_private_key_path)
            raise PuppetizerError, "r10k_private_key not found at #{r10k_private_key_path}"
          end
        else
          r10k_private_key_path = false
        end
      end

      # deploy code with code manager?
      if data.has_key?('deploy_code') and data['deploy_code'] == "true"
        deploy_code = true
      else
        deploy_code = false
      end

      # use control repo supplied in inventory else command line default
      if data.has_key?('control_repo') and ! data['control_repo'].empty?
        control_repo = data['control_repo']
      else
        control_repo = @options[:global][:commands][command_context[0]][:options][:control_repo]
      end

      # dns_alt_names from inventory
      if data.has_key?('dns_alt_names') and ! data['dns_alt_names'].empty?
        # each pair needs to be wrapped in double quotes
        dns_alt_names = data['dns_alt_names'].split(',').map { |s| '"' + s + '"'}.join(',')
      else
        dns_alt_names = false
      end
      user_start = @user_start
      user_end = @user_end

      setup_csr_attributes(host, csr_attributes, data)

      # SCP up the agents if present
      upload_agent_installers(host)

      # run the PE installer
      if compile_master
        # install puppet agent as a CM
        ssh(host, ERB.new(read_template(@@install_cm_template), nil, '-').result(binding))

        # sign the cert on the mom
        Escort::Logger.output.puts "Waiting 5 seconds for CSR to arrive on MOM"
        sleep(5)
        action_log("# --- begin run command on #{mom} ---")
        ssh(mom, ERB.new(read_template(@@sign_cm_cert_template), nil, '-').result(binding))
        action_log("# --- end run command on #{mom} ---")


        # copy the classification script to the MOM and run it
        Escort::Logger.output.puts "Classifying #{host} as Compile Master"
        script_path = "/tmp/#{File.basename(@@classify_cm_script)}"

        action_log("# --- begin copy file to #{mom} ---")
        scp(mom, resource_path(@@classify_cm_script), script_path)
        action_log("# --- end copy file to #{mom} ---")

        # pin the CM to the PE Masters group and set a load balancer address for
        # pe_repo (if provided)
        action_log("# --- begin run command on #{mom} ---")
        ssh(mom, "chmod +x #{script_path}")
        ssh(mom, "#{user_start} #{script_path} #{host} #{lb} #{user_end}")
        action_log("# --- end run command on #{mom} ---")

        # Run puppet in the correct order
        Escort::Logger.output.puts "Running puppet on compile master: #{host}"
        ssh(host, "#{user_start} /opt/puppetlabs/bin/puppet agent -t #{user_end}")

        Escort::Logger.output.puts "Running puppet on MOM: #{mom}"
        action_log("# --- begin run command on #{mom} ---")
        ssh(mom, "#{user_start} /opt/puppetlabs/bin/puppet agent -t #{user_end}")
        action_log("# --- end run command on #{mom} ---")
      else
        # full PE installation

        puppet_r10k_key = @@puppet_r10k_key

        # SCP the installer
        tarball = find_pe_tarball
        scp(host, tarball, "/tmp/#{tarball}", "Upload PE Media")

        # copy r10k private key if needed
        if r10k_private_key_path

          # upload to /tmp
          temp_keyfile = "/tmp/#{File.basename(@@puppet_r10k_key)}"
          scp(host, r10k_private_key_path, temp_keyfile)

          # make directory and move temp keyfile there
          ssh(host, "#{user_start} mkdir -p #{@@puppet_r10k_ssh} #{user_end}")
          ssh(host, "#{user_start} mv #{temp_keyfile} #{@@puppet_r10k_key} #{user_end}")
        end

        # run installation
        ssh(host, ERB.new(read_template(@@install_pe_master_template), nil, '-').result(binding))

        # fix permissions on key
        if r10k_private_key_path
          ssh(host, "#{user_start} chown pe-puppet.pe-puppet #{@@puppet_r10k_key} #{user_end}")
          ssh(host, "#{user_start} chmod 600 #{@@puppet_r10k_key} #{user_end}")
        end
      end

      # Upload the offline gems if present - must be done AFTER puppet install
      # to obtain gem command
      upload_offline_gems(host)

      # post-install (gems) after we have uploaded any offline gems
      ssh(host, ERB.new(read_template(@@pe_postinstall_template), nil, '-').result(binding))

      # run puppet to finalise configuration
      ssh(host, "#{user_start} #{@@puppet_path}/puppet agent -t #{user_end} ")

      if deploy_code and ! compile_master
        setup_code_manager(host)
      end

      Escort::Logger.output.puts "Puppet Enterprise installation for #{host} completed"
    end

    def defrag_line(d, channel, no_print)
      # The sudo prompt doesn't have a newline at the end so the main stream
      # reading code never catches it, lets capture it here...
      # based on: http://stackoverflow.com/a/4235463
      if d =~ /^\[sudo\] password for #{@ssh_username}:/ or d =~ /Password:/
        if @swap_user == 'sudo'
          if @user_password
            # send password
            channel.send_data @user_password

            # don't forget to press enter :)
            channel.send_data "\n"
          else
            raise PuppetizerError, "We need a sudo password.  Please export PUPPETIZER_USER_PASSWORD=xxx"
          end
        elsif @swap_user == 'su'
          if @root_password
            # send password
            channel.send_data @root_password
            channel.send_data "\n"
          else
            raise PuppetizerError, "We need an su password.  Please export PUPPETIZER_ROOT_PASSWORD=xxx"
          end
        end
      end

      # read the input line-wise (it *will* arrive fragmented!)
      (@buf ||= '') << d
      while line = @buf.slice!(/(.*)\r?\n/)
        if ! no_print
          Escort::Logger.output.puts line.strip #=> "hello stderr"
        end
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

    def scp(host, local_file, remote_file, job_name='Upload data')
      if port_open?(host,22)
        if upload_needed(host, local_file, remote_file)
          action_log("scp #{local_file} to #{host}:#{remote_file}")
          busy_spinner = BusySpinner.new
          begin
            # local variables are visible in instance-eval but instance ones are not...
            # see http://stackoverflow.com/questions/3071532/how-does-instance-eval-work-and-why-does-dhh-hate-it
            ssh_opts = @ssh_opts
            progressbar = ProgressBar.create(:title => job_name)
            Net::SSH::Simple.sync do
              scp_put(host, local_file, remote_file, ssh_opts) do |sent, total|
                #Escort::Logger.output.puts "Bytes uploaded: #{sent} of #{total}"

                # for some reason, sent bytes is too high when we are sending to
                # AWS over a slow link.  I don't know if its because they bytes
                # are in-flight or if its just because of bug in net-scp but
                # pulsing the progress bar to let user know that status is now
                # unknown/finishing
                if sent==total
                  t = Thread.new { busy_spinner.run }
                  t.abort_on_exception = true
                else
                  percent_complete = (sent/total.to_f) * 100
                  progressbar.progress=(percent_complete)
                end
              end
            end
            # control returns here
            if busy_spinner
              busy_spinner.stop
            end

          rescue Net::SSH::Simple::Error => e
            if e.message =~ /AuthenticationFailed/
              error_message = "Authentication failed for #{ssh_opts[:user]}@#{host}, key loaded?"
            else
              error_message = 'no'#e.message
            end
            raise PuppetizerError, error_message
          end
        end
      else
        raise PuppetizerError, "host #{host} not responding to SSH"
      end
    end

    def ssh(host, cmd, no_print=false, no_capture=false)
      action_log(cmd)
      user_start = @user_start
      request_pty = ! @user_start.empty?
      if port_open?(host,22)
        begin
          ssh_opts = @ssh_opts
          r = Net::SSH::Simple.sync do
            ssh(host, cmd, ssh_opts, request_pty) do |e,c,d|
              case e
                when :start
                  #puts "CONNECTED"
                when :stdout, :stderr
                  defrag_line(d,c,no_print)
                  if no_capture
                    :no_append
                  end
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
          raise PuppetizerError, error_message
        end
      else
        raise PuppetizerError, "host #{host} not responding to SSH"
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
            begin
              install_pe(hostname, csr_attributes, data)
            rescue PuppetizerError => e
              Escort::Logger.error.error e.message
            end
          end
        when "agents"
          @myini[section_key].each do |r|
            hostname, csr_attributes, data = InventoryParser::parse(r)
            begin
              install_puppet(hostname, csr_attributes, data)
            rescue PuppetizerError => e
              Escort::Logger.error.error e.message
            end
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
      user_start = @user_start
      user_end = @user_end

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

    def action_upload_agent_installers()
      section_key = "puppetmasters"
      if @myini.sections.include?(section_key)
        @myini[section_key].each do |r|
          hostname, csr_attributes, data = InventoryParser::parse(r)
          upload_agent_installers(hostname)
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

  # Make our own exception so that we know we threw it and can proceed
  class PuppetizerError  < StandardError
  end

  class BusySpinner

    def stop
      @running = false
    end

    def run
      @running = true
      progressbar = ProgressBar.create(:total=> nil, :title=>'finishing')

      while @running
        progressbar.increment
        sleep(0.2)
      end
    end

  end

end
