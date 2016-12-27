# Make log and consume business info easily in your rails application!

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'flog_ruby'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install flog_ruby

## Usage

### Get and use flogger

`flogger = Flog.get(:api)`  

Here `api` is a business log group.

log your business info as your normal logger, but in better hash format.

```ruby
flogger.info :project_visit, user_id: 123, project_id: 234, extra: {data: 'other context info.'}
```

### Environment and Rsyslog support

In development environment, flog write log into `log/flog/*.log` by default.

In other environment, you can configure it use rsyslog mechanism to send info to remote logger service!

```bash
SYSLOG_ORIGIN:    log entry point origin source
SYSLOG_FACILITY:  rsyslog facility, default: local0 
FLOG_LEVEL:       logger level, default: debug 
FLOG_NOT_SYSLOG:  force not use rsyslog, use multi-log files
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/flog_ruby. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

