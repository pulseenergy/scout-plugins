require 'time'
require 'stringio'

class NginxAvgResponseTimes < Scout::Plugin
    needs 'yaml'
    
    OPTIONS=<<-EOS
      nginx_log_file:
          default: "/var/log/nginx/access.log"
          name: Log File
          notes: Location of the nginx log file to examine
      frequency:
          default: 5
          name: Frequency
          notes: The duration (in minutes) of the sliding window to average response times over
      methods_to_report:
          default: "GET"
          name: HTTP Methods to report
          notes: Will report on matching methods. i.e. 'GET, POST, PUT, DELETE'
      include_counts:
          default: "false"
          name: Include Counts
          notes: Will include counts in addition to average response times
      include_sizes:
          default: "false"
          name: Include Average Sizes
          notes: Will include average response size in addition to average response times
      url_regex:
          default: "\/api\/([^\"\?\/]*).*"
          name: URL Regex
          notes: Regular expression with one grouping expression for combining stats for like urls
    EOS
    
    def build_report
        parser = NginxParser.new(option(:nginx_log_file), option(:frequency), option(:url_regex))
        response_times = Hash.new
        counts = Hash.new
        response_sizes = Hash.new
        parser.yield_matched_lines do |match|
            method = match[1]
            address = match[2]
            response_time = match[3]
            response_size = match[4]
            next if not option(:methods_to_report).include? method
            key = "#{method}-#{address}"
            response_times[key] = (response_times[key] || 0) + Float(response_time)
            response_sizes[key] = (response_sizes[key] || 0) + Float(response_size)
            counts[key] = (counts[key] || 0) + 1
        end
        response_times.each_key do |key|
            if option(:include_counts) != "false"
                report(key + "-count" => counts[key])
            end
            report(key + "-avg-response" => 1000 * response_times[key] / counts[key])
            if option(:include_sizes) != "false"
                report(key + "-avg-size" => response_sizes[key] / counts[key])
            end
        end
    end
end

class NginxParser

  def initialize path, minutes_ago=5, url_regex="(\S*), "
    raise ArgumentError unless File.exists?( path )

    @log = File.open( path )
    # Must be a sortible date pattern like ISO-8601
    @date_format = "%FT%T%z"
    @date_regex = /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[\-\+]\d{2}:\d{2}/
    # If date is at the start of the line, we don't need to parse it out
    @date_at_start_of_line = true
    @starting_date = (Time.now - 60 * Integer(minutes_ago)).strftime(@date_format)
    @regex = /\S* [\d\.]+ .* \"(\S+) #{url_regex} \S*\" \d+ \"[^\"]*\" ([\d\.]+) (\d+) \"[^\"]*\"/
    @buffer_size = 10000
  end

  # file might be large, so start searching at end in blocks of buffer_size
  # won't return lines in order
  def each_line_after_starting_date &block
    search_end = @log.stat.size
    more_to_buffer = true
    while more_to_buffer
        @log.pos = [0, search_end - @buffer_size].max
        if @log.pos > 0
            # We might be midline
            @log.gets #advance to next line
        else
            # this is the last chunk to look at
            more_to_buffer = false
        end
        
        search_start = @log.pos
        while @log.pos < search_end
            line = @log.gets
            if (@date_at_start_of_line && line > @starting_date) || ((match = @date_regex.match(line)) && match[0] > @starting_date)
                yield line
            elsif more_to_buffer && (@date_at_start_of_line && line < @starting_date) || ((match = @date_regex.match(line)) && match[0] < @starting_date)
                # continue returning lines from this chunk, but don't look at earlier chunks
                more_to_buffer = false
            end
        end
        search_end = search_start
    end
  end

  def yield_matched_lines &block
      each_line_after_starting_date do |line|
          if match = @regex.match(line)
              yield match
          end
      end
  end
end
