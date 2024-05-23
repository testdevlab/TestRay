# Class used for handling all test devices used during any one test.
# Includes their creation and interactions during the test
class DeviceHandler
  attr_reader :devices

  def initialize(case_role_sets)
    @timeout = $config["Timeout"] ? $config["Timeout"] : 10
    @server_port = 4727
    @driver_port = 8205
    @devices = {}
    create_devices(case_role_sets)
  end

  # Iterate through all required roles and create Device class instances for each
  def create_devices(case_role_sets)
    local_androids, local_iphones = {}, {}
    log_info("Starting creation and configuration of role handlers...")
    case_role_sets.each do |case_role_set|
      # check for additional capabilities under roleset
      case_caps = {}
      if case_role_set.key?("Capabilities") && !case_role_set["Capabilities"].nil?
        case_caps = convert_yaml(case_role_set["Capabilities"])
      end

      # iterate through individual roles in roleset
      roles_in_roleset = convert_value(case_role_set["Role"]).split(",")
      roles_in_roleset.each do |case_role|
        device, is_local = create_single_device(case_role, case_role_set["App"], case_caps)
        case is_local
        when "Android" 
          local_androids[case_role] = device
        when "iOS"
          local_iphones[case_role]  = device
        else
          @devices[case_role]       = device
        end
        @server_port += 2
        @driver_port += 2
      end
    end

    # assign any requested local Android/iOS devices to physical ones
    assign_local_devices(local_androids, Android.detect_devices) unless local_androids.empty?
    assign_local_devices(local_iphones,  Ios.detect_devices)     unless local_iphones.empty?
    log_abort("No role handlers were initialised!") if @devices.empty?
    log_info("All role handlers created and fully configured!")

    # build the full capabilities for each device and launch Appium servers where needed
    @devices.values.each { |device| device.build_driver }
  end

  # Create Device class instance for an individual case role
  def create_single_device(case_role, role_app, case_caps)
    log_debug("Creating handler for case role '#{case_role}'...")

    # Find matching device role in config file
    # guaranteed to exist due to previous check_case_roles_apps call
    config_device = {}
    $config["Devices"].each do |d|
      d["role"].split(",").each do |r|
        if r == case_role
          config_device = d
          break
        end
      end
    end

    # assemble app details for role
    # cannot be done for entire roleset due to browser being per-role
    role_app = convert_value(role_app)
    app_details = {"Application" => role_app}
    if !["browser", "command", "desktop"].include?(role_app)
      app_details = app_details.merge($config["Apps"][role_app])
    elsif ["browser", "desktop"].include?(role_app)
      app_details["Browser"] = config_device["browser"]
    end

    # Get some physical device parameters (remote or local, udid, etc.)
    url, udid, options = setup_path_to_device(config_device)

    # Get capabilities from config and case, and replace existing udid if it is provided
    @server_port = convert_value(config_device["serverPort"]).to_i if config_device.key?("serverPort")
    config_caps = {}
    if config_device.key?("capabilities") && !config_device["capabilities"].nil?
      config_caps = convert_yaml(config_device["capabilities"])
      log_info("Role '#{case_role}': Adding capabilities from config: #{config_caps}")
      udid = config_caps["udid"] if config_caps.key?("udid")
      @driver_port = config_caps["systemPort"].to_i if config_caps.key?("systemPort")
      @driver_port = config_caps["wdaLocalPort"].to_i if config_caps.key?("wdaLocalPort")
    end
    if !case_caps.empty?
      log_info("Role '#{case_role}': Adding capabilities from case: #{case_caps}")
      udid = case_caps["udid"] if case_caps.key?("udid")
      @driver_port = case_caps["systemPort"].to_i if case_caps.key?("systemPort")
      @driver_port = case_caps["wdaLocalPort"].to_i if case_caps.key?("wdaLocalPort")
    end

    # Create virtual device for the role
    network_details = [@server_port, url, @driver_port]
    device = Device.new(
      role: case_role,
      platform: config_device["platform"],
      udid: udid,
      network_details: network_details,
      app_details: app_details,
      timeout: @timeout,
      config_caps: config_caps,
      case_caps: case_caps,
      options: options
    )

    log_debug("Created handler for case role '#{case_role}'")
    
    # separate local Android/iOS devices since they may or may not be pre-determined
    return device, config_device["platform"] if options.key?("localPhone")
    return device, nil
  end

  # Assign local Android/iOS Device class instances to physical devices
  def assign_local_devices(virtual_devices, phones)
    if virtual_devices.length > phones.length
      log_abort("Not enough locally connected devices!\n" +
                "Requested roles: #{virtual_devices.keys}\n" +
                "Available devices: #{phones}")
    end
    virtual_devices_dup = virtual_devices.dup
    # first identify and remove devices with already specified udid
    virtual_devices.each do |role, device|
      next if device.udid.nil?
      found_index = nil
      phones.each_with_index do |phone, index|
        next unless phone[1] == device.udid
        found_index = index
        break
      end
      log_abort("Role '#{role}': Could not reserve local device with udid " +
                "'#{device.udid}'! Either it does not exist, or it is already " +
                "assigned to another role!") unless found_index
      device.device_name = phones[found_index][0]
      @devices[role] = device
      log_info("Role '#{role}': Using local device #{phones[found_index]}")
      virtual_devices_dup.delete(role)
      phones.delete_at(found_index)
    end
    # for the remaining roles, assign phones in order
    virtual_devices_dup.each do |role, device|
      phone = phones.shift
      device.device_name = phone[0]
      device.udid        = phone[1]
      @devices[role] = device
      log_info("Role '#{role}': Using local device #{phone}")
    end
  end

  # Launch Appium drivers for all roles using them
  # (roles with Selenium drivers already have the drivers launched)
  def start_drivers
    Android.initialise_appium_commands
    begin
      retries ||= 1
      threads = []
      @devices.each do |role, device|
        threads.append(Thread.new { device.start_driver })
      end
      threads.each do |thread|
        thread.join
      end
    rescue => e
      log_error("Driver start ##{retries} is unsuccessful. Error:")
      log_error("#{e.message}")
      if (retries += 1) < 1
        Android.take_screenshots
        retry
      else
        raise e
      end
    end
  end

  # Stops the Appium/Selenium drivers for all roles
  def stop_drivers
    @devices.each do |role, device|
      begin
        device.stop_driver
      rescue => e
        log_warn("Could not quit driver for #{role}. Error:")
        log_warn("#{e.message}")
      end
    end
  end

  # Starts Appium servers for all roles using them
  def start_servers
    @devices.each do |role, device|
      device.start_server
    end
  end

  # Stops Appium servers for all roles using them
  def stop_servers
    @devices.each do |role, device|
      device.stop_server
    end
  end
