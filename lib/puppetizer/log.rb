module Puppetizer::Log
  @action_log = "./puppetizer_#{Time.now.iso8601}.log"

  def self.action_log(message)
    File.open(@action_log, 'a') do |file|
      file.write message + "\n"
    end
  end
end
