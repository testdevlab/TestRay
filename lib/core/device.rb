require "appium_lib"
require "base64"
require "csv"
require "fileutils"
require "os"
require "keisan"
require "selenium-webdriver"
require "screen-recorder"
require "date"
require_relative "rest_api"
require_relative "appium_server"
require_relative "device_drivers"

# Class describing one Selenium/Appium device (user),
# with its initialisation and control methods.
class Device
  attr_accessor :device_name, :udid

  def initialize(
    role:,
    platform:,
    udid:,
    network_details:,
    app_details:,
    timeout:,
    config_caps:,
    case_caps:,
    options:
  )
    @role = role
    @platform = platform
    @server_port, @url, @driver_port = network_details
    @app_details = app_details
    @application = app_details["Application"].downcase
    @udid = udid
    @device_name = "Test Device" # will be overwritten for local devices
    @timeout = timeout
    @config_caps = config_caps
    @case_caps = case_caps
    @options = options
    @driver = nil
  end

  def get_driver_tr
    @driver
  end

  # assemble the full capabilities for the device,
  # launch the server (if needed) and create the driver
  def build_driver()
    return if @application == "command"
    if @application == "desktop" # Selenium
      driverclass = SeleniumDriver.new(@url)
      base_caps = case @app_details["Browser"]
        when "chrome"
          full_ops = driverclass.merge_chrome_ops(@config_caps, @case_caps)
          @driver = driverclass.build_chrome_driver(full_ops)
        when "firefox"
          full_ops = driverclass.merge_firefox_ops(@config_caps, @case_caps)
          @driver = driverclass.build_firefox_driver(full_ops)
        when "safari"
          full_ops = driverclass.merge_safari_ops(@config_caps, @case_caps)
          @driver = driverclass.build_safari_driver(full_ops)
        when "ie"
          full_ops = driverclass.merge_ie_ops(@config_caps, @case_caps)
          @driver = driverclass.build_ie_driver(full_ops)
        when "edge"
          full_ops = driverclass.merge_edge_ops(@config_caps, @case_caps)
          @driver = driverclass.build_edge_driver(full_ops)
        else 
          raise "Chosen browser is \"#{@app_details["Browser"]}\" which is not " + 
          "in the list of available browsers: chrome,firefox,safari,ie,edge"
      end

    else # Appium
      @udid = convert_value(@udid)
      if @url.nil? # local Appium - need to create server too
        @server = AppiumServer.new(@role, @udid, @server_port)
        server_port = @server.start
        @url = "http://localhost:#{server_port}/"
      end
      driverclass = AppiumDriver.new(@device_name, @driver_port, @udid, @app_details, @url)
      base_caps = case @platform
        when "iOS" then driverclass.build_ios_caps()
        when "Mac" then driverclass.build_mac_caps()
        when "Windows" then driverclass.build_windows_caps()
        else driverclass.build_android_caps()
      end
      full_caps = driverclass.merge_full_caps(base_caps, @config_caps, @case_caps)
      @driver = driverclass.build_appium_driver(full_caps, @url)
    end
  end

  # executed provided command in OS command line.
  # Accepts:
  #   Value
  #   Greps
  #   Detach
  def command(action)
    command, greps, detach, log = action["Value"], action["Greps"], action["Detach"], action["Log"]
    run_type = action["RunType"]
    raise "Command Value cannot be empty!" unless command
    command = convert_udid(command, @udid)
    command = convert_value(command)

    log_info("#{@role}: running command: #{command}")
    output = ""
    if detach
      if ENV["LOG_LEVEL"] == "debug" || OS.windows? || action["Debug"]
        pid = spawn(command)
      else
        pid = spawn(command, [:out, :err]=>"/dev/null")
      end
    else
      if run_type == "capture"
        stdout, stderr, status = Open3.capture3(command)
        output = stdout + stderr
      elsif run_type == "ruby"
        `#{command}`
      else
        Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
          exit_status = wait_thr.value
          unless exit_status.success?
            path = take_error_screenshot unless ["adb", "command"].include?(@application)
            screenshot_error = (path ? "\nError Screenshot: #{path}" : "")
            raise "#{@role}: failed command '#{command}'#{screenshot_error}" if action["Raise"]
          end
          output = stdout.read + stderr.read
        end
      end
    end

    unless log.nil?
      if convert_value(log).to_s == "Reset network"
        $network_state = 0
      else 
        $network_state = 1
      end
    end

    log_info("#{@role}: command output: #{output}")

    return if greps.nil?
    greps.each do |grep|
      load_grep(grep, output)
    end
  end

  # retrieves the URL of currently open page.
  # Accepts:
  #   Greps
  def get_url(action)
    greps = action["Greps"]
    value = @driver.current_url
    log_info("URL value: #{value}")

    unless greps.nil?
      greps.each do |grep|
        load_grep(grep, value)
      end
    end
  end

  # calls an HTTP GET request to provided URL.
  def get_call(action)
    Api.get_call(action)
  end

  # set orientation of the phone.
  def set_orientation(action)
    try = 0
    while try < 5
      begin
        if action["Value"].downcase == "landscape"
          @driver.driver.rotate :landscape
          return
        else
          @driver.driver.rotate :portrait
          return
        end
      rescue => e
        log_warn(e.message) if try == 4
        sleep 0.5
      end
      try += 1
    end
  end

  # calls an HTTP POST request to provided URL.
  def post_call(action)
    Api.post_call(action)
  end

  # starts the Appium driver (Selenium driver starts on its own).
  def start_driver
    return unless @udid
    log_info("Role '#{@role}': Starting Appium driver on port #{@driver_port} (device #{@udid})...")
    begin
      @driver.start_driver
      log_info("Role '#{@role}': Appium driver started!")
    rescue => e
      raise "Role '#{@role}': Could not start Appium driver:\n#{e.message}"
    end
  end

  # stops the Appium or Selenium driver if it's running.
  def stop_driver(action = nil)
    return unless @driver
    begin
      if @udid
        log_info("Role '#{@role}': Stopping Appium driver on port #{@driver_port} (device #{@udid})... ", no_date=false, _print=true)
        @driver.driver_quit
      else
        log_info("Role '#{@role}': Stopping Selenium driver... ", no_date=false, _print=true)
        @driver.quit
      end
      log_info("Done!\n", no_date=true, _print=true)
    rescue => e
      message = "Role '#{@role}': Could not stop the driver:\n#{e.message}"
      if action && action.key?("NoRaise") && action["NoRaise"]
        log_warn(message)
      else
        raise message
      end
    end
  end

  # starts an Appium server.
  def start_server
    @server.start if @server
  end

  # stops Appium server if it's running.
  def stop_server
    @server.stop if @server
  end

  # navigates to the provided URL.
  # Accepts:
  #   Value
  def navigate(action)
    url = convert_value(action["Value"])
    @driver.get(url)
  end

  # closes the currently opened app and puts it in the background
  def close_app(action = nil)
    @driver.background_app(-1)
  end

  # hides keyboard (Only Mobile)
  def hide_keyboard(action = nil)
    @driver.hide_keyboard
  end

  # Toggles wifi using the iOS Control Center (available only for iOS with Physical Devices, not simulators)
  def toggle_wifi(action = nil)
    # Get the window size 
    size = @driver.window_size

    # Get the top right offset
    top_right_offset = {x: size.width, y: 0}
    
    # Get the bottom right offset
    bottom_right_offset = {x: size.width, y: size.height}

    opts = {
      start_x: top_right_offset[:x],
      start_y: top_right_offset[:y],
      end_x: bottom_right_offset[:x],
      end_y: bottom_right_offset[:y],
    }

    # Swipe down to make Control Center appear
    action = Appium::TouchAction.new(@driver).swipe(opts).perform

    # Toggle the wifi
    wifi_toggle_button = @driver.find_element(:accessibility_id, "wifi-button") 
    wifi_toggle_button.click

    opts = {
      start_x: bottom_right_offset[:x],
      start_y: bottom_right_offset[:y],
      end_x: top_right_offset[:x],
      end_y: top_right_offset[:y],
    }

    # Swipe up to make Control Center disappear
    action = Appium::TouchAction.new(@driver).swipe(opts).perform
    log_info("Toggled wifi using Control Center!")
  end

  # launches the app specified by the Android app package / iOS bundle ID
  # defaults to the app under test if Value is not provided
  # Accepts:
  #   Value (optional)
  def launch_app(action)
    app_id = action["Value"]
    if app_id
      if @platform == "iOS"
        @driver.execute_script('mobile: launchApp', {'bundleId': app_id})
      elsif @platform == "Android"
        @driver.activate_app(app_id)
      end
    else
      @driver.launch_app
    end
  end

  # closes the app specified by the Android app package / iOS bundle ID
  # defaults to the app under test if Value is not provided
  # Accepts:
  #   Value (optional)
  def terminate_app(action)
    app_id = action["Value"]
    if app_id
      if @platform == "iOS"
        @driver.execute_script('mobile: terminateApp', {'bundleId': app_id})
      elsif @platform == "Android"
        @driver.terminate_app(app_id)
      end
    else
      @driver.close_app
    end
  end

  # starts recording test execution. Whole desktop is recorded if 'udid' is not
  # set.
  # Accepts:
  #   Value
  #   Resolution ([width]x[height])
  #   Video_Quality
  #   FPS (not available for Android)
  #   Bitrate (not available for desktop)
  #   Time
  def start_record(action)
    output = action["Value"] ? action["Value"] : "recording"
    fps = action["FPS"] ? action["FPS"] : "30"
    bitrate = action["Bitrate"] ? convert_value(action["Bitrate"]) : 5000000

    path = File.join(Dir.pwd, "Reports")

    FileUtils.mkdir_p(path) unless Dir.exist? path

    if @udid
      res = action["Resolution"]

      video_quality = action["Video_Quality"] ?
        action["Video_Quality"] :
        "medium"

      res = @options["resolution"] if @options["resolution"] &&
                                          !@options["resolution"].empty? &&
                                          !res
      video_type = action["Video_Type"] ? action["Video_Type"] : "h264"
      if @platform == "iOS"
        log_info("#{@role}: Video configuration: video_type -> #{video_type}, " +
        "video_fps -> #{fps}, video_quality -> #{video_quality}")
        timeout = action["Time"] ? action["Time"] : "260"
        @driver.start_recording_screen(
          video_type: video_type,
          time_limit: timeout,
          video_fps: fps,
          video_quality: video_quality,
        )
        return
      end

      timeout = action["Time"] ? action["Time"] : "600"

      if res && !res.empty?
        if !res.include?("x")
          log_info("resolution format is wrong: #{res}. " +
                 "Should be: [width]x[height]") if !res.include?("x")
          log_info("#{@role}: Starting recording with default resolution, time_limit: #{timeout}, bit_rate: #{bitrate}")

          @driver.start_recording_screen_a time_limit: timeout, bit_rate: bitrate
        else
          log_info("#{@role}: Starting recording with #{res} resolution, time_limit: #{timeout}, bit_rate: #{bitrate}")
          @driver.start_recording_screen_a(
            video_size: "#{res}",
            time_limit: timeout,
            bit_rate: bitrate,
          ) if res.include?("x")
        end
      else
        log_info("Starting recording with default resolution, time_limit: #{timeout}, bit_rate: #{bitrate}")
        @driver.start_recording_screen_a(time_limit: timeout, bit_rate: bitrate) 
      end
    else
      video_quality = action["Video_Quality"] ?
        action["Video_Quality"] :
        "faster"

      timeout = action["Time"] ? action["Time"] : "180"
      res = action["Resolution"] ? action["Resolution"] : "1080x720"

      advanced = {
        input: {
          framerate: fps,
          video_size: res,
        },
        output: {
          t: timeout,
          preset: video_quality,
        },
        log: "recorder.log",
        loglevel: "level+debug",
      }

      advanced[:input][:pix_fmt] = "yuv420p" unless OS.windows?

      @recorder = ScreenRecorder::Desktop.new(
        output: File.join(path, "#{output}.mkv"),
        advanced: advanced,
      )
      @recorder.start
    end
  end

  # stops recording test execution. Name, height and width can be provided to
  # modify end file.
  # Accepts:
  #   Value
  #   Height
  #   Width
  def end_record(action)
    name, height, width = convert_value(action["Value"]), convert_value(action["Height"]), convert_value(action["Width"])
    if @udid
      if @options && !@options.empty? && @options["screenPercentage"] && !@options["screenPercentage"].empty? &&
         @options["resolution"].include?("x") &&
         @options["screenPercentage"].include?("x")
        height = @options["resolution"].split("x")[1].to_f *
                 @options["screenPercentage"].split("x")[1].to_f
        width = @options["resolution"].split("x")[0].to_f *
                @options["screenPercentage"].split("x")[0].to_f
      else
        log_info("screenPercentage format is wrong: " +
               "#{@options["screenPercentage"]}. Should be: [width]x[height]")
      end

      mp4_video = @driver.stop_recording_screen
      File.open(name, "wb") { |f| f.write(Base64.decode64(mp4_video)) }

      rm_cmd = "rm"
      if OS.windows?
        rm_cmd = "del"
      end

      if height && width && height != "" && width != ""
        out = `#{rm_cmd} cropped_#{name}`
        log_info("Cropping to #{width}:#{height}")
        log_info("ffmpeg -hide_banner -loglevel panic -i #{name} -vf " +
               "\"crop=#{width}:#{height}:0:0\" -threads 5 -preset ultrafast " +
               "-strict -2 cropped_#{name} > /dev/null")
        out = `ffmpeg -hide_banner -loglevel panic -i #{name} -vf "crop=#{width}:#{height}:0:0" -threads 5 -preset ultrafast -strict -2 cropped_#{name} > /dev/null`
      end
    else
      @recorder.stop
    end
  end

  # clicks on the provided element. Multiple location strategies are
  # accepted - css, xPath, id.
  # Accepts:
  #   Strategy
  #   Id
  #   Condition
  #   CheckTime
  #   OffsetX
  #   OffsetY
  #   NoRaise
  def click(action)
    action = convert_value_pageobjects(action);
    start = Time.now
    return unless wait_for(action)

    action["Condition"] = nil
    start_error = Time.now

    el = wait_for(action)

    now = Time.now
    log_info("Time to find element: #{now - start - (now - start_error) / 2}s " +
           "error #{(now - start_error)}") if action["CheckTime"]
    error = nil

    wait_time = (action["CheckTime"] ? action["CheckTime"] : @timeout)

    while (Time.now - start) < wait_time
      begin
        @platform == "iOS" ?
          @driver.action.move_to(el) :
          @driver.action.move_to(el).perform
      rescue => e
        error = e
      end
      begin
        if !(action["OffsetX"].nil? && action["OffsetY"].nil?)
          @driver.action.move_to(el, action["OffsetX"], action["OffsetY"])
            .click
            .perform
        else
          el.click
        end
        log_info("Time for click: #{Time.now - start}s") if action["CheckTime"]
        return
      rescue => e
        error = e
      end
    end

    if error && !action["NoRaise"]
      path = take_error_screenshot()
      raise "#{@role}: Element '#{action["Id"]}': #{error.message}\nError Screenshot: #{path}"
    end
  end

  # Hovers over an element.
  # Accepts:
  #   Strategy
  #   Id
  #   Condition
  #   CheckTime
  #   NoRaise
  def hover(action)
    action = convert_value_pageobjects(action);
    start = Time.now
    return unless wait_for(action)

    action["Condition"] = nil
    start_error = Time.now

    el = wait_for(action)

    now = Time.now
    log_info("Time to find element: #{now - start - (now - start_error) / 2}s " +
           "error #{(now - start_error)}") if action["CheckTime"]
    error = nil

    wait_time = (action["CheckTime"] ? action["CheckTime"] : @timeout)

    while (Time.now - start) < wait_time
      begin
        @platform == "iOS" ?
          @driver.action.move_to(el) :
          @driver.action.move_to(el).perform
      rescue => e
        error = e
      end
      begin
        @driver.action.move_to(el).release.perform
        log_info("Time for click and hold: #{Time.now - start}s") if action["CheckTime"]
        return
      rescue => e
        error = e
      end
    end
    if error && !action["NoRaise"]
      path = take_error_screenshot()
      raise "#{@role}: #{error.message}\nError Screenshot: #{path}"
    end
  end

  # tap_by_coord on the provided element but over its coordinates. Multiple location 
  # strategies are accepted - css, xPath, id.
  # Accepts:
  #   Strategy
  #   Id
  #   Condition
  #   CheckTime
  #   NoRaise
  def tap_by_coord(action)
    action = convert_value_pageobjects(action);
    el = wait_for(action)
    el_location = el.location
    log_info("#{@role}: element coordinates: x -> #{el_location.x}, y -> #{el_location.y}")
    action = Appium::TouchAction.new(@driver).press(x: el_location.x, y: el_location.y).wait(600).release.perform
  end

  # taps on an element, only mobile.
  def tap(action)
    action = convert_value_pageobjects(action);
    el = wait_for(action)
    action = Appium::TouchAction.new(@driver).tap(element: el).release.perform
  end

  # presses on the provided element. Uses Appium's TouchAction.
  # Accepts:
  #   Strategy
  #   Id
  #   Condition
  #   CheckTime
  #   NoRaise
  def press(action)
    action = convert_value_pageobjects(action);
    start = Time.now
    return unless wait_for(action)

    action["Condition"] = nil
    start_error = Time.now

    el = wait_for(action)

    now = Time.now
    log_info("Time to find element: #{now - start - (now - start_error) / 2}s " +
           "error #{(now - start_error)}") if action["CheckTime"]
    error = nil

    wait_time = (action["CheckTime"] ? action["CheckTime"] : @timeout)

    while (Time.now - start) < wait_time
      begin
        @platform == "iOS" ?
          @driver.action.move_to(el) :
          @driver.action.move_to(el).perform
      rescue => e
        error = e
      end

      begin
        Appium::TouchAction.new(@driver).press(el).wait(600).release.perform
        log_info("Time for click: #{Time.now - start}s") if action["CheckTime"]
        return
      rescue => e
        error = e
      end
    end
    if error && !action["NoRaise"]
      path = take_error_screenshot()
      raise "#{@role}: #{error.message}\nError Screenshot: #{path}"
    end
  end

  # clicks and holds on the provided element.
  # Accepts:
  #   Strategy
  #   Id
  #   Condition
  #   CheckTime
  #   NoRaise
  def click_and_hold(action)
    action = convert_value_pageobjects(action);
    start = Time.now
    return unless wait_for(action)

    action["Condition"] = nil
    start_error = Time.now

    el = wait_for(action)

    now = Time.now
    log_info("Time to find element: #{now - start - (now - start_error) / 2}s " +
           "error #{(now - start_error)}") if action["CheckTime"]
    error = nil

    wait_time = (action["CheckTime"] ? action["CheckTime"] : @timeout)

    while (Time.now - start) < wait_time
      begin
        @platform == "iOS" ?
          @driver.action.move_to(el) :
          @driver.action.move_to(el).perform
      rescue => e
        error = e
      end
      begin
        @driver.action.click_and_hold(el).perform
        log_info("Time for click and hold: #{Time.now - start}s") if action["CheckTime"]
        return
      rescue => e
        error = e
      end
    end
    if error && !action["NoRaise"]
      path = take_error_screenshot()
      raise "#{@role}: #{error.message}\nError Screenshot: #{path}"
    end
  end

  # sets the provided value for element.
  # Accepts:
  #   Strategy
  #   Id
  #   Value
  def send_keys(action)
    action = convert_value_pageobjects(action);
    value = action["Value"]
    el = nil
    value = value.gsub("$AND_ROLE$", @role) if value && value.is_a?(String) && value.include?("$AND_ROLE$")
    log_info("#{@role}: Sending keys: #{value}")

    el = wait_for(action) if (!action["Actions"] && action["Strategy"])

    start = Time.now
    error = nil

    while (Time.now - start) < @timeout
      begin
        if convert_value(value) == "backspace"
            el.send_keys(:backspace)
        elsif !action["Actions"] && el
          el.send_keys(convert_value(value))
        else
          if convert_value(value) == "enter"
            @driver.action.send_keys(:enter).perform
          elsif convert_value(value) == "arrow_down"
            @driver.action.send_keys(:arrow_down).perform
          elsif convert_value(value) == "tab"
            @driver.action.send_keys(:tab).perform
          elsif el
            @driver.action.send_keys(convert_value(value), el).perform
          else
            @driver.action.send_keys(convert_value(value)).perform
          end
        end
        return
      rescue => e
        error = e
      end
    end
    if error && !action["NoRaise"]
      path = take_error_screenshot()
      raise "#{@role}: #{error.message}\nError Screenshot: #{path}"
    end
  end


  #Clears a provided text field
  # Accepts:
  #   Strategy
  #   Id
  def clear_field(action) 
    action = convert_value_pageobjects(action);
    el = nil
    el = wait_for(action) if (!action["Actions"] && action["Strategy"])
    start = Time.now
    error = nil
    while (Time.now - start) < @timeout
      begin
        el.clear
        return
      rescue => e
        error = e
      end
    end
    if error && !action["NoRaise"]
      path = take_error_screenshot()
      raise "#{@role}: #{error.message}\nError Screenshot: #{path}"
    end
  end


  # Accepts:
  #   Strategy
  #   Id
  def swipe_up(action)
    action = convert_value_pageobjects(action);
    el = wait_for(action)
    el_location = el.location
    opts = {
      start_x: el_location.x,
      start_y: el_location.y,
      end_x: el_location.x,
      end_y: 0,
    }
    action = Appium::TouchAction.new(@driver).swipe(opts).perform
  end

  # Accepts:
  #   Strategy
  #   Id
  def swipe_down(action)
    action = convert_value_pageobjects(action);
    el = wait_for(action)
    el_location = el.location

    opts = {
      start_x: el_location.x,
      start_y: el_location.y,
      end_x: el_location.x,
      end_y: 1500,
    }

    action = Appium::TouchAction.new(@driver).swipe(opts).perform
  end

  def swipe_elements(action)
    # swipe from element1 to element2
    el1 = wait_for(action["Element1"])
    el2 = wait_for(action["Element2"])
    el1_x = el1.location.x + (el1.size.width / 2)
    el1_y = el1.location.y + (el1.size.height / 2)
    el2_x = el2.location.x + (el2.size.width / 2)
    el2_y = el2.location.y + (el2.size.height / 2)
    opts = {
      start_x: el1_x,
      start_y: el1_y,
      end_x: el2_x,
      end_y: el2_y,
      duration: 2000,
    }

    action = Appium::TouchAction.new(@driver).swipe(opts).perform
  end

  # TODO
  def driver_method(action)
    log_info("TODO")
    # HERE USER WILL INPUT A TEXT AND THEN THE METHOD WILL PARSE IT INTO A METHOD
    # @driver.send(action["Method"], action["Var"]) # Check how to send multiple vars
  end

  # TODO
  def touch_actions(action)
    log_info("TODO")
    # HERE USER WILL PUT SEVERAL ACTIONS IN A LIST:
    # - Action: press
    #   Coordinates:
    #     X:
    #     ...
    #   Element:
    #     Strategy:
    #     Id:
    # - Action: release
    #  ...
  end

  # swipes to provided X and Y values.
  # Accepts:
  #   StartX
  #   StartY
  #   OffsetX
  #   OffsetY
  def swipe_coord(action)
    opts = {
      start_x: action["StartX"],
      start_y: action["StartY"],
      end_x: action["EndX"] ? action["EndX"] : 0,
      end_y: action["EndY"] ? action["EndY"] : 0,
    }

    action = Appium::TouchAction.new(@driver).swipe(opts).perform
  end

  # clicks on the provided coordinates, if not provided then middle of the screen
  # Accepts:
  # X
  # Y
  def click_coord(action = nil)
    if action["X"] && action["Y"]
      action = Appium::TouchAction.new(@driver).press(x: action["X"], y: action["Y"]).release.perform
    else
      window_size = @driver.window_size
      x_middle = window_size.width * 0.5
      y_middle = window_size.height * 0.5

      action = Appium::TouchAction.new(@driver).press(x: x_middle, y: y_middle).release.perform
    end
  end

  # sets the app context to the specified value (native, web, etc.)
  # Accepts:
  #   Value
  def context(action)
    context = convert_value(action["Value"])
    @driver.set_context(context)
  end

  # parses the provided attribute value from element.
  # Accepts:
  #   Strategy
  #   Id
  #   Greps
  def get_attribute(action)
    el = wait_for(action)
    return unless el
    
    greps = action["Greps"]

    return if greps.nil?

    greps.each do |grep|
      attr_value = el.attribute(grep["attr"])
      log_info("Element attribute is " + attr_value.to_s)
      load_grep(grep, attr_value)
    end
  end

  # sets a new attribute value for element.
  # Accepts:
  #   Strategy
  #   Id
  #   Attribute
  #   Value
  def set_attribute(action)
    action = convert_value_pageobjects(action);
    el = wait_for(action)

    attribute = convert_value(action["Attribute"])
    value = convert_value(action["Value"])

    @driver.execute_script(
      "arguments[0].setAttribute('#{attribute}', '#{value}');", el
    )
  end

  # removes an attribute value from element.
  # Accepts:
  #   Strategy
  #   Id
  #   Attribute
  def remove_attribute(action)
    action = convert_value_pageobjects(action);
    el = wait_for(action)

    attribute = convert_value(action["Attribute"])

    @driver.execute_script("arguments[0].removeAttribute('#{attribute}');", el)
  end

  # retrieves the current app context
  # Accepts:
  #   Greps
  def get_current_context(action)
    greps = action["Greps"]
    cur_context = @driver.current_context
    log_info("Current app context: #{cur_context}")

    return if greps.nil?
    greps.each do |grep|
      ENV[grep["var"]] = cur_context
    end
  end

  # returns all available app contexts (native, web, etc.)
  def get_contexts(action)
    log_info(@driver.available_contexts.to_s)
    # TODO: Grep context into variables
  end

  # parses and saves the source code for currect page.
  def get_source(action)
    source = if @platform.nil? || @platform == "desktop"
      @driver.page_source
    else
      @driver.get_source
    end
    File.write("./page_source.xml", source)
  end

  # parses value that is currently in clipboard.
  # Accepts:
  #   Greps
  def clipboard(action)
    greps = action["Greps"]
    value = @driver.get_clipboard
    log_info("#{@role}: Clipboard value: #{value}")

    return if greps.nil?

    greps.each do |grep|
      load_grep(grep, value)
    end
  end

  # switches to the provided window index.
  # Accepts:
  #   Value
  #   CheckTime
  def switch_window(action)
    index = action["Value"]
    wait_time = (action["CheckTime"] ? action["CheckTime"] : @timeout)
    start = Time.now
    found = false
    while (Time.now - start) < wait_time
      found = @driver.window_handles.length >= index+1
      break if found
      sleep 0.5
    end

    if !found
      path = take_error_screenshot()
      raise "#{@role}: Could not find enough window handles: requested index" +
            " #{index}, found total #{@driver.window_handles.length}\nError Screenshot: #{path}"
    end

    log_info("#{@role}: Switching to window: #{index}")
    @driver.switch_to.window @driver.window_handles[index.to_i]
  end

  # open new tab
  def new_tab(action = nil)
    @driver.manage.new_window(:tab)
  end

  # switches to the provided window index.
  # Accepts:
  #   Value
  def switch_frame(action)
    index = action["Value"]
    if action["Id"] && action["Strategy"]
      el = wait_for(action)
      if el
        log_info("#{@role}: Switching to frame element: #{action["Strategy"]}:#{action["Id"]}")
        index = el
      else
        raise "\n#{@role}: Element '#{action["Strategy"]}:#{action["Id"]}' could not be found"
      end
    end
    if !index
      raise "#{@role}: you must specify Value or Strategy + Id for switch_frame type!"
    end
    if el == nil && index == "parent"
      @driver.switch_to.default_content
    else
      begin
      @driver.switch_to.frame index
      rescue => e 
        log_info("#{@role}: There was an error while switching frames: #{e.message}", "error")
      end
    end
  end

  # parses provided element text value.
  # Accepts:
  #   Strategy
  #   Id
  #   Greps
  def get_text(action)
    action = convert_value_pageobjects(action);
    greps = action["Greps"] ? action["Greps"] : []
    el = wait_for(action)
    return unless el

    start = Time.now
    found = false

    while (Time.now - start) < @timeout
      el = wait_for(action)
      value = el.text
      log_info("#{@role}: Element text: #{value}") if value

      greps.each do |grep|
        if value
          load_grep(grep, value)
          found = true if ENV[grep["var"]] != ""
        else
          sleep 0.5 if grep["condition"] && grep["condition"] == "nempty"
        end
      end
      break if found
    end

    if !found
      path = take_error_screenshot()
      raise "#{@role}: Could not match element text to requirements: \n#{greps}\nError Screenshot: #{path}"
    end
  end

  # waits for the provided element to be present.
  # Accepts:
  #   Strategy
  #   Id
  #   Index
  #   Time or CheckTime
  #   Condition
  def wait_for(action)
    action = convert_value_pageobjects(action);
    locator_strategy, id = action["Strategy"], action["Id"]
    if action["Condition"]
      return unless check_condition(action)
    end

    wait_time = (action["Time"] ? action["Time"] : @timeout)
    wait_time = (action["CheckTime"] ? action["CheckTime"] : wait_time)
    index = action["Index"]

    exception = ""
    start = Time.now
    try = 0
    while (Time.now - start) < wait_time
      if id.is_a?(String)
        begin
          id = convert_value(id)
          locator_strategy = convert_value(locator_strategy)
          try += 1
          el = nil
          if index
            els = @driver.find_elements(locator_strategy, id)
            if index.is_a?(String) && index == "last"
              log_info("#{@role}: Index element: #{els.length - 1}")
              el = els[-1]
            else
              el = (els.length > index ? els[index] : els[-1])
            end
          else
            el = @driver.find_element(locator_strategy, id)
          end
          return el
        rescue => e
          exception = e
          sleep(0.2)
        end
      else
        i = 0
        id.each do |locator|
          locator = convert_value(locator)
          begin
            el = @driver.find_element(convert_value(locator_strategy[i]), locator)
            return el
          rescue => e
            exception = e
            sleep(0.1)
          end
          i += 1
        end
      end
    end

    if !action["NoRaise"]
      path = take_error_screenshot()
      raise "\n#{@role}: Element '#{id}' is not visible after #{wait_time} " +
              "seconds \nException: #{exception}\nError Screenshot: #{path}"
    end
  end

  # sets provided network condition to driver.
  # Accepts:
  #   Condition
  def set_network(action)
    conditions = action["Condition"]
    @driver.network_conditions = conditions
  end

  # Accepts:
  #   Width
  #   Height
  def maximize(action = nil)
    @driver.manage.window.maximize
    if action["Width"] && action["Height"]
      @driver.manage.window.resize_to action["Width"], action["Height"]
    end
  end

  def minimize(action = nil)
    @driver.manage.window.minimize
  end

  # Accepts:
  #   Name
  #   Folder
  #   Options
  def write_file(action)
    log_info("#{@role}: writing file")
    name = (action["Name"] ? convert_value(action["Name"]) : "name.txt")
    log_info("File Name: #{name}")
    folder = (action["Folder"] ? convert_value(action["Folder"]) : ".")
    begin
      Dir.mkdir(folder) unless Dir.exist? folder
    rescue => e
    end
    value = convert_value(action["Value"])
    log_info("#{@role}: Creating File with file Name: #{name} and Value: #{value}")
    File.open(name, "w") { |f| f.write(value) }
  end

  def submit(action)
    el = wait_for(action)
    el.submit
  end

  def scroll_to(action)
    el = wait_for(action)
    options = (action["Options"] ? action["Options"] : "true")
    @driver.execute_script("arguments[0].scrollIntoView(#{options});", el)
  end

  def click_js(action)
    el = wait_for(action)
    @driver.execute_script("arguments[0].click();", el)
  end

  # takes screenshot. The image is saved in the provided location.
  # Accepts:
  #   Name
  #   Folder
  #   Overwrite
  #   Interval
  #     For
  #     Every
  def screenshot(action)
    name = convert_value(action["Name"])
    filename_base = "screenshot_#{name}"
    folder = File.join(Dir.pwd, "Reports", "screenshots")
    if convert_value(action["Folder"]) != ""
      folder = convert_value(action["Folder"])
    end

    begin
      FileUtils.mkdir_p(folder) unless Dir.exist? folder
    rescue => e
    end

    if action["Interval"]
      interval_for = convert_value(action["Interval"]["For"]).to_f
      interval_every = convert_value(action["Interval"]["Every"]).to_f
    else
      interval_for, interval_every = 1.0, 1.0
    end

    start = Time.now
    loop_times = (interval_every != 0.0 ?
      interval_for / interval_every.to_i :
      1)

    (1..loop_times).each do |i|
      break if Time.now - start > interval_for
      filename_ext = action["Overwrite"] ? ".png" : "_#{i}_#{Time.now.to_f}.png"
      path = File.join(folder, filename_base + filename_ext)
      log_info("#{@role}: Saving '#{filename_base + filename_ext}'")

      if @udid
        @driver.screenshot(path)
      else
        screenshot_file = @driver.screenshot_as(:base64)
        File.open(path, "wb") { |f| f.write(Base64.decode64(screenshot_file)) }
      end

      break if Time.now - start > interval_for
      sleep(interval_every - (Time.now - start).to_f % interval_every)
    end
  end

  # waits for the element to have a specific attribute value.
  # Accepts:
  #   Strategy
  #   Id
  #   Attribute
  #   Value
  #   Time
  def wait_for_attribute(action)
    action = convert_value_pageobjects(action);
    locator_strategy = convert_value(action["Strategy"])
    id, att, value = convert_value(action["Id"]), convert_value(action["Attribute"]), convert_value(action["Value"])
    default_wait_time = (action["Time"] ? action["Time"] : @timeout)
    exception = ""
    start = Time.now

    while (Time.now - start) < default_wait_time
      begin
        el = @driver.find_element(locator_strategy, id)
        if el.attribute(att) == value
          return el
        end
      rescue => e
        exception = e
        sleep(0.1)
      end
    end

    path = take_error_screenshot()
    raise "\n#{@role}: Element '#{locator_strategy}:#{id}' does not have " +
            "attribute #{att} = #{value} after " +
            "#{default_wait_time} seconds \nException: #{exception}\nError Screenshot: #{path}"
  end

  # waits for the element to have a specific JS property value.
  # Accepts:
  #   Strategy
  #   Id
  #   Property
  #   Value
  #   Time
  def wait_for_property(action)
    action = convert_value_pageobjects(action);
    locator_strategy = convert_value(action["Strategy"])
    id, prop, value = convert_value(action["Id"]), convert_value(action["Property"]), convert_value(action["Value"])
    default_wait_time = (action["Time"] ? action["Time"] : @timeout)
    exception = ""
    start = Time.now

    while (Time.now - start) < default_wait_time
      begin
        el = @driver.find_element(locator_strategy, id)
        elprop = el.property(prop)
        if elprop.to_s == value.to_s
          log_info("Property: #{prop} matched Value: #{value.to_s}")
          return el
        end
      rescue => e
        exception = e
        sleep(0.1)
      end
    end

    path = take_error_screenshot()
    raise "\n#{@role}: Element '#{locator_strategy}:#{id}' does not have " +
            "property #{prop} = #{value} after " +
            "#{default_wait_time} seconds \nException: #{exception}\nError Screenshot: #{path}"
  end

  # Accepts:
  #   Time
  def visible_for(action)
    time = (action["Time"] ? action["Time"] : @timeout)
    start = Time.now
    while (Time.now - start) < time.to_f
      action["Time"] = 0.2
      self.wait_for(action)
    end
  end

  def add_cookie(action)
    @driver.manage.add_cookie :name => convert_value(action["Name"]), :value => convert_value(action["Value"])
  end

  def wait_for_page_to_load(action)
    action["Time"] = (action["Time"] ? action["Time"] : 10)
    wait = Selenium::WebDriver::Wait.new(:timeout => action["Time"])
    wait.until {@driver.execute_script('var browserState = document.readyState; return browserState;') == "complete" }
  end

  # Accepts:
  # Time
  # Value
  def visible_for_not_raise(action)
    time = (action["Time"] ? action["Time"] : @timeout)
    start = Time.now
    value = action["Value"]
    action["Value"] = true
    while (Time.now - start) < time.to_f
      action["Time"] = 0.2 
      if visible(action)
        sleep 0.2
      else
        action["Time"] = @timeout
        # If it wasn't visible from the begining but we expect 
        # Value: false (Not visible), then it should return true
        return !value
      end
    end
    action["Time"] = @timeout
    # If it was visible for the amount of time but we expect 
    # Value: false (Not visible), then it should return false
    return value
  end

  # Accepts:
  #   Time
  def collection_visible_for(action)
    time = (action["Time"] ? action["Time"] : @timeout)
    start = Time.now
    while (Time.now - start) < time
      action["Elements"].each do |element|
        element["Time"] = 0.2
        self.wait_for(element)
      end
    end
  end

  # waits until the provided element is visible.
  # Accepts:
  #   Strategy
  #   Id
  #   Time
  #   Value
  def visible(action)
    action = convert_value_pageobjects(action);
    default_wait_time = (action["Time"] ? action["Time"] : 0.2)
    start = Time.now
    while (Time.now - start) < default_wait_time
      begin
        el = @driver.find_element(convert_value(action["Strategy"]), convert_value(action["Id"]))
        return true if action["Value"]
        sleep 0.2
      rescue => e
        return true unless action["Value"]
        sleep 0.2
      end
    end
    return false
  end

  # waits until the provided element is not visible.
  # Accepts:
  #   Strategy
  #   Id
  #   Time
  def wait_not_visible(action)
    action = convert_value_pageobjects(action);
    id = convert_value(action["Id"])
    default_wait_time = (action["Time"] ? action["Time"] : @timeout)
    start = Time.now
    while (Time.now - start) < default_wait_time
      begin
        el = @driver.find_element(convert_value(action["Strategy"]), id)
        log_info("#{@role}: Element '#{id}' is still visible, waiting ...")
        sleep(0.1)
      rescue => e
        return
      end
    end
    path = take_error_screenshot()
    raise "\nElement '#{id}' is still visible after " +
            "#{default_wait_time} seconds\nError Screenshot: #{path}"
  end

  # guarantee that the checkbox is checked or unchecked depending on the option
  # Accepts:
  #   Strategy
  #   Id
  #   Option -> check or uncheck
  def credentials_checkbox(action)
    action = convert_value_pageobjects(action);
    option = convert_value(action["Option"])
    el = @driver.find_element(convert_value(action["Strategy"]), convert_value(action["Id"]))
    input = el.find_element(:xpath => "./input")
    span = el.find_element(:xpath => "./span")
    is_checked = false
    
    if input.attribute("checked")
      is_checked = true
    end
      
    if (is_checked) && (option == "uncheck")
      span.click
    elsif (option == "check") && (!is_checked)
      span.click
    end
  end

  # opens driver notifications.
  def notifications(action)
    begin
      @driver.open_notifications()
      return
    rescue => e
      exception = e
    end
    path = take_error_screenshot()
    raise "\n#{@role}: Could not open notifications' bar: #{exception}\nError Screenshot: #{path}"
  end

  # Does the action "back" as it would happen in a mobile device
  def back(action)
    begin
      @driver.back()
      return
    rescue => e
      exception = e
    end
    path = take_error_screenshot()
    raise "\n#{@role}: Could not go back: #{exception}\nError Screenshot: #{path}"
  end

  # Presses the home button (Android only)
  def home_button(action)
    raise "\n#{@role}: Home button is only defined for Android!" if @platform != "Android"
    Android.home_button(nil, @udid)
  end

  # Prints and Writes timestamp with given format
  def get_timestamp(action)
    format_t = convert_value(action["Format"])
    time = Time.now.utc.strftime(format_t)
    log_info("Timestamp is: #{time}")
    if action["File"]
      file = File.open(convert_value(action["File"]), "w")
      file.write(time)
      file.close
    elsif action["Var"]
      ENV[convert_value(action["Var"])] = time
    end
  end
  
  # Prints and Writes local timestamp with given format
  # Format
  # Var
  # File
  def get_local_timestamp(action)
    format_t = convert_value(action["Format"])
    time = Time.now.getlocal.strftime(format_t)
    log_info("Timestamp is: #{time}")
    if action["File"]
      file = File.open(convert_value(action["File"]), "w")
      file.write(time)
      file.close
    elsif action["Var"]
      ENV[convert_value(action["Var"])] = time
    end
  end

  # Prints and Writes yesterday's date with given format
  # Format
  # Var
  # File
  def get_yesterday_date(action)
    format_t = convert_value(action["Format"])
    time = Date.today.prev_day.strftime(format_t)
    log_info("Yesterday's date is: #{time}")
    if action["File"]
      file = File.open(convert_value(action["File"]), "w")
      file.write(time)
      file.close
    elsif action["Var"]
      ENV[convert_value(action["Var"])] = time
    end
  end

  # Prints and Writes tomorrow's date with given format
  # Format
  # Var
  # File
  def get_tomorrow_date(action)
    format_t = convert_value(action["Format"])
    time = (Date.today + 1).strftime(format_t)
    log_info("Tomorrow's date is: #{time}")
    if action["File"]
      file = File.open(convert_value(action["File"]), "w")
      file.write(time)
      file.close
    elsif action["Var"]
      ENV[convert_value(action["Var"])] = time
    end
  end

  # returns now time -5 minutes
  # Format
  # Var
  # File
   def get_past_timestamp(action)
    format_t = convert_value(action["Format"])
    time = (Time.now.getlocal - 5*60).strftime(format_t)
    log_info("Timestamp - 5 minute is: #{time}")
    if action["File"]
      file = File.open(convert_value(action["File"]), "w")
      file.write(time)
      file.close
    elsif action["Var"]
      ENV[convert_value(action["Var"])] = time
    end
  end

  # returns now time + # minutes
  # Format
  # Mintes
  # Var
  # File
   def get_timestamp_plus_minutes(action)
    format_t = convert_value(action["Format"])
    user_minutes = convert_value(action["Minutes"])
    time = (Time.now.getlocal + user_minutes.to_i*60).strftime(format_t)
    log_info("Timestamp + #{user_minutes} minute is: #{time}")
    if action["File"]
      file = File.open(convert_value(action["File"]), "w")
      file.write(time)
      file.close
    elsif action["Var"]
      ENV[convert_value(action["Var"])] = time
    end
  end

  def set_env_var(action)
    log_info("Assigned value: \"#{convert_value(action["Value"])}\" to Var: \"#{convert_value(action["Var"])}\"")
    ENV[convert_value(action["Var"])] = convert_value(action["Value"])
  end

  # from cases available as 'sleep'.
  def pause(time)
    sleep(convert_value(time).to_f)
  end

  # Private method to check conditions from wait_for method
  def check_condition(action)
    action["Condition"].each do |condition|
      if condition["Operation"].downcase == "visible"
        action["Time"] = condition["Value"]
        action["Value"] = condition["Result"]

        unless visible(action)
          return assert_condition(action, condition)
        end
      elsif condition["Operation"].downcase == "visible_for"
        action["Time"] = condition["Value"]
        action["Value"] = condition["Result"]

        unless visible_for_not_raise(action)
          return assert_condition(action, condition)
        end
      elsif condition["Operation"].downcase == "eq"
        unless convert_value(condition["Value"]) == convert_value(condition["Result"])
          return assert_condition(action, condition)
        end
      elsif condition["Operation"].downcase == "ne"
        if convert_value(condition["Value"]) == convert_value(condition["Result"])
          return assert_condition(action, condition)
        end
      elsif condition["Operation"].downcase == "att" # Attribute Equal
        unless wait_for(action).attribute(convert_value(condition["Value"])) == convert_value(condition["Result"])
          return assert_condition(action, condition)
        end
      elsif condition["Operation"].downcase == "natt" # Attribute not Equal
        if wait_for(action).attribute(convert_value(condition["Value"])) == convert_value(condition["Result"])
          return assert_condition(action, condition)
        end
      end
    end
    log_info("#{@role}: Info: All conditions met")
    return true
  end

  # Private method to check conditions from check_condition method
  def assert_condition(action, condition)
    operation = condition["Operation"].downcase
    if condition["Raise"]
      path = take_error_screenshot()
      raise "#{@role}: Info: condition '#{operation}' for element " +
      "'#{action["Strategy"]}:#{action["Id"]}', with 'Value: " +
      "#{convert_value(condition["Value"])}' and expected " +
      "'Result: #{convert_value(condition["Result"])}' " +
      "wasn't fullfiled\nError Screenshot: #{path}"
    else
      log_info "#{@role}: Info: condition '#{operation}' for element " +
      "'#{action["Strategy"]}:#{action["Id"]}', with Value: " +
      "#{convert_value(condition["Value"])} and expected " +
      "result: #{convert_value(condition["Result"])} " +
      "wasn't fullfiled"
    end

    return false
  end


  private :check_condition
  private :assert_condition

  # continuously check the state of the call for the specified time
  # (connected, connecting, dropped, etc)
  # used in transport performance tests
  def state_checker(action)
    strategy, idlist, message, app = action["Strategy"], action["Id"], action["Message"], action["App"]
    default_wait_time = (action["Time"] ? action["Time"] : @timeout)
    $network_state = 0
    
    filename = File.join(convert_value(action["Path"]), "network_states.csv")
    seen_list = []
    file = File.open(filename, "w")
    file.write("Time,Call state,Network state\n")
    start = Time.now
    while (Time.now - start) < convert_value(default_wait_time).to_i
      idlist.each_with_index do |id_a, index|
        id = convert_value(id_a)
        begin
          el = @driver.find_element(strategy[index], id)
          unless seen_list.include? message[index]
            seen_list.append(message[index])
          end
        rescue => e
          if seen_list.include? message[index]
            seen_list.delete(message[index])
          end
          exception = e
        end
      end
      file.write("#{(Time.now - start).round(2)},")
      message.each_with_index do |msg, index|
        if seen_list.last == msg
          file.write("#{index}")
          break
        end
      end
      file.write(",#{$network_state}\n")
    end
    file.close

    #Write the names of the states in network_states.csv
    filename_definitions = File.join(convert_value(action["Path"]), "network_states_definitions.txt")
    file = File.open(filename_definitions, "w")
    message.each_with_index do |mes, index|
      file.write("#{index} #{convert_value(mes).to_s} \n")
    end
    file.close

    # Calculates the time it takes for UI element to appear and disappear after network changes
    file = File.open(filename, "r")
    csv = CSV.read(file, headers: true)
    file.close()

    begin
      first_time = csv.find { |row| row["Call state"] == '2' }
      first_time = first_time["Time"]
      rows_with_loading = csv.select {|row| row["Call state"] == '2'}
      last = rows_with_loading.last
      last_time = last["Time"]
        
      net_down = csv.find { |row| row["Network state"] == '1' }
      net_down = net_down["Time"]
      prew = nil
      reset_network = nil
      csv.each_with_index do |row, i|
        if i != 0
          if row["Network state"] == '0' && prew == '1'
            reset_network = row["Time"]
            break
          end
        end
        prew = row["Network state"]
      end

      lost_connection_time = first_time.to_f - net_down.to_f
      reconnection_time = last_time.to_f - reset_network.to_f

      timeText = "#{lost_connection_time.round(2)}\n#{reconnection_time.round(2)}"
      timeName = File.join(convert_value(action["Path"]), "state_reaction_time.txt")
      time = File.open(timeName, "w") {|f| f.write(timeText) }
    rescue => e
      log_warn(e)
      timeText = "0"
      timeName = File.join(convert_value(action["Path"]), "state_reaction_time.txt")
      time = File.open(timeName, "w") {|f| f.write(timeText) }
    end
  end

  # common method for taking screenshot on error
  # should not be called from test file - use screenshot() instead
  def take_error_screenshot()
    return if "command" == @application
    if ENV.has_key?('folderPath')
      folder = File.join(Dir.pwd, convert_value(ENV['folderPath']))
    elsif ENV.has_key?('LOCAL_PATH')
      folder = File.join(Dir.pwd, convert_value(ENV['LOCAL_PATH']))
    else
      folder = File.join(Dir.pwd, "Reports", "screenshots")
    end
    path = File.join(folder, "screenshot_#{@role}.png")
  
    begin
      FileUtils.mkdir_p(folder) unless Dir.exist? folder
      if @udid
        @driver.screenshot(path)
      else
        screenshot_file = @driver.screenshot_as(:base64)
        File.open(path, "wb") { |f| f.write(Base64.decode64(screenshot_file)) }
      end
      return path
    rescue => e
      log_warn("Could not take screenshot due to error: #{e.message}")
      sleep(0.1)
      return "Could not take screenshot due to error: #{e.message}"
    end
  end  


  # Reload driver
  # Accepts:
  #   Asserts
  #     WindowNumber
  #     WindowTitle
  #     Application
  def reload_driver(action)
    stop_driver()
    build_driver()
    start_driver()
  end

  # Reload driver with a new window handle
  # Accepts:
  #   Asserts
  #     WindowNumber
  #     WindowTitle
  #     Application
  def reload_driver_with_new_window_handle(action)
    if @platform != 'Windows'
      log_warn('Tried to execute this on ', @platform, 'when this is supposed to only work on windows')
      return
    end

    # NEW WINDOW HANDLE
    window_number = -1 # Set  default Window number 
    window_number = convert_value(action['WindowNumber']).to_i if action['WindowNumber'] # Override window number if specified
    time = 30 # Set default timeout value
    time = convert_value(action['Time']) if action['Time'] # Override timeout if specified
    window_handle = 0
    if action['WindowTitle']
      window_handle = get_window_handle(convert_value(action['WindowTitle']), 'title', window_number, time)
    elsif action['Application']
      window_handle = get_window_handle(convert_value(action['Application']), 'app', window_number, time)
    else
      log_warn('No WindowTitle or Application specified for reload_driver_with_new_window_handle call')
      return
    end
    driverclass = AppiumDriver.new(@device_name, @driver_port, @udid, @app_details, @url)
    base_caps = driverclass.build_windows_caps()
    base_caps['appTopLevelWindow'] = window_handle.to_s(16)
    # STOPING PREVIOUS DRIVER
    stop_driver()
    # START DRIVER WITH CUSTOM WINDOW
    full_caps = driverclass.merge_full_caps(base_caps, @config_caps, @case_caps)
    puts('New capabilities are: ', full_caps)
    @driver = driverclass.build_appium_driver(full_caps, @url)
    start_driver()
  end

  # call the specified assertion method
  # Accepts:
  #   Asserts
  #     Type
  #     Var
  #     Value
  def assert(action)
    raise "#{@role}: Assert action requires an 'Asserts' section!" unless action.key?("Asserts")
    action["Asserts"].each do |assert|
      raise "#{@role}: 'Asserts' section requires attributes 'Type', 'Var', " +
            "'Value'!" if assert.values_at("Type", "Var", "Value").include?(nil)
      src_var = ENV[convert_value(assert["Var"])]
      cmp_var = assert["Value"].is_a?(Numeric) ? assert["Value"] : convert_value(assert["Value"])
      op = assert["Type"].downcase
      
      if ["contain_encode_utf8"].include?(op)
        src_not_frozen_var = src_var.dup.force_encoding("ASCII-8BIT")
        utf8_string = src_not_frozen_var.encode("UTF-8", "ASCII-8BIT", invalid: :replace, undef: :replace, replace: "")
      end

      # check for class mismatches
      if ["contain", "n_contain", "contain_encode_utf8"].include?(op)
        raise "#{@role}: Value '#{cmp_var}' should be a String!" unless cmp_var.is_a?(String)
      elsif ["eq", "ne"].include?(op)
        if cmp_var.is_a?(Numeric)
          src_var = src_var.to_i if src_var.to_i.to_s == src_var
          src_var = src_var.to_f if src_var.to_f.to_s == src_var
          unless src_var.is_a?(Numeric)
            raise "#{@role}: Variables have mismatching types!\n" + 
                  "#{src_var} is #{src_var.class}, but #{cmp_var} is #{cmp_var.class}!"
          end
        end
      elsif ["lt", "gt", "le", "ge"].include?(op)
        raise "#{@role}: Value '#{cmp_var}' should be a Numeric!" unless cmp_var.is_a?(Numeric)
        src_var = src_var.to_i if src_var.to_i.to_s == src_var
        src_var = src_var.to_f if src_var.to_f.to_s == src_var
        raise "#{@role}: Var '#{src_var}' should be a Numeric!" unless src_var.is_a?(Numeric)
      else
        raise "#{@role}: Unknown assertion type '#{op}'!"
      end
    
      # do the actual operation
      on_fail_text = ""
      case op
      when "contain"
        on_fail_text = "contain" unless src_var.include?(cmp_var)
      # Custom option made to handle those non UTF-8 characters that Never Alone returns.
      when "contain_encode_utf8"
        on_fail_text = "contain" unless utf8_string.include?(cmp_var)
      when "n_contain"
        on_fail_text = "NOT contain" unless !src_var.include?(cmp_var)
      when "eq"
        on_fail_text = "be equal to" unless src_var == cmp_var
      when "ne"
        on_fail_text = "NOT be equal to" unless src_var != cmp_var
      when "lt"
        on_fail_text = "be less than" unless src_var < cmp_var
      when "gt"
        on_fail_text = "be greater than" unless src_var > cmp_var
      when "le"
        on_fail_text = "be less or equal to" unless src_var <= cmp_var
      when "ge"
        on_fail_text = "be greater or equal to" unless src_var >= cmp_var
      end
    
      unless on_fail_text.empty?
        path = take_error_screenshot unless "command" == @application
        screenshot_error = (path ? "\nError Screenshot: #{path}" : "")
        raise "#{@role}: The Var was '#{src_var}', but it was expected " + 
              "to #{on_fail_text} '#{cmp_var}'#{screenshot_error}"
      end 
      if ["contain_encode_utf8"].include?(op)
        log_info "#{@role}: Succesful Assert -> '#{utf8_string}' - #{assert["Type"]} - '#{cmp_var}'"
      else
        log_info "#{@role}: Succesful Assert -> '#{src_var}' - #{assert["Type"]} - '#{cmp_var}'"
      end
    end
  end 

  # call the specified operation method
  # Accepts:
  #  Operation
  #  ExpectedResult
  #  ResultVar
  def operation(action)
    calculator = Keisan::Calculator.new
    operation_val = convert_value(action["Operation"])
    result = nil
    begin
      result = calculator.evaluate(operation_val)
    rescue => e
      path = take_error_screenshot unless "command" == @application
      screenshot_error = (path ? "\nError Screenshot: #{path}" : "")
      raise "The operation was NOT valid: #{e.message}.#{screenshot_error}"
    end
    log_info "Result from the operation '#{operation_val}' = '#{result}'"
    unless action["ExpectedResult"].nil?
      exp_result = convert_value(action["ExpectedResult"])
      if (result.is_a?(Numeric) && exp_result.to_f != result) || 
      (result.is_a?(String) && exp_result != result) || 
      (!!result == result && result.to_s != exp_result.downcase)
        path = take_error_screenshot unless "command" == @application
        screenshot_error = (path ? "\nError Screenshot: #{path}" : "")
        raise "#{@role}: The Result was '#{result}', but it was expected " + 
        "to be '#{exp_result}'.#{screenshot_error}"
      else
        log_info "Successful validation of the operation '#{operation_val}' = '#{exp_result}'"
      end
    end
    ENV[convert_value(action["ResultVar"])] = result.to_s if action["ResultVar"]
  end 
