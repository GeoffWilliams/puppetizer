require 'puppetizer'
require 'puppetizer/install_state'
require 'fileutils'

module Puppetizer
  module InstallState
    STATE_DIR         = './install_state'

    def self.state_filename(certname)
      "#{STATE_DIR}/#{certname}"
    end

    def self.installed(certname)
      return File.exists?(state_filename(certname))
    end

    def self.mark_installed(certname)
      FileUtils.mkdir_p(STATE_DIR)
      FileUtils.touch(state_filename(certname))
    end

  end
end
