module Puppetizer
  class SshParams

    def initialize(hostname, authenticator)
      @hostname       = hostname
      @authenticator  = authenticator

      auth_methods = [
        "none",
        "publickey"
      ]

      ssh_opts = {
        :user               => @authenticator.username(hostname),
        :auth_methods       => auth_methods,
        :operation_timeout  => 0,
        :timeout            => 60*60, # nothing we do should take more then an hour, period
      }

      if @authenticator.user_password(hostname)
        auth_methods.push("password")
        ssh_opts[:password] = @authenticator.user_password(hostname)
      end

      @ssh_opts = ssh_opts
    end

    def get_hostname
      @hostname
    end

    def get_username
      @authenticator.username(@hostname)
    end


    def get_user_password
      @authenticator.user_password(@hostname)
    end

    def get_root_password
      @authenticator.root_password(@hostname)
    end

    def get_pty_required
      @authenticator.pty_required(@hostname)
    end

    def get_swap_user
      @authenticator.swap_user(@hostname)
    end

    def get_ssh_opts
      @ssh_opts
    end
  end
end