end

# returns the attribute of the element in a variable
def return_element_attribute(action)
  el = wait_for(action)
  return unless el

  attr_value = el.attribute(action["Attribute"])
  
  if action["NoNewLine"]
    no_newline_el_string = attr_value.to_s.gsub("\n", " ")
    log_info("Element attribute is  #{no_newline_el_string}")
    ENV[convert_value(action["ResultVar"])] = no_newline_el_string
  else
    log_info("Element attribute is " + attr_value.to_s)
    ENV[convert_value(action["ResultVar"])] = attr_value.to_s
  end

end

# day_month is use to select a random day inside of it
$days_month = ["1", "2", "3", "4", "5","6","7","8","9","10","11","12","13","14","15","16","17","18","19","20","21","22","23","24",
"24","25","26","27","28","29","30"]

# Recieve a timestamp and return the related day
def get_day(action)
  timestamp_string = convert_value(action["Timestamp"])
  timestamp = timestamp_string.to_i
  time = Time.at(timestamp/1000)
  position_found_day = $days_month.index(time.day.to_s)
  if position_found_day.nil?
    ENV[convert_value(action["ResultVar"])] = format('%02d',time.day) 
  else
    found_day = $days_month[position_found_day]
    $days_month.delete(found_day)
    ENV[convert_value(action["ResultVar"])] = format('%02d',found_day) 
  end
