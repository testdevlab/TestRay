require "appium_lib"
require "base64"
require "csv"
require "fileutils"
require "os"
require "keisan"
require "selenium-webdriver"
require "screen-recorder"
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
        @url = "http://localhost:#{server_port}/wd/hub"
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

  def close_app(action = nil)
    @driver.close_app
  end

  def launch_app(action = nil)
    @driver.launch_app
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

  # tap_by_coord on the provided element but over its coordinates. Multiple location 
  # strategies are accepted - css, xPath, id.
  # Accepts:
  #   Strategy
  #   Id
  #   Condition
  #   CheckTime
  #   NoRaise
  def tap_by_coord(action)
    el = wait_for(action)
    el_location = el.location
    log_info("#{@role}: element coordinates: x -> #{el_location.x}, y -> #{el_location.y}")
    action = Appium::TouchAction.new(@driver).press(x: el_location.x, y: el_location.y).wait(600).release.perform
  end

  # presses on the provided element. Uses Appium's TouchAction.
  # Accepts:
  #   Strategy
  #   Id
  #   Condition
  #   CheckTime
  #   NoRaise
  def press(action)
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
    source = @driver.get_source
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

    # switches to the provided window index.
  # Accepts:
  #   Value
  def switch_frame(action)
    index = action["Value"]
    el = wait_for(action)
    if el
      log_info("#{@role}: Switching to frame element: #{action["Strategy"]}:#{action["Id"]}")
      index = el
    else
      log_info("#{@role}: Switching to frame: #{index}")
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
  #   Value
  def terminate_app(action)
    begin
      @driver.terminate_app action["Value"]
    rescue => e
    end
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
  def collection_visible_for(collection)
    time = (action["Time"] ? action["Time"] : @timeout)
    start = Time.now
    while (Time.now - start) < time
      collection.each do |element|
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
    
      # check for class mismatches
      if ["contain", "n_contain"].include?(op)
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
      log_info "#{@role}: Succesful Assert -> '#{src_var}' - #{assert["Type"]} - '#{cmp_var}'"
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

# END OF DEVICE CLASS
