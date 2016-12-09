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
require 'net/ssh/simple'
require 'puppetizer/log'
require 'puppetizer/puppetizer_error'
require 'puppetizer/busy_spinner'

module Puppetizer::Transport
  Log = ::Puppetizer::Log

  # Overall module per-run settings
  def self.init(ssh_opts, user_start)

    # hash of options for ssh
    @ssh_opts = ssh_opts

    # used to detect if we need to allocated a PTY or not (for non-root)
    @user_start = user_start
  end


  def self.upload_needed(host, local_file, remote_file)
    local_md5=%x{md5sum #{local_file}}.strip.split(/\s+/)[0]
    remote_md5=ssh(host, "md5sum #{remote_file} 2>&1", true).stdout.strip.split(/\s+/)[0]

    needed = local_md5 != remote_md5
    if ! needed
      Escort::Logger.output.puts "#{local_md5} #{File.basename(local_file)}"
    end
    return needed
  end

  def self.port_open?(ip, port)
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

  def self.scp(host, local_file, remote_file, job_name='Upload data')
    if port_open?(host,22)
      if upload_needed(host, local_file, remote_file)
        Log::action_log("scp #{local_file} to #{host}:#{remote_file}")
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

  def self.ssh(host, cmd, no_print=false, no_capture=false)
    Log::action_log(cmd)
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

  def self.defrag_line(d, channel, no_print)
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

end