end

# Return the following month of the current date
def get_next_month(action)
  current_date = Time.now
  next_month = current_date.month + 1
  ENV[convert_value(action["ResultVar"])] = format('%02d',next_month)
end

#Obtain a random day difference to inserted day (InsertedDay could be undefined) 
#and day = 31 is not included
def generate_random_day(action)
  inserted_day = convert_value(action["InsertedDay"])
  if inserted_day.nil?
    unique_number = format('%02d', rand(0..($days_month.length-1))).to_i
    day = $days_month[unique_number]
    $days_month.delete(day)
    ENV[convert_value(action["ResultVar"])] = day
  else
  $days_month.delete(inserted_day)
  unique_number = format('%02d', rand(0..($days_month.length-1))).to_i
  day = $days_month[unique_number]
  ENV[convert_value(action["ResultVar"])] = day
  end
end

# Returns a variable with a unique name using timestamps at the end
# i.e. method receives "Hey" and then returns "Hey <timestamp>"
def generate_unique_name(action)
  name = convert_value(action["Name"])
  unique_name = "#{name} #{Time.now.utc.strftime("%d%m%y%H%M%S")}"
  ENV[convert_value(action["ResultVar"])] = unique_name
end

# Custom method to calculate the minutes/seconds from when an event was created
# i.e. returns "Added x minutes ago" or "Added x seconds ago"
def calculate_minutes_passed_by_from_event_creation(action)
  timestamp = Time.parse(convert_value(action["Timestamp"]))
  now = Time.now.getlocal
  diff = now - timestamp
  
  if diff < 60
    seconds_passed = diff.truncate()
    ENV[convert_value(action["ResultVar"])] = "Added #{seconds_passed} seconds ago"
  else
    minutes_passed = (diff/60).truncate()
    if minutes_passed == 1
      ENV[convert_value(action["ResultVar"])] = "Added #{minutes_passed} minute ago"
    else
      ENV[convert_value(action["ResultVar"])] = "Added #{minutes_passed} minutes ago"
    end
  end
  
