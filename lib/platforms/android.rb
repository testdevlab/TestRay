require "httparty"
require "nokogiri"
require "open3"
require "open-uri"
require "os"

# Class describing communication with local Android devices
class Android
  @@no_adb = OS.windows? ? "not recognized" : "not found"

  # Detect locally connected Android devices, once
  def self.detect_devices_once
    log_debug("Detecting connected Android devices...")
    devices = []
    adb_devices = `adb devices 2>&1`
    log_abort "adb is not installed " +
          "or not added to PATH!" if adb_devices.include?(@@no_adb)
    adb_devices.split("\n").each do |device|
      next if device.start_with?("List", "*")
      udid = device.split("\t")[0]
      if device.include?("unauthorized")
        log_warn("Unauthorized device found (#{udid}) - check it for a confirmation dialogue!")
        next
      end
      manufacturer = `adb -s #{udid} shell getprop ro.product.manufacturer`.strip
      model = `adb -s #{udid} shell getprop ro.product.model`.strip
      name = "#{manufacturer.capitalize} #{model}"
      devices.append([name, udid]) if device.include?("device")
    end
    return devices
  end

  # Detect locally connected Android devices with 3 retries
  def self.detect_devices
    devices = self.detect_devices_once
    if devices.empty?
      retries = 1
      while (retries < 3)
        log_warn("No Android devices found, restarting adb server...")
        `adb kill-server && adb start-server`
        sleep 1
        devices = self.detect_devices_once
        break if !devices.empty?
        retries += 1
      end
      log_abort "Could not find any connected Android devices!" if retries >= 3
    end
    return devices
  end

  ########################################################
  # NON-TEST METHODS (not called in 'testray execute')
  ########################################################

  # List and return the available target devices
  def self.list_devices()
    all_devices = self.detect_devices
    network_devices = all_devices.select {|d| d[1].include?(":")}
    usb_devices = all_devices.reject {|d| d[1].include?(":")}
    all_udids = all_devices.map {|d| d[1]}

    log_abort "No Android devices found!" if all_devices.empty?
    output = "Available Android devices: #{prettyprint_devices(all_devices)}"
    output += "\nConnected over USB: #{prettyprint_devices(usb_devices)}" unless usb_devices.empty?
    output += "\nConnected over network: #{prettyprint_devices(network_devices)}" unless network_devices.empty?
    return all_udids, output
  end

  # Returns the installed version of the provided app on target device
  # If app is not present, prints N/A and returns nil
  def self.version(app, udid, printout=false)
    check_for_app_name(app)
    check_app_data_present(app, "Package")
    package = $config["Apps"][app]["Package"]
    ver = `adb -s #{udid} shell dumpsys package #{package} | grep -m1 versionName`
    version = ver.empty? ? "N/A" : ver.split("versionName=")[-1].strip
    log_info "#{app} installed version: #{version}" if printout
    version = nil if version == "N/A"
    return version
  end

  # Returns the latest version number of the provided app, taken from apkpure
  def self.latest(app)
    check_for_app_name(app)
    check_app_data_present(app, "Download")
    page = Nokogiri::HTML(URI.open($config["Apps"][app]["Download"]))
    latest_version = page.css("span[itemprop='version']")[0].text
    latest_version = latest_version.delete!(" ")
    log_info "#{app} available version: #{latest_version}"
    return latest_version
  end

  # Force stops the provided app on target device
  def self.stop(app, udid)
    check_for_app_name(app)
    check_app_data_present(app, "Package")
    package = $config["Apps"][app]["Package"]
    `adb -s #{udid} shell am force-stop #{package}`
    log_info "Stopped #{app}"
  end

  # Uninstalls the provided app from target device
  def self.uninstall(app, udid)
    check_for_app_name(app)
    check_app_data_present(app, "Package")
    log_abort "#{app} is not installed!" if self.version(app, udid).nil?
    package = $config["Apps"][app]["Package"]
    `adb -s #{udid} uninstall #{package}`
    log_info "Successfully uninstalled #{app}!"
  end

  # Installs the latest version of the app, taken from apkpure
  # If app is already installed, attempts to update it
  def self.install(app, udid, latest)
    check_for_app_name(app)
    installed = self.version(app, udid)
    if !installed.nil?
      if installed == latest
        log_info "#{app} is already on the latest version!"
        return
      end
      if is_newer_version(installed, latest)
        log_info "#{app} has a newer version available - updating..."
      else
        log_info "#{app} version is newer than available on apkpure..."
        return
      end
    else
      log_info "#{app} not installed - continuing..."
    end

    # Get actual download link
    page = Nokogiri::HTML(URI.open($config["Apps"][app]["Download"]))
    link = page.css("a.da")[0]["href"]
    page = Nokogiri::HTML(URI.open("https://apkpure.com#{link}"))
    link = page.css("#download_link")[0]["href"]

    # Download apk file
    log_info "Downloading #{app} version #{latest} from #{link}..."
    out, err, status = Open3.capture3(
      "curl --insecure -L \"#{link}\" -o #{app}.apk"
    )
    log_abort "Could not download app: #{err}" unless status.success?

    # Install apk file
    log_info "Installing #{app} version #{latest}..."
    out, err, status = Open3.capture3(
      "adb -s #{udid} install -r #{app}.apk"
    )
    log_abort "Could not install app: #{err}" unless status.success?

    log_info "Successfully installed #{app} version #{latest}!"
  end

  # Reinstalls the specified app
  def self.reinstall(app, udid, latest)
    self.uninstall(app, udid)
    self.install(app, udid, latest)
  end

  # Takes a screenshot
  def self.screenshot(app, udid)
    time = Time.now.strftime("%Y%m%d-%H%M%S")
    `adb -s #{udid} exec-out screencap -p > #{udid}_#{time}.png`
    log_info "Created screenshot '#{udid}_#{time}.png'"
  end

  # Press home button
  def self.home_button(app, udid)
    `adb -s #{udid} shell input keyevent 3`
    log_info "Pressed home button"
  end

  def self.get_chrome_driver(udid)
    v = `adb -s #{udid} shell dumpsys package com.android.chrome | grep versionName`
    vers = v.split("versionName=")[1].split(".")[0]
    return "chromedriver#{vers}" if File.exists? "chromedriver#{vers}"

    r = HTTParty.get("https://chromedriver.storage.googleapis.com").body

    chrome_driver_file_name = "chromedriver_mac64.zip"
    unzip_cmd = "unzip -a -o"
    mv_cmd = "mv"
    rm_cmd = "rm"

    if OS.windows?
      chrome_driver_file_name = "chromedriver_win32.zip"
      unzip_cmd = "tar -xf"
      mv_cmd = "move"
      rm_cmd = "del"
    end

    chrome_version = ""
    r.split("#{vers}.").each do |text|
      if text.include?(chrome_driver_file_name)
        new_chrome_version = "#{vers}.#{text.split(chrome_driver_file_name)[0]}"
        if new_chrome_version.length < 17
          chrome_version = new_chrome_version
        end
      end
    end

    log_info "https://chromedriver.storage.googleapis.com/#{chrome_version}#{chrome_driver_file_name}"

    `curl -L \"https://chromedriver.storage.googleapis.com/#{chrome_version}#{chrome_driver_file_name}\" -o chromedriver#{vers}.zip`
    `#{unzip_cmd} chromedriver#{vers}.zip`
    `#{mv_cmd} chromedriver chromedriver#{vers}`
    `#{rm_cmd} chromedriver#{vers}.zip`
    log_info chrome_version
    log_info "chromedriver#{vers}"
    return "chromedriver#{vers}"
  end
end

def is_newer_version(installed, latest)
  v_o = installed.split(".")
  v_n = latest.split(".")
  i = 0
  newer = false
  v_n.each do |sub_vers|
    i += 1
    begin
      sub_vers.to_i
    rescue => e
      next
    end
    break if sub_vers.to_i < v_o[i - 1].to_i
    next if sub_vers.to_i == v_o[i - 1].to_i
    if sub_vers.to_i > v_o[i - 1].to_i
      newer = true
      break
    end
  end

  return newer
end
