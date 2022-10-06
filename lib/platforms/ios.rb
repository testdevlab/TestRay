# Class describing communication with local iOS devices
class Ios
  # Detect locally connected iOS devices, once
  def self.detect_devices_once
    log_debug("Detecting connected iDevices...")
    devices = []
    idevices = `xcrun xctrace list devices 2>&1`
    log_abort "Xcode is not installed or configured!" if idevices.include?("error")
    idevices.split("\n").each do |device|
      next unless device.include?(") (")
      device_list = device.split("(")
      name = device_list[0].strip
      udid = device_list.last().split(")")[0]
      devices.append([name, udid])
    end
    return devices
  end

  # Detect locally connected iOS devices with 3 retries
  def self.detect_devices
    log_abort "iOS device automation is not possible on Windows!" if OS.windows?
    devices = self.detect_devices_once
    if devices.empty?
      retries = 1
      while (retries < 3)
        log_debug("No iOS devices found, retrying...")
        sleep 1
        devices = self.detect_devices_once
        break if !devices.empty?
        retries += 1
      end
      log_abort "Could not find any connected iOS devices!" if retries >= 3
    end
    return devices
  end

  ########################################################
  # NON-TEST METHODS (not called in 'testray execute')
  ########################################################

  # List and return the available target devices and connection types
  def self.list_devices()
    all_devices = self.detect_devices
    usb_udids = `idevice_id -l`.split("\n")
    network_devices = []
    usb_devices = []
    all_udids_conns = {}

    all_devices.each do |device|
      if usb_udids.include?(device[1])
        connection_type = "usb"
        usb_devices.append(device)
      else
        connection_type = "network"
        network_devices.append(device)
      end
      all_udids_conns[device[1]] = connection_type
    end

    log_abort "No iDevices found!" if all_devices.empty?
    output = "Available iDevices: #{prettyprint_devices(all_devices)}"
    output += "\nConnected over USB: #{prettyprint_devices(usb_devices)}" unless usb_devices.empty?
    output += "\nConnected over network: #{prettyprint_devices(network_devices)}" unless network_devices.empty?
    return all_udids_conns, output
  end

  # Returns the installed version of the provided app on target device
  # If app is not present, prints N/A and returns nil
  def self.version(app, udid_conn, printout=false)
    check_for_app_name(app)
    check_app_data_present(app, "iOSBundle")
    bundle = $config["Apps"][app]["iOSBundle"]
    ver = `ideviceinstaller #{loc(udid_conn)} -l | grep #{bundle} | cut -d',' -f 2`
    version = ver.empty? ? "N/A" : ver.strip.tr('\"', '')
    log_debug("#{app} installed version: #{version}") if printout
    version = nil if version == "N/A"
    return version
  end

  # Uninstalls the provided app from target device
  def self.uninstall(app, udid_conn)
    check_for_app_name(app)
    log_abort "#{app} is not installed!" if self.version(app, udid_conn).nil?
    bundleid = $config["Apps"][app]["iOSBundle"]
    `ideviceinstaller #{loc(udid_conn)} -U #{bundleid}`
    log_debug("Successfully uninstalled #{app}!")
  end

  # Takes a screenshot
  def self.screenshot(app, udid_conn)
    time = Time.now.strftime("%Y%m%d-%H%M%S")
    `idevicescreenshot #{loc(udid_conn)} #{udid_conn[0]}_#{time}.png`
    log_debug("Created screenshot '#{udid_conn[0]}_#{time}.png'")
  end
end

# Sets the iDevice identifier for idevice___ commands, depending on the connection
def loc(udid_conn)
  return udid_conn[1] == "network" ? "-n" : "-u #{udid_conn[0]}"
end
