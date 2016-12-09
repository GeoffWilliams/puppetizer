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
require 'puppetizer/util'
require 'puppetizer/transport'
require 'puppetizer'
module Puppetizer::AltInstaller
  Transport = ::Puppetizer::Transport
  Util = ::Puppetizer::Util

  @@agent_cache = "./agent_repos_cache"
  @@puppet_conf = "/etc/puppetlabs/puppet/puppet.conf"

  @@platform_tag_script         = './scripts/platform_tag.sh'
  @@puppet_conf_template        = './templates/puppet.conf.erb'

  # login to host via SSH and run a script to work out the platform tag
  def self.platform_tag(hostname)
    Transport::ssh(hostname, Puppetizer::Util::resource_read(@@platform_tag_script)).stdout.strip.downcase
  end

  def self.extract_agent(platform_tag)
    if ! Dir.exists?(@@agent_cache)
      Dir.mkdir(@@agent_cache)
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
    package_glob = 'puppet-agent-*'
    pattern = "*/#{package_glob}"
    install_dir = Dir.pwd
    target = nil
    Dir.chdir(@@agent_cache) do
      repo_dirs = platform_tag.split('-')
      extract_dir = "repos/#{repo_dirs[0]}/#{repo_dirs[1]}/PC1/#{repo_dirs[2]}"
      extract_glob = "#{extract_dir}/#{package_glob}"
      # skip extraction if repo dir exists
      if ! Dir.glob(extract_glob)
        tarball = "#{install_dir}/agent_installers/puppet-agent-#{platform_tag}.tar.gz"
        if File.exists?(tarball)
          %x(tar -zxvf #{taball} #{pattern})
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

  def self.ensure_puppet_conf(hostname, puppetmaster, certname, user_start, user_end)
    Escort::Logger.output.puts "Setting up puppet.conf file on #{hostname}"
    f = Tempfile.new("puppetizer")
    begin
      f << ERB.new(Util::resource_read(@@puppet_conf_template), nil, '-').result(binding)
      f.close
      puppet_conf_tmp = "/tmp/puppet.conf"
      Transport::scp(hostname, f.path, puppet_conf_tmp)
      Transport::ssh(hostname,
        "#{user_start} mkdir -p #{Puppetizer::Puppetizer.puppet_confdir} #{user_end} && "\
        "#{user_start} mv #{puppet_conf_tmp} #{Puppetizer::Puppetizer.puppet_confdir}/puppet.conf #{user_end}")
    ensure
      f.close
      f.unlink
    end


  end

  # manually install puppet over SCP without using curl, bash or wget for
  # systems that dont have these tools - eg aix and solaris
  def self.install_puppet(hostname, puppetmaster, data, user_start, user_end)

    # FIXME extract certname from data
    certname = hostname

    # login to remote host, run scipt to determine flavour
    platform_tag = platform_tag(hostname)

    # copy correct installer
    package_file = extract_agent(platform_tag)
    Transport::scp(hostname, package_file, "/tmp/#{File.basename(package_file)}")

    # puppet.conf
    ensure_puppet_conf(hostname, puppetmaster, certname, user_start, user_end)

    # install packages
  end
end
