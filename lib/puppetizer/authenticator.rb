module Puppetizer
  class Authenticator

    def initialize(password_file, global_username)
      if password_file
        read_password_file(password_file, global_username=false)
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
      @passwords = false
    end

    def username(hostname)
      if @passwords
        @passwords[hostname][:username]
      else
        @global_username
      end
    end

    def user_password(hostname)
      if @passwords
        @passwords[hostname][:user]
      else
        @user_password
      end
    end

    def root_password(hostname)
      if @passwords
        @passwords[hostname][:root]
      else
        @root_password
      end
    end

  end
end