end

# Custom method to verify that an event on Never Alone went to the bottom after its time has passed.
def verify_event_went_to_bottom(action)
  action = convert_value_pageobjects(action);
  event_name = convert_value(action["EventName"])

  if event_name.nil? || event_name.empty?
    raise "EventName cannot be null."
  end

  events = @driver.find_elements(convert_value(action["Strategy"]), convert_value(action["Id"]))

  if events.nil? || events.empty?
    raise "Event elements collection cannot be null."
  end

  event_labels = []
  events.each do |event|
    attr_value = event.attribute("label")
    log_info("Found element label: #{attr_value}")
    event_labels.push(attr_value)
  end

  if event_labels.last().include? event_name
    log_info("#{event_name} was at the bottom of the Schedules!")
  else
    raise "#{event_name} was not at the bottom of the Schedules!"
  end

end

# Custom method to verify that all events are matching today's date.
def verify_all_events_match_todays_date(action)
  action = convert_value_pageobjects(action);

  events = @driver.find_elements(convert_value(action["Strategy"]), convert_value(action["Id"]))

  if events.nil? || events.empty?
    raise "Event elements collection cannot be null."
  end

  today_date = Date.today
  events.each do |event|
    event.click
    wait = Selenium::WebDriver::Wait.new(:timeout => 5)
    date_label = wait.until {@driver.find_element(convert_value(action["SecondStrategy"]), convert_value_pageobjects(action["SecondId"]))}
    event_date = Date.parse(date_label.attribute("label"))
    close_button = @driver.find_element(:class_chain, "**/XCUIElementTypeButton[`label CONTAINS 'Close'`]")
    close_button.click

    if today_date == event_date
      log_info("An event has been validated to be for today!")
    else
      raise "Event is not for today's date, today's date: #{today_date}, event's date: #{event_date}"
    end

  end

