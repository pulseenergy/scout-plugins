class HealthCheck < Scout::Plugin
  needs 'redis'

  OPTIONS=<<-EOS
    redis_host:
      default: localhost
      name: Redis Host
      notes: The hostname of the Redis instance
    redis_port:
      default: 6379
      name: Redis Port
      notes: The port of the Redis instance
    redis_password:
      default: localhost:6379
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

  def build_report
    redis = Redis.new :port     => option(:redis_port),
                      :db       => option(:redis_database),
                      :password => option(:redis_password),
                      :host     => option(:redis_host)

    value_key_prefix = option(:value_key_prefix).to_s
    rate_key_prefix = option(:rate_key_prefix).to_s

    value_keys = redis.keys(value_key_prefix + "*")

    value_keys.each do |key|
      value = redis.get(key).to_i
      name = key
      name[value_key_prefix] = ""
      report(name => value)
    end

    granularity = option(:rate_granularity) == 'second' ? :sec : :minute
    rate_keys = redis.keys(rate_key_prefix + "*")
    rate_keys.each do |key|
      value = redis.get(key).to_i
      name = key
      name[rate_key_prefix] = ""
      counter(name, value, :per => granularity)
    end
  end
end