end

# Determine the device udid, url and options
# Distinguishes local devices and different types of remote devices
def setup_path_to_device(device)
  udid, url = nil, nil
  options = {}
  if device["url"] && device["browser"].nil?
    android_payload = { "appium" => { "os" => "Android" } }
    android_payload = {
      "appium" => { "os" => "Android", "timeout" => device["timeout"] },
    } if device["timeout"]
    android_payload = { "appium" => { "os" => device["os"] } } if device["os"]
    android_payload["appium"]["groupID"] = device["groupID"] if device["groupID"]
    device_inf = UIGrid.retrieveAndroidDevice(
      device["url"], android_payload, device["role"]
    )
    udid = device_inf["udid"]
    url = device_inf["proxyURL"]
    options["resolution"] = device_inf["resolution"]
    options["screenPercentage"] = device_inf["screenPercentage"]
    log_info("TestUI Grid: retrieved device #{device_inf["udid"]} " +
             "with proxy url: #{url}")
  elsif device["url"] && device["browser"]
    android_payload = { "selenium" => { "browser" => device["browser"] } }
    android_payload = {
      "selenium" => {
        "browser" => device["browser"],
        "timeout" => device["timeout"],
      },
    } if device["timeout"]
    android_payload = {
      "selenium" => { "os" => device["os"], "browser" => device["browser"] },
    } if device["os"]
    android_payload["selenium"]["groupID"] = device["groupID"] if device["groupID"]
    device_inf = UIGrid.retrieveAndroidDevice(
      device["url"], android_payload, device["role"]
    )
    url = device_inf["proxyURL"]

    log_info("TestUI Grid: retrieved browser #{device["browser"]} " +
           "with proxy url: #{device_inf["proxyURL"]}")
  elsif device["seleniumUrl"]
    url = device["seleniumUrl"]
  elsif device["appiumUrl"]
    url = device["appiumUrl"]
    udid = device["udid"]
  elsif device.has_key?('platform')
    if ["Mac", "Windows"].include?(device["platform"])
      udid = device["platform"]
    else # local Android or iOS - udid assigned later
      options["localPhone"] = true
    end
  end

  return url, udid, options
end