end

# Custom internal method to wait for an element to be enabled
def wait_for_enabled_element(locator)
  begin
    wait = Selenium::WebDriver::Wait.new(:timeout => 5)
    element = wait.until {@driver.find_element(:xpath, convert_value_pageobjects(locator))}
    wait.until {element.enabled?}
    return element
  rescue Exception => e
    log_info("Exception: #{e}")
    return false
  end
end

# Custom internal method to wait for an element to exist
def wait_for_element_to_exist(locator)
  begin
    wait = Selenium::WebDriver::Wait.new(:timeout => 5)
    element = wait.until {@driver.find_element(:xpath, convert_value_pageobjects(locator))}
    return element
  rescue Exception => e
    log_info("Exception: #{e}")
    return false
  end
end

# Custom internal method to wait for element to dissapear
def wait_for_element_not_visible(locator)
  begin
    wait = Selenium::WebDriver::Wait.new(:timeout => 5)
    wait.until { !@driver.find_element(:xpath, convert_value_pageobjects(locator)).visible? }
  rescue Selenium::WebDriver::Error::TimeoutError
    log_info("Exception: Element still visible")
  end
end

# Custom internal method to wait for an element collection to exist
def wait_for_element_collection_to_exist(locator)
  begin
    wait = Selenium::WebDriver::Wait.new(:timeout => 5)
    elements = wait.until {@driver.find_elements(:xpath, convert_value_pageobjects(locator))}
    return elements
  rescue Exception => e
    log_info("Exception: #{e}")
    return false
  end
