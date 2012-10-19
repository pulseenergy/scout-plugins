#
# Copyright 2012 Pulse Energy Inc.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#    http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#
# A Scout Plugin for reading JMX values.
#
# Requires: Java SDK and jmxterm [http://wiki.cyclopsgroup.org/jmxterm]
#
class JmxAgent < Scout::Plugin
  needs "pty", "expect"

  OPTIONS=<<-EOS
    config_file:
      name: Config File
      notes: Configuration file on each server from which to load all other configuration values. Providing a config file value overrides any other configuration settings and can be used as an alternative to configuring the plugin in the Scout interface.

    jmxterm_uberjar:
      name: jmxterm uberjar File
      notes: Absolute file name of the jmxterm uberjar.
    
    jvm_pid_file:
      name: JVM PID File
      notes: File from which the PID of the JVM process can be read.
             Optional. If absent, mbean_server_url must be configured.
      
    mbean_server_url:
      name: MBean Server URL
      notes: The URL can be <host>:<port> or full service URL.
             Optional. If absent, jvm_pid_file must be configured.
             
    mbeans_attributes:
      name: MBean and Attributes Names
      notes: A pipe-delimited list of comma separated attribute names @ MBean name.
      For example: HeapMemoryUsage,NonHeapMemoryUsage@java.lang:type=Memory|Name@java.lang:type=Runtime
  EOS

  JMXTERM_PROMPT = "\$>"

  def to_float?(value)
    Float(value)
  rescue
    value
  end
  
  def parse_attribute_line(line)
    s = line.split(/[=;]/)
    {:name => s[0].strip, :value => to_float?(s[1].strip)}
  end

  def get_values_from_result(result, name_prefix=nil)
    values = {}

    attribute = nil
    composite = false


    result.each_with_index do |line, i|
      next if line.strip.empty? or i < 2 or line.index("#mbean = ") or line.index(JMXTERM_PROMPT)

      if composite then
        if (line.strip.end_with?('};')) then
          composite = false
        else
          p = parse_attribute_line(line)
          key = "#{attribute}.#{p[:name]}"
          key = "#{name_prefix}.#{key}" if name_prefix
          values[key] = p[:value]
        end
      else
        p = parse_attribute_line(line)
        attribute = p[:name]
        if (p[:value]  == '{') then
          composite = true
        else
          key = attribute
          key = "#{name_prefix}.#{key}" if name_prefix
          values[key] = p[:value]
        end
      end
    end

    values
  end

  def read_mbean(jmx_cmd, mbean, attributes)
    result = `echo get -b #{mbean} #{attributes} | #{jmx_cmd}`
    get_values_from_result result, ""
  end

  def read_jvm_pid_file()
    if @jvm_pid_file and not @jvm_pid_file.empty?
      @jvm_pid = File.open(@jvm_pid_file).readline.strip
      @mbean_server_location = @jvm_pid
    end

    error("No MBean server location configured: no PID file nor server URL") if @mbean_server_location.empty?
  end

  def configure_from_file(config_file)
    config = YAML::load(File.open(config_file, "r"))

    @jvm_pid_file = config["jvm_pid_file"]
    @mbean_server_location = config["mbean_server_location"]

    read_jvm_pid_file()

    @jmxterm_uberjar = config["jmxterm_uberjar"]

    @mbeans = config["mbeans"]
    @excluded_attributes = config["excluded_attributes"]
    @counter_attributes = config["counter_attributes"]
    @excluded_attributes ||= []
    @counter_attributes ||= []
  end

  def configure_from_options()
    @jvm_pid_file = option(:jvm_pid_file)
    @mbean_server_location = option(:mbean_server_url)

    read_jvm_pid_file()

    mbeans_attributes = option(:mbeans_attributes).to_s
    error("No MBeans and Attributes Names defined") if mbeans_attributes.empty?

    @jmxterm_uberjar = option(:jmxterm_uberjar)
    @mbeans = []

    mbeans_attributes.split("|").each do |mbean_spec|
      elements = mbean_spec.split("@")
      attributes = elements[0]
      mbean_name = elements[1]
      mbean = {}
      mbean["name"] = mbean_name
      mbean["attributes"] = attributes.split(",")
      @mbeans << mbean
    end
    @excluded_attributes = []
    @counter_attributes = []
  end

  def build_report

    config_file = option(:config_file).to_s

    if config_file.empty?
      configure_from_options()
    else
      configure_from_file(config_file)
    end

    jmx_cmd = "java -jar #{@jmxterm_uberjar} -l #{@mbean_server_location}"

    mbean_values = {}

    begin
      PTY.spawn(jmx_cmd) do |jmxterm_reader, jmxterm_writer, pid|
        begin
          jmxterm_writer.sync = true
          jmxterm_reader.expect(JMXTERM_PROMPT)
          @mbeans.each do |mbean|
            jmxterm_writer.puts "get -b #{mbean['name']} #{mbean['attributes'].join(' ')}"
            jmxterm_reader.expect(JMXTERM_PROMPT) do |output|
              mbean_values.merge!(get_values_from_result output.first, mbean["report_prefix"])
            end
          end
          jmxterm_writer.puts("quit")
          jmxterm_writer.flush
          jmxterm_reader.expect("#bye")
        rescue Exception => e
          error("Unable to connect to JVM at #{@mbean_server_location} using jmxterm: \n#{e.backtrace}")
          return
        ensure
          jmxterm_reader.close
          jmxterm_writer.close
        end
      end
    rescue PTY::ChildExited
    end

    mbean_values.delete_if{|key, value| @excluded_attributes.index(key)}

    @counter_attributes.each do |attr|
      key = attr["key"]
      value = mbean_values[key]
      granularity = attr["granularity"]
      counter(key, value, :per => granularity)
      mbean_values.delete(key)
    end

    report(mbean_values)
  end
end

