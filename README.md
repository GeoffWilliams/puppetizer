# Puppetizer

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/puppetizer`. To experiment with that code, run `bin/console` for an interactive prompt.

TODO: Delete this and the text above, and describe your gem

## Development instructions

### Prerequisites

* ruby

  ```shell
  yum install -y ruby
  ```
_Note:  This will install the system ruby - you don't need to (nor should you...) install this software on a Puppet Enterprise Master_

* bundler

  ```shell
  gem install bundler
  ```


```shell
git clone https://github.com/GeoffWilliams/puppetizer
cd puppetizer
bundle install
bundle exec ./puppetizer ...
```

Where `...` represents the arguments to the puppetizer command

## Bundle installation

Add this line to your application's Gemfile:

```ruby
gem 'puppetizer'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install puppetizer



# sudo
Login to machines as user `fred` and become root using `sudo` and `fred`'s password: `freddy123`.

If passwordless sudo is in use, omit the export of `PUPPETIZER_USER_PASSWORD`.

```shell
export PUPPETIZER_USER_PASSWORD=freddy123 # password for the user (for SSH)
puppetizer --ssh_username fred
```

# su
Login to machines as user `fred` and become `root` using `su` with password `topsecr3t`

```shell
export PUPPETIZER_USER_PASSWORD=freddy123 # password for the user (for SSH)
export PUPPETIZER_ROOT_PASSWORD=topsecr3t # password for root (asked by su)
puppetizer --swap-user su --ssh-username fred
```

# Offline
Sometimes your puppetmaster will have no internet access or internet downloads for gems, agents etc are slowing you down.  In this case, puppetizer has support to upload the files needed from a local directory to keep you moving.

## Puppet Agents
Puppetizer will download the

## Gems
Puppetizer will upload and install all gems found in the `./gems` directory relative to where you are running the `puppetizer` command from.

To download the gems you need, try running https://github.com/GeoffWilliams/puppetizer/blob/master/get_gems.sh



## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/puppetizer.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