end

# Custome action to clean hanged calls and sessions
def provider_clean_hanged_call_or_session(action)
  have_call = false
  if wait_for_element_to_exist("$PAGE.providers_home_page.session_return_button$")
    log_info("There's a return session")
    @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.providers_home_page.session_return_button$")).click
    have_call = true
  end
  if wait_for_element_to_exist("$PAGE.providers_call_handling_page.end_call_btn$")
    log_info("there's an end call button")
    wait_for_enabled_element("$PAGE.providers_call_handling_page.end_call_btn$")
    @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.providers_call_handling_page.end_call_btn$")).click
    have_call = true
  end
  if wait_for_enabled_element("$PAGE.providers_call_handling_page.complete_session_button$")
    log_info("there's a complete session button")
    wait_for_enabled_element("$PAGE.providers_call_handling_page.complete_session_button$")
    @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.providers_call_handling_page.complete_session_button$")).click
    have_call = true
  end
  if wait_for_element_to_exist("$PAGE.providers_call_handling_page.post_call_survey_title$")
    log_info("We are at the provider's survey")
    have_call = true
  end
  if have_call
    @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.providers_call_handling_page.resolved_true_option$")).click
    wait_for_enabled_element("$PAGE.providers_call_handling_page.recommend_discharge_yes_by_SNF$")
    @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.providers_call_handling_page.recommend_discharge_yes_by_SNF$")).click
    wait_for_enabled_element("$PAGE.providers_call_handling_page.call_notes_subject_input$")
    @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.providers_call_handling_page.call_notes_subject_input$")).send_keys("Automation Test subject")
    wait_for_enabled_element("$PAGE.providers_call_handling_page.call_notes_provider_input$")
    @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.providers_call_handling_page.call_notes_provider_input$")).send_keys("Automation Test Notes: Ended by provider's cleaner")
    wait_for_enabled_element("$PAGE.providers_call_handling_page.submit_exit_session_button$")
    @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.providers_call_handling_page.submit_exit_session_button$")).click
    
    wait_for_element_not_visible("$PAGE.providers_call_handling_page.submit_exit_session_button$")
    @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.providers_home_page.home_button$")).click
    wait_for_enabled_element("$PAGE.providers_home_page.home_title$")
  end
