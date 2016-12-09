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

module Puppetizer::Util
  # Return the absolute filename of a named resource in this gem
  def self.resource_path(resource)
    File.join(
      File.dirname(File.expand_path(__FILE__)), "../../res/#{resource}")
  end

  def self.resource_read(res)
    # Override shipped templates with local ones if present
    if File.exist?(res)
      Escort::Logger.output.puts "Using local template #{res}"
      res_file = res
    else
      res_file = File.join(
        File.dirname(File.expand_path(__FILE__)), "../../res/#{res}")
    end
    File.open(res_file, 'r') { |file| file.read }
  end

end
