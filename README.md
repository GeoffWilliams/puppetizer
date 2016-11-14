# Puppetizer

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/puppetizer`. To experiment with that code, run `bin/console` for an interactive prompt.

TODO: Delete this and the text above, and describe your gem

## Installation

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




## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/puppetizer.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
