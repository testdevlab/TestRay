require "json"
require_relative "rest_api"

# Methods and classes describing communication with devices through TestUI Grid.

class UIGrid
  def self.retrieveAndroidDevice(url, payload, role)
    log_info "TestUI Grid: requesting device: #{payload}"
    response = post(
      "#{url}/session/start",
      cookies: {},
      headers: {},
      payload: payload.to_json,
    )
    raise "TestUI Grid: failed to fetch a device!" if response.code != 200
    device = JSON.parse(response)
    raise "TestUI Grid: not available browser with: " +
            "#{payload} - #{role} - #{device["error"]} - #{url}" if device["error"]

    return device
  end

  def self.releaseAndroidDevice(url, device_json)
    device_name = device_json[:deviceName]
    payload = { "appium" => { "deviceName" => "#{device_name}" } }
    log_info "Releasing Appium device: #{payload}"
    release = post(
      "#{url}/session/release",
      cookies: {},
      headers: {},
      payload: payload.to_json,
    )

    raise "Failed to release a device!" if release.code != 200
  end

  def self.retrieveIosDevice(url, payload, role)
  end

  def self.releaseIosDevice(url, device_json)
  end

  def self.releaseAllSelenium(url)
    nodes = get("#{url}/nodes", cookies: {}, headers: {})
    json_response = JSON.parse(nodes)
    json_response["selenium"].each do |selenium|
      next unless selenium["session"]
      selenium["session"].each do |session|
        log_info "Released session: #{session["value"]["sessionId"]}"
        release = post(
          "#{url}/nodes/delete?ID=#{session["value"]["sessionId"]}",
          cookies: {},
          headers: {},
          payload: session.to_json,
        )
      end
    end
    j = 1
    json_response["selenium"].each do |selenium|
      for i in selenium["available"]...selenium["instances"]
        body = {:selenium => {:browser => selenium["browser"], :ID => j}}
        log_info "Releasing: #{body.to_json}"
        release = post(
          "#{url}/session/release",
          cookies: {},
          headers: {},
          payload: body.to_json,
        )
      end
      j += 1
    end
  end
end
