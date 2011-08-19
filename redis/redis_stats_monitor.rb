class RedisStatsMonitor < Scout::Plugin
  needs 'redis', 'yaml'

  OPTIONS=<<-EOS
    config_file:
      name: Config File
      notes: Configuration file on each server from which to load all other configuration values. Providing a config file value overrides any other configuration settings and can be used as an alternative to configuring the plugin in the Scout interface.
    redis_host:
      default: localhost
      name: Redis Host
      notes: The hostname of the Redis instance
    redis_port:
      default: 6379
      name: Redis Port
      notes: The port of the Redis instance
    redis_password:
      name: Redis Password
      notes: The password of the Redis instance
    redis_database:
      default: 0
      name: Redis Database
      notes: The database id to pass to the Redis instance
    value_key_prefix:
      name: Value Key Prefix
      notes: Key prefix for Redis keys to be returned as simple values
    rate_key_prefix:
      name: Rate Key Prefix
      notes: Key prefix for Redis keys to be returned as rates
    rate_granularity:
      default: minute
      name: Rate Granularity
      notes: Granularity at which rates are calculated ('second', 'minute')
  EOS


  def configure_from_options
    @redis = Redis.new :port => option(:redis_port),
                       :db => option(:redis_database),
                       :password => option(:redis_password),
                       :host => option(:redis_host)

    @value_key_prefix = option(:value_key_prefix).to_s
    @rate_key_prefix = option(:rate_key_prefix).to_s
    @granularity = option(:rate_granularity).to_s == 'second' ? :sec : :minute
  end

  def configure_from_file(config_file)
    config = YAML::load(File.open(config_file, "r"))

    redis_config = config["redis"]
    @redis = Redis.new :port => redis_config["port"],
                       :db => redis_config["database"],
                       :password => redis_config["password"],
                       :host => redis_config["host"]

    prefixes = config["key_prefixes"]
    @value_key_prefix = prefixes["value"].to_s
    @rate_key_prefix = prefixes["rate"].to_s
    @granularity = config["rate_granularity"].to_s
  end

  def build_report
    config_file = option(:config_file).to_s

    if config_file.empty?
      configure_from_options()
    else
      configure_from_file(config_file)
    end

    value_keys = @redis.keys(@value_key_prefix + "*")

    value_keys.each do |key|
      value = @redis.get(key).to_i
      name = key
      name[@value_key_prefix] = ""
      report(name => value)
    end

    rate_keys = @redis.keys(@rate_key_prefix + "*")
    rate_keys.each do |key|
      value = @redis.get(key).to_i
      name = key
      name[@rate_key_prefix] = ""
      counter(name, value, :per => @granularity)
    end
  end
end