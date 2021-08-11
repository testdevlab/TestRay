# Class describing Appium driver initialisation-related methods,
# including capability assembly and driver creation.
class AppiumDriver
  def initialize(device, driver_port, udid, app_details, url)
    @device_name = device
    @driver_port = driver_port
    @udid = udid
    @app_details = app_details
    @app = app_details["Application"]
    @url = url
  end

  # assemble basic capabilities for Android
  def build_android_caps
    caps = ({
      "platformName" => "Android",
      "automationName" => "UiAutomator2",
      "deviceName" => @device_name,
      "udid" => @udid,
      "systemPort" => @driver_port,
      "adbExecTimeout" => 120000,
      "noReset" => true,
      "newCommandTimeout" => 2000 * 60,
    })
    if @app.downcase == "browser"
      if @url.nil?
        chromeDriverEx = Android.get_chrome_driver(@udid)
        chromeDriverExPath = File.join(Dir.getwd(), chromeDriverEx)
        caps.merge!({ "chromedriverExecutable" => chromeDriverExPath, })
      end
      caps.merge!({ "browserName" => "chrome" })
    else
      caps.merge!({
        "appActivity" => @app_details["Activity"],
        "appPackage" => @app_details["Package"]
      })
    end
    return caps
  end

    # assemble basic capabilities for iOS
  def build_ios_caps
    caps = {
      "platformName" => "iOS",
      "automationName" => "XCUITest",
      "deviceName" => @device_name,
      "udid" => @udid,
      "wdaLocalPort" => @driver_port,
      "noReset" => true,
      "newCommandTimeout" => 2000 * 60,
    }
    if @app.downcase == "browser"
      caps.merge!({ "browserName" => "Safari" })
    else
      caps.merge!({ "bundleId" => @app_details["iOSBundle"] })
    end
    return caps
  end

    # assemble basic capabilities for Mac
  def build_mac_caps
    app = @app_details.key?("MacAppName") ? @app_details["MacAppName"] : @app
    return {
      "platformName" => "Mac",
      "app" => app,
      "forceMjsonwp" => true,
    }
  end

  # assemble basic capabilities for Windows
  def build_windows_caps
    process_check = execute_powershell("Get-Process #{@app}")
    if process_check.include? "Exception"
      if @app_details.key?("UWPAppName") # launch UWP app
        spawn("start shell:AppsFolder\\#{@app_details["UWPAppName"]}")
      else # launch Win32 app
        spawn(execute_powershell("where.exe /r $HOME #{@app}.exe"))
      end
      sleep(5)
    end

    processWindowHandles = execute_powershell("(Get-Process #{@app}).MainWindowHandle").split("\n")
    appMainWindowHandleList = (processWindowHandles.select { |wh| wh.to_i != 0 })
    hexMainWindowHandle = appMainWindowHandleList[-1].to_i.to_s(16)

    caps = {
      "platformName" => "Windows",
      "forceMjsonwp" => true,
      "newCommandTimeout" => 2000 * 60,
    }
    if @app_details.key?("WinPath")
      caps.merge!({ "app" => @app_details["WinPath"] })
    else
      caps.merge!({ "appTopLevelWindow" => "#{hexMainWindowHandle}" })
    end
    return caps
  end

  # merge basic capabilities with those given in case and/or config
  def merge_full_caps(base_caps, config_caps, case_caps)
    full_caps = Marshal.load(Marshal.dump(base_caps))
    full_caps = full_caps.merge(config_caps) unless config_caps.nil?
    full_caps = full_caps.merge(case_caps) unless case_caps.nil?
    log_info("Appium capabilities: #{full_caps.to_json}")
    return full_caps
  end

  # build the Appium driver, given a set of capabilities
  def build_appium_driver(caps, local_url)
    @url = local_url if @url.nil?
    log_debug("Appium Server URL: #{@url}")
    return Appium::Driver.new(
      {
        caps: caps,
        appium_lib: { server_url: @url },
      },
      false
    )
  end
end

# Class describing Selenium driver initialisation-related methods,
# including capability assembly and driver creation.
class SeleniumDriver
  # unlike Appium, Selenium (Chrome) does not require setting any 'default'
  # capabilities, so can directly merge case and config parameters
  def initialize(url)
    @url = url
  end

  # merge case and/or config capabilities/options for Chrome
  def merge_chrome_ops(config_caps, case_caps)
    config_caps = {} unless config_caps
    case_caps = {} unless case_caps
    config_ops = (config_caps["chromeOptions"] ? config_caps["chromeOptions"] : {})
    case_ops = (case_caps["chromeOptions"] ? case_caps["chromeOptions"] : {})
    return config_ops if case_ops.empty?
    config_args, case_args = config_ops["args"], case_ops["args"]
    config_prefs, case_prefs = config_ops["prefs"], case_ops["prefs"]
  
    # start with simple merge to handle top-level keys only present in one hash
    final_ops = config_ops.merge(case_ops)
  
    # check args
    if config_args && case_args
      config_args.each do |config_arg|
        next if case_args.include?(config_arg)
        found_arg = false
        if config_arg.include? "="
          root_arg = config_arg.split("=")[0]
          case_args.each do |case_arg|
            if (case_arg.include? "=") && (case_arg.split("=")[0] == root_arg)
              found_arg = true
              break
            end
          end
        end
        case_args.append(config_arg) unless found_arg
      end
      final_ops["args"] = case_args
    end
  
    # check prefs
    if config_prefs && case_prefs
      final_ops["prefs"] = config_prefs.merge(case_prefs)
    end
  
    log_info("Chrome Options: #{final_ops}")
    return final_ops
  end

  # build the Chrome driver, given a set of options
  def build_chrome_driver(chrome_ops)
    if @url.nil?
      # local selenium instance
      localChromeOptions = Selenium::WebDriver::Chrome::Options.new(
        options: chrome_ops,
      )
      driver = Selenium::WebDriver.for(
        :chrome, options: localChromeOptions
      )
    else
      # remote selenium grid
      log_debug("Selenium Server URL: #{@url}")
      remoteChromeOptions = Selenium::WebDriver::Remote::Capabilities.chrome(
        "goog:chromeOptions": chrome_ops,
      )
      driver = Selenium::WebDriver.for(
        :remote, url: @url, desired_capabilities: remoteChromeOptions,
      )
    end
    return driver
  end
end