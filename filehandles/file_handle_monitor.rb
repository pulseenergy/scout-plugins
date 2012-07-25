class FileHandleMonitor < Scout::Plugin
  OPTIONS=<<-EOS
  EOS

  def build_report
    report_hash={}
    
    # subtract one for header row
    report_hash["Total Handles"] = shell("lsof -n | wc -l").to_i - 1
    report_hash["Network Handles"] = shell("lsof -n -i | wc -l").to_i - 1
    report_hash["Unix Handles"] = shell("lsof -n -U | wc -l").to_i - 1

    report(report_hash)
  end

  # Use this instead of backticks. It's a separate method so it can be stubbed for tests
  def shell(cmd)
    `#{cmd}`
  end
end