end

# Custom action to clean calls from queue and hanged calls on the care partner site
def care_partner_clean_call_queue_and_hanged_calls(action)
  
  log_info("checking if there is any hanged call")
  if wait_for_element_to_exist("$PAGE.care_platform_home.active_call_section$")
    
    log_info("open the show video if it is hidden")
    if wait_for_enabled_element("$PAGE.care_platform_floating_video_call.video_show_button$")
      @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_floating_video_call.video_show_button$")).click
    end
    
    log_info("hover over the video fixed content to pull up the video return button")
    wait_for_element_to_exist("$PAGE.care_platform_floating_video_call.video_fixed_content$")
    @driver.action.move_to(wait_for_element_to_exist("$PAGE.care_platform_floating_video_call.video_fixed_content$")).perform

    log_info("navigate to the call queue")
    @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_floating_video_call.video_return_button$")).click
    
    log_info("verify it was redirected to the call queue, if call is running, click on hang call")
    if wait_for_element_to_exist("$PAGE.care_platform_call_portal.end_call_button$")
      log_info("a call on course was found, click on the end call button")
      wait_for_enabled_element("$PAGE.care_platform_call_portal.end_call_button$")
      @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_call_portal.end_call_button$")).click
    end
    
    log_info("Click on the No Message button if it appears")
    if wait_for_element_to_exist("$PAGE.care_platform_call_portal.no_message_button$")
      @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_call_portal.no_message_button$")).click
      @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform.navigation_home$")).click
      wait_for_enabled_element("$PAGE.care_platform.call_queue_title$")
      return
    end

    log_info("complete the session")
    wait_for_enabled_element("$PAGE.care_platform_call_portal.video_status$")
    
    log_info("fill in Subject and Details field")
    wait_for_enabled_element("$PAGE.providers_call_handling_page.subject_input$")
    @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.providers_call_handling_page.subject_input$")).send_keys("Automation Tear Down")
    @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.providers_call_handling_page.details_textarea$")).send_keys("Automation Tear Down Details")
    
    log_info("wait for the Complete Sesion button to be enabled and click on it")
    wait_for_enabled_element("$PAGE.care_platform_call_portal.complete_session_btn$")
    @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_call_portal.complete_session_btn$")).click
    
    log_info("wait for the post-call survey options")
    wait_for_enabled_element("$PAGE.care_platform_call_portal.non_medical_radiobtn$")
    
    log_info("select the non medical radio button")
    @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_call_portal.non_medical_radiobtn$")).click
    
    log_info("select the issue resolved radio button")
    @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_call_portal.issue_resolved_yes_radiobutton$")).click
    
    log_info("select the Accidental call category")
    @driver.find_element(:id, convert_value_pageobjects("$PAGE.care_platform_call_portal.category_select$")).click
    wait_for_enabled_element("$PAGE.care_platform_call_portal.accidental_call_option$")
    @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_call_portal.accidental_call_option$")).click
    
    log_info("Submit and Exit session")
    @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_call_portal.submit_and_exit_session_button$")).click
    wait_for_enabled_element("$PAGE.care_platform.call_queue_title$")
  end
  
  log_info("checking if there is any pending call on the call queue page")
  call_queue_call_elements = wait_for_element_collection_to_exist("$PAGE.care_platform_home.call_queue_calls$")
  if call_queue_call_elements.nil? || call_queue_call_elements.empty?
    puts "Call queue call elements collection is null/empty."
  end
  
  if call_queue_call_elements.length() > 0
    call_queue_call_elements.each do |call_element|
      
      log_info("wait for call queue element")
      wait_for_enabled_element("$PAGE.care_platform_home.first_call_of_queue$")
      @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_home.first_call_of_queue$")).click
      log_info("answer call")
      wait_for_element_to_exist("$PAGE.care_platform_home.answer_call$")
      @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_home.answer_call$")).click
      
      if wait_for_element_to_exist("$PAGE.care_platform_notifications.failed_to_join_call_notification$") || wait_for_element_to_exist("$PAGE.care_platform_notifications.call_already_answered_notification$")
        log_info("Failed to join call/Call already answered notification appeared")
        @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform.navigation_home$")).click
        @driver.navigate.refresh
        wait_for_enabled_element("$PAGE.care_platform.call_queue_title$")
      else
        log_info("wait for the end call button")
        wait_for_element_to_exist("$PAGE.care_platform_call_portal.end_call_button$")
        
        log_info("click on the end call")
        @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_call_portal.end_call_button$")).click

        log_info("Click on the No Message button if it appears")
        if wait_for_element_to_exist("$PAGE.care_platform_call_portal.no_message_button$")
          @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_call_portal.no_message_button$")).click
          @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform.navigation_home$")).click
          wait_for_enabled_element("$PAGE.care_platform.call_queue_title$")
          next
        end

        log_info("fill in the details to complete the session, complete the session")
        wait_for_element_to_exist("$PAGE.care_platform_call_portal.video_status$")
        
        log_info("fill in Subject and Details field")
        wait_for_enabled_element("$PAGE.providers_call_handling_page.subject_input$")
        @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.providers_call_handling_page.subject_input$")).send_keys("Automation Tear Down")
        @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.providers_call_handling_page.details_textarea$")).send_keys("Automation Tear Down Details")
        
        log_info("wait for the Complete Sesion button to be enabled and click on it")
        wait_for_enabled_element("$PAGE.care_platform_call_portal.complete_session_btn$")
        @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_call_portal.complete_session_btn$")).click
        
        log_info("wait for the post-call survey options")
        wait_for_element_to_exist("$PAGE.care_platform_call_portal.non_medical_radiobtn$")
        
        log_info("select the non medical radio button")
        @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_call_portal.non_medical_radiobtn$")).click
        
        log_info("select the issue resolved radio button")
        @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_call_portal.issue_resolved_yes_radiobutton$")).click
        
        log_info("select the Accidental call category")
        @driver.find_element(:id, convert_value_pageobjects("$PAGE.care_platform_call_portal.category_select$")).click
        wait_for_element_to_exist("$PAGE.care_platform_call_portal.accidental_call_option$")
        @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_call_portal.accidental_call_option$")).click
        
        log_info("Submit and Exit session")
        @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform_call_portal.submit_and_exit_session_button$")).click
        @driver.find_element(:xpath, convert_value_pageobjects("$PAGE.care_platform.navigation_home$")).click
        wait_for_enabled_element("$PAGE.care_platform.call_queue_title$")
      end
    end
  end
