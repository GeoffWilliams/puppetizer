# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'puppetizer/version'

Gem::Specification.new do |spec|
  spec.name          = "puppetizer"
  spec.version       = Puppetizer::VERSION
  spec.authors       = ["Geoff Williams"]
  spec.email         = ["geoff@geoffwilliams.me.uk"]

  spec.summary       = %q{Puppetize your world, the easy way}
  spec.description   = %q{Install Puppet on Masters and Agents}
  spec.homepage      = "https://github.com/GeoffWilliams/puppetizer"
  spec.license       = "Apache 2.0"


  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.12"
  spec.add_development_dependency "rake", "~> 10.0"

  spec.add_runtime_dependency "escort", "0.4.0"
  spec.add_runtime_dependency 'net-ssh-simple', '1.6.16'
  spec.add_runtime_dependency 'inistyle', '0.1.0'
  spec.add_runtime_dependency 'ruby-progressbar', '1.8.1'
end
