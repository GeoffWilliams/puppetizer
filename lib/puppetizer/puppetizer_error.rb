# Make our own exception so that we know we threw it and can proceed
module Puppetizer
  class PuppetizerError  < StandardError
  end
end
