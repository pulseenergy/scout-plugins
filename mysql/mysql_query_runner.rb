class MySQLQueryRunner < Scout::Plugin
  needs 'mysql'

  OPTIONS=<<-EOS
    config_file:
      name: Config File
      notes: Configuration file on each server from which to load all other configuration values. Providing a config file value overrides any other configuration settings and can be used as an alternative to configuring the plugin in the Scout interface.
    mysql_host:
      default: localhost
      name: MySQL Host
      notes: The hostname of the MySQL instance
    mysql_port:
      default: 3306
      name: MySQL Port
      notes: The port of the MySQL instance
    mysql_user:
      default: root
      name: MySQL User
      notes: The password of the MySQL instance
    mysql_password:
      name: MySQL Password
      notes: The password of the MySQL instance
    mysql_database:
      name: MySQL Database
      notes: The database id to pass to the MySQL instance
    label:
      name: Query Label
      notes: Label for SQL query
    query:
      name: SQL Query
      notes: SQL statement to be executed

  EOS

  def configure_from_file(config_file)
    config = YAML::load(File.open(config_file, "r"))

    db_config = config["mysql"]
    @db = Mysql.real_connect(db_config["host"], db_config["user"], db_config["password"], db_config["database"], db_config["port"])
    @queries = config["queries"]
  end

  def configure_from_options()
    @db = Mysql.real_connect(option(:mysql_host), option(:mysql_user), option(:mysql_password), option(:mysql_database), option(:mysql_port))
    @queries = {option(:label) => option(:query)}
  end


  def do_report(key, value)
    report(key => value)
    @report_count +=1
  end

  def execute_query(key_prefix, sql)
    begin
      result = @db.query(sql)

      num_rows = result.num_rows
      num_cols = result.num_fields

      if num_rows > 1 and num_cols == 1
        error("Multirow query '#{key_prefix}' must contain a label field as the first column")
        return
      end

      if num_rows == num_cols and num_cols == 1
        do_report(key_prefix, result.fetch_row()[0].to_i)
        return
      end

      result.each do |row|
        row_label = key_prefix + ":" + row[0]
        if num_cols == 2
          do_report(row_label, row[1].to_i)
        else
          result.fetch_fields.each_with_index do |field, i|
            if i > 0
              key = row_label + ":" + field.name
              do_report(key,row[i].to_i)
            end
          end
        end
      end
    ensure
      result.free if result
    end
  end

  def build_report
    @report_count = 0
    config_file = option(:config_file).to_s

    begin
      if config_file.empty?
        configure_from_options
      else
        configure_from_file(config_file)
      end

      @queries.each_pair do |key, value|
        execute_query(key, value)
        if @report_count > 20
          error("More than 20 fields reported")
          return
        end
      end
    rescue Mysql::Error => e
      error("DB error #{e.errno}: #{e.error}")
    ensure
      @db.close if @db
    end
  end
end