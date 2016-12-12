require 'csv'
require 'puppetizer'
require 'puppetizer/puppetizer_error'
require 'puppetizer/authenticator'
module Puppetizer
  class Authenticator

    def initialize(password_file, global_username=false)
      @password_file = password_file
      if @password_file
        read_password_file(@password_file)
      else
        @passwords = false
        if global_username
          @global_username  = global_username
        else
          @global_username = 'root'
        end

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
      end
    end

    def read_password_file(password_file)
      if File.exists? password_file
        @passwords = {}
        # thanks! http://technicalpickles.com/posts/parsing-csv-with-ruby/
        body = File.open(password_file)
        csv = CSV.new(body, :headers => true, :header_converters => :symbol, :converters => :all)

        # read each line of CVS and magic it into a hash.  Use the hostname
        # field as its key in @passwords and remove this key from the data
        csv.to_a.map { |row|
          d = row.to_hash
          hostname = d.delete(:hostname)
          @passwords[hostname] = d
        }
      else
        raise PuppetizerError, "File not found: #{password_file}"
      end
    end

    # lookup how (if at all) we should swap users for this host and return
    # 2 strings - one to use before running a command and one to run
    #             after, eg: "su root -c'" and "'"
    # a label describing the swap method
    def swap_user(hostname)
      # if non-root, use sudo
      if @passwords
        ssh_username      = read_password_value(hostname, :username)
        root_password_set = !! read_password_value(hostname, :password_root, false)
      else
        ssh_username      = @global_username
        root_password_set = !! @root_password
      end

      if ssh_username == "root"
        user_start  = ''
        user_end    = ''
        type        = :none
      elsif root_password_set
        # solaris/aix require the -u argument, also compatible with linux
        user_start  = 'su root -c \''
        user_end    = '\''
        type        = :su
      else
        user_start  = 'sudo'
        user_end    = ''
        type        = :sudo
      end

      return user_start, user_end, type
    end

    def read_password_value(hostname, key, fatal=true)
      if @passwords.has_key?(hostname)
        if @passwords[hostname].has_key?(key)
          @passwords[hostname][key]
        else
          if fatal
            raise PuppetizerError, "#{hostname} missing #{key} in #{@password_file}"
          end
        end
      else
        raise PuppetizerError, "#{hostname} missing from #{@password_file}"
      end
    end

    def username(hostname)
      if @passwords
        read_password_value(hostname, :username)
      else
        @global_username
      end
    end

    def user_password(hostname)
      if @passwords
        read_password_value(hostname, :password_user)
      else
        @user_password
      end
    end

    def root_password(hostname)
      if @passwords
        read_password_value(hostname, :password_root)
      else
        @root_password
      end
    end

    def pty_required(hostname)
      return username(hostname) != 'root'
    end
  end
end