end

# Custom action to wait for a mobile element to exist
def wait_for_mobile_element_to_exist(locator)
  begin
    wait = Selenium::WebDriver::Wait.new(:timeout => @timeout)
    # element = wait.until {@driver.find_element(:class_chain, convert_value_pageobjects(locator))}
    element = wait.until {@driver.find_element(:class_chain, locator)}
    return element
  # rescue Selenium::WebDriver::Error::NoSuchElementError
  rescue Exception => e
    # puts "Element not found"
    # return nil
    log_info("Exception: #{e}")
    return false
  end
end

# Custom action to wait for a mobile element to disappear
def wait_for_mobile_element_to_disappear(locator)
  element_exists = wait_for_mobile_element_to_exist(locator)
  unless element_exists
    return true
  end
end

# Custom action to clean all the unwanted prompts on Never Alone app before starting test.
def senior_clean_unwanted_prompts(action)
  count = 0
  loop do
    log_info("check if there is an existing prompt")

    if wait_for_mobile_element_to_disappear("**/XCUIElementTypeButton[`label CONTAINS 'Close'`]") && count <=30
      log_info("no prompts on the app")
      break
    end
    
    if wait_for_mobile_element_to_exist("**/XCUIElementTypeButton[`label CONTAINS 'Close'`]")
      log_info("close the unwanted prompt")
      prompt = wait_for_mobile_element_to_exist("**/XCUIElementTypeButton[`label CONTAINS 'Close'`]")
      if prompt
        prompt.click
      end
    end
    sleep 3
    
    if count >= 30
      log_info("there is too many prompts")
      break
    end
    count += 1
  end
end
# END OF DEVICE CLASS
