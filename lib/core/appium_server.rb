require "fileutils"
require "os"

# Class describing handling of the Appium server for a given device and port.
class AppiumServer
  def initialize(role, udid, port)
    @role = role
    @udid = udid
    @port = port
  end

  # start the Appium server
  def start
    folder = File.join(Dir.pwd, "appium_logs")
    FileUtils.mkdir_p(folder) unless Dir.exist? folder
    grep_cmd = OS.windows? ? "find" : "grep"
    opened = `netstat -anp tcp | #{grep_cmd} "#{@port}"`.include?("LISTEN")
    until !opened
      log_warn("Role '#{@role}': Port #{@port} is busy! Trying port #{@port+2}\n", no_date=false, _print=true)
      @port = @port + 2
      opened = `netstat -anp tcp | #{grep_cmd} "#{@port}"`.include?("LISTEN")
    end

    spawn("appium --base-path=/wd/hub -p #{@port} >> #{folder}/#{@udid}.log 2>&1")

    opened = false
    log_info("Role '#{@role}': Starting Appium server on port #{@port} ", no_date=false, _print=true)
    until opened
      print "." if  ["INFO","DEBUG"].include? ENV["LOG_LEVEL"].upcase
      opened = `netstat -anp tcp | #{grep_cmd} "#{@port}"`.include?("LISTEN")
      sleep(0.1)
    end
    log_info(" Done!\n", no_date=true, _print=true)

    return @port
  end

  # stop the Appium server
  def stop
    log_info("Role '#{@role}': Stopping Appium server on port #{@port}... ", no_date=false, _print=true)
    if OS.windows?
      `for /f "tokens=5" %a in ('netstat -aon ^| find ":#{@port}" ^| find "LISTENING"') do taskkill /f /pid %a`
    else
      while true
        ps = `ps -A | grep "appium -p #{@port}"`
        break unless ps.include?("node")
        ps.split("\n") do |process|
          next if process.include?("grep")
          `kill #{process.split(" ")[0]}`
        end
        sleep(0.1)
      end
    end
    log_info("Done!\n", no_date=true, _print=true)
  end
end
