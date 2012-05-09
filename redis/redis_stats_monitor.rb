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
    size_keys:
      default: ""
      name: Monitor Key Size
      notes: A comma-separated list of keys to monitor the length of (works for lists, sets, zsets, hashes, and strings).
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
    @size_keys = option(:size_keys).to_s
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
    @size_keys = config["size_keys"].to_s
    @granularity = config["rate_granularity"].to_s
  end

  def check_field_count(field_count)
    if field_count > 20
      error("More than 20 fields reported")
      return false
    end
    return true
  end

  def build_report
    config_file = option(:config_file).to_s

    if config_file.empty?
      configure_from_options()
    else
      configure_from_file(config_file)
    end

    field_count = 0
    
    value_keys = []
    if not @value_key_prefix.empty? then
      value_keys = @redis.keys(@value_key_prefix + "*")
    end

    value_keys.each do |key|
      value = @redis.get(key).to_i
      name = key
      name[@value_key_prefix] = ""
      report(name => value)
      field_count += 1
      if not check_field_count(field_count)
        return
      end
    end

    rate_keys = []
    if not @rate_key_prefix.empty? then
        rate_keys = @redis.keys(@rate_key_prefix + "*")
    end
    rate_keys.each do |key|
      value = @redis.get(key).to_i
      name = key
      name[@rate_key_prefix] = ""
      counter(name, value, :per => @granularity)
      field_count += 1
      if not check_field_count(field_count)
        return
      end
    end

    if not @size_keys.empty? then
      @size_keys.split(',').each do |redis_key|
        name = redis_key
        type = @redis.type(redis_key)
        if type == "none" then
          next
        end
        functions = Hash["list", :llen, "set", :scard, "zset", :zcard, "hash", :hlen, "string", :strlen]
        value = @redis.send(functions[type], redis_key).to_i
        report(name => value)
        field_count += 1
        if not check_field_count(field_count)
          return
        end
      end
    end
  end
end