#!/usr/bin/env ruby
#
# Copyright 2016 Geoff Williams for Puppet Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
require 'puppetizer'
require 'puppetizer/util'
require 'puppetizer/transport'
require 'puppetizer/alt_installer'
require 'escort'
require 'erb'

module Puppetizer
  module AltInstaller
    Transport = Puppetizer::Transport
    Util = Puppetizer::Util

    AGENT_CACHE                 = "./agent_repos_cache"
    PLATFORM_TAG_SCRIPT         = './scripts/platform_tag.sh'
    ENABLE_PUPPET_TEMPLATE      = './templates/alt_install_enable_puppet.sh.erb'
    PUPPET_CONF_TEMPLATE        = './templates/puppet.conf.erb'
    SOLARIS_NOASK_FILE          = './files/solaris-noask'
    SOLARIS_NOASK_TARGET        = '/tmp/solaris-noask'
    MV_PUPPET_CONF_TEMPLATE     = './templates/mv_puppet_conf.sh.erb'


    # login to host via SSH and run a script to work out the platform tag
    def self.platform_tag(ssh_params)
      Transport::ssh(ssh_params,
        Puppetizer::Util::resource_read(PLATFORM_TAG_SCRIPT)
      ).stdout.strip.downcase
    end

    def self.extract_agent(platform_tag)
      if ! Dir.exists?(AGENT_CACHE)
        Dir.mkdir(AGENT_CACHE)
      end
      # Target listings for all supported platforms (aix,solaris,rhel) eg:
      #   repos/solaris/10/PC1/puppet-agent-1.7.1-1.i386.pkg.gz
      #   repos/solaris/11/PC1/puppet-agent@1.7.1,5.11-1.i386.p5p
      #   repos/aix/5.3/PC1/ppc/puppet-agent-1.7.1-1.aix5.3.ppc.rpm
      #   repos/aix/6.1/PC1/ppc/puppet-agent-1.7.1-1.aix6.1.ppc.rpm
      #   repos/aix/7.1/PC1/ppc/puppet-agent-1.7.1-1.aix7.1.ppc.rpm
      #   repos/el/6/PC1/i386/puppet-agent-1.7.1-1.el6.i386.rpm
      #   repos/el/7/PC1/x86_64/puppet-agent-1.7.1-1.el7.x86_64.rpm
      # Was going to do a platform-based lookup here but really all thats needed
      # is to extract the file matching /puppet-agent-*
      package_glob = 'puppet-agent*'
      pattern = "*/#{package_glob}"
      install_dir = Dir.pwd
      target = nil
      Dir.chdir(AGENT_CACHE) do
        repo_dirs = platform_tag.split('-')
        if repo_dirs[0] == 'solaris'
          # the solaris platform uses a different directory structure :/
          extract_dir = "repos/#{repo_dirs[0]}/#{repo_dirs[1]}/PC1"
        else
          extract_dir = "repos/#{repo_dirs[0]}/#{repo_dirs[1]}/PC1/#{repo_dirs[2]}"
        end
        extract_glob = "#{extract_dir}/#{package_glob}"
        # skip extraction if repo dir exists
        if Dir.glob(extract_glob).empty?
          tarball = "#{install_dir}/agent_installers/puppet-agent-#{platform_tag}.tar.gz"
          if File.exists?(tarball)
            %x(tar -zxvf #{tarball} #{pattern})
          else
            raise Escort::UserError.new(
              "Please download the Puppet Enterprise agent repository for "\
              "#{platform_tag} and put it in ./agent_installers")
          end
        end
        target = Dir.pwd + "/" + Dir.glob(extract_glob)[0]
      end
      target
    end

    def self.ensure_puppet_conf(ssh_params, puppetmaster, certname)
      user_start, user_end = ssh_params.get_swap_user()

      Escort::Logger.output.puts "Setting up puppet.conf file on #{ssh_params.get_hostname()}"
      f = Tempfile.new("puppetizer")
      begin
        f << ERB.new(Util::resource_read(PUPPET_CONF_TEMPLATE), nil, '-').result(binding)
        f.close
        puppet_conf_tmp = "/tmp/puppet.conf"
        Transport::scp(ssh_params, f.path, puppet_conf_tmp)
        Transport::ssh(ssh_params,
          ERB.new(Util::resource_read(MV_PUPPET_CONF_TEMPLATE), nil, '-').result(binding))
      ensure
        f.close
        f.unlink
      end
    end

    # manually install puppet over SCP without using curl, bash or wget for
    # systems that dont have these tools - eg aix and solaris
    def self.install_puppet(ssh_params, puppetmaster, data)
      user_start, user_end = ssh_params.get_swap_user()

      # FIXME extract certname from data
      certname = ssh_params.get_hostname()

      # login to remote host, run scipt to determine flavour
      platform_tag = platform_tag(ssh_params)

      # copy correct installer
      package_file = extract_agent(platform_tag)
      agent_installer_file = "/tmp/#{File.basename(package_file)}"
      Transport::scp(ssh_params, package_file, agent_installer_file)

      # puppet.conf
      ensure_puppet_conf(ssh_params, puppetmaster, certname)

      # install packages
      case platform_tag
      when /^solaris-10/
        # solaris 10 ONLY needs a 'noask' file to shut the pkgadd tool up.  This
        # has to be referenced in a different installation template too
        Transport::scp(ssh_params, SOLARIS_NOASK_FILE, SOLARIS_NOASK_TARGET)
        install_script_res =
          "./templates/alt_install_#{platform_tag.split('-')[0]}-10.sh.erb"
      when /^solaris-11/
        install_script_res =
          "./templates/alt_install_#{platform_tag.split('-')[0]}-11.sh.erb"
      when /^el/, /^aix/
        install_script_res = "./templates/alt_install_#{platform_tag.split('-')[0]}.sh.erb"
      else
        raise Escort::UserError.new(
          "No support for #{platform_tag} in the alt_installer yet (ticket?)")
      end

      install_script = ERB.new(Util::resource_read(install_script_res), nil, '-').result(binding)

      # packages
      Transport::ssh(ssh_params, install_script)

      # use puppet to enable the services
      Transport::ssh(ssh_params,
        ERB.new(Util::resource_read(ENABLE_PUPPET_TEMPLATE), nil, '-').result(binding)
      )
    end
  end
end
