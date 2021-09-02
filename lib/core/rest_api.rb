require "json"
require "rest-client"

AUTOMATION_USER_AGENT = "PA-API-Automation"

# BASIC REST METHODS
def post(url, headers: {}, cookies: {}, payload: {})
  # RestClient.log = 'stdout'
  headers = {} unless headers
  headers["User-Agent"] = AUTOMATION_USER_AGENT unless headers["User-Agent"]
  RestClient::Request.execute(
    method: :post,
    url: url,
    headers: headers,
    cookies: cookies,
    payload: payload,
  ) do |response|
    response
  end
end
  
def get(url, headers: {}, cookies: {})
  # RestClient.log = 'stdout'
  headers = {} unless headers
  headers["User-Agent"] = AUTOMATION_USER_AGENT unless headers["User-Agent"]

  RestClient::Request.execute(
    method: :get,
    url: url,
    headers: headers,
    cookies: cookies,
  ) do |response|
    response
  end
end
  
def put(url, headers: {}, cookies: {}, payload: {})
  # RestClient.log = 'stdout'
  headers = {} unless headers
  headers["User-Agent"] = AUTOMATION_USER_AGENT unless headers["User-Agent"]
  RestClient::Request.execute(
    method: :put,
    url: url,
    headers: headers,
    cookies: cookies,
    payload: payload,
  ) do |response|
    response
  end
end
  
def delete(url, headers: {}, cookies: {})
  # RestClient.log = 'stdout'
  headers["User-Agent"] = AUTOMATION_USER_AGENT unless headers["User-Agent"]
  RestClient::Request.execute(
    method: :delete,
    url: url,
    headers: headers,
    cookies: cookies,
  ) do |response|
    response
  end
end

# PRIVATE METHODS TO USE FOR API CLASS
private

def assert_calls(r, asserts)
  if asserts
    asserts.each do |assert|
      if assert["Type"] == 'code'
        unless assert["Value"].is_a?(Integer) 
          raise 'Value type should be a Integer but it is NOT, Please use integers for Status Codes'
        end
        unless assert["Value"] == r.code
          raise "The status code was #{r.code}, but it was expected to be #{assert["Value"]}"
        end
      end
    end
  end
end

def post_method(action, body)
  url, greps = action["Url"], action["Greps"]
  headers, cookies = action["Headers"], action["Cookies"]
  if headers
    headers.each do |key, value|
      headers[key] = convert_value(value)
    end
  end
  log_info("Body without convert: #{body}")
  
  url = convert_value(url)
  headers = {} if headers.nil?
  cookies = {} if cookies.nil?
  payload = nil

  if body["Multipart"] || body["multipart"]
    payload = get_multipart_files(body)
  else
    if body.is_a? Hash
      payload = eval(convert_value(body)).to_json
    else
      payload = convert_value(body).to_json
    end
  end

  log_info("url: #{url},\npayload: #{payload}")
  r = post(url, cookies: cookies, headers: headers, payload: payload)
  # CHECK FOR ASSERTS
  assert_calls(r, action["Asserts"])
  # CHECK IF RESPONSE HAS A FILE AND WRITE IT
  if action["File_Response"]
    File.open(convert_value(action["File_Response"]), "wb") {
      |f|
      f.write r.body
    }
  else
    log_info(r)
  end
  begin
    unless greps.nil?
      greps.each do |grep|
        matching = r[grep["match"]]
        log_info(matching)
        ENV[grep["var"]] = matching
      end
    end
  rescue => e
  end
end

def get_multipart_files(body)
  payload = {:multipart => true}
  body.each do |key, value|
    next if key == "Multipart"

    file_m = convert_value(value)
    if !File.exist? file_m
      Dir.entries(".").select { |in_files|
        in_files.include?(".")
      }.each do |file|
        next unless file.match(/#{convert_value(body["File"])}/)
        if file.match(/#{convert_value(body["File"])}/)[0]
          file_m = file.match(/#{convert_value(body["File"])}/)[0]
          log_info("found file: #{file_m}")
          file_m = File.join(".", file_m)
          break
        end
      end
    end
    if !File.exist? file_m
      log_warn("File '#{file_m}' does not exist, won't be doing the POST call")
      next
    end
    payload[key] = File.new(file_m, "rb")
  end

  return payload
end

def get_method(action)
  url, greps = action["Url"], action["Greps"]
  headers, cookies = action["Headers"], action["Cookies"]
  headers = {} if headers.nil?
  cookies = {} if cookies.nil?
  url = convert_value(url)
  r = get("#{url}", cookies: cookies, headers: headers)
  # CHECK FOR ASSERTS
  assert_calls(r, action["Asserts"])
  # CHECK IF RESPONSE HAS A FILE AND WRITE IT
  r_json = nil
  if action["File_Response"]
    File.open(convert_value(action["File_Response"]), "wb") {
      |f|
      f.write r.body
    }
  else
    r_json = JSON.parse(r)
    log_info("response:\n#{r_json.to_s}")
  end
  unless greps.nil?
    greps.each do |grep|
      matching = r_json[grep["match"]]
      log_info("Setting variable '#{grep["var"]}' to '#{matching}'")
      ENV[grep["var"]] = matching
    end
  end
end

def put_method(action, body)
  url, greps = action["Url"], action["Greps"]
  headers, cookies = action["Headers"], action["Cookies"]
  if headers
    headers.each do |key, value|
      headers[key] = convert_value(value)
    end
  end

  log_info("Body without convert: #{body}")
  
  url = convert_value(url)
  headers = {} if headers.nil?
  cookies = {} if cookies.nil?
  payload = nil
  if body.is_a? Hash
    payload = eval(convert_value(body)).to_json
  else
    payload = convert_value(body).to_json
  end
  
  log_info("url: #{url},\npayload: #{payload}")
  r = put(url, cookies: cookies, headers: headers, payload: payload)
  # CHECK FOR ASSERTS
  assert_calls(r, action["Asserts"])
  # CHECK IF RESPONSE HAS A FILE AND WRITE IT
  if action["File_Response"]
    File.open(convert_value(action["File_Response"]), "wb") {
      |f|
      f.write r.body
    }
  else
    log_info(r)
  end
  begin
    unless greps.nil?
      greps.each do |grep|
        matching = r[grep["match"]]
        log_info(matching)
        ENV[grep["var"]] = matching
      end
    end
  rescue => e
  end
end

def delete_method(action)
  url, greps = action["Url"], action["Greps"]
  headers, cookies = action["Headers"], action["Cookies"]
  headers = {} if headers.nil?
  cookies = {} if cookies.nil?
  url = convert_value(url)
  r = get("#{url}", cookies: cookies, headers: headers)
  # CHECK FOR ASSERTS
  assert_calls(r, action["Asserts"])
  # CHECK IF RESPONSE HAS A FILE AND WRITE IT
  r_json = JSON.parse(r)
  log_info("response:\n#{r_json.to_s}")
  unless greps.nil?
    greps.each do |grep|
      matching = r_json[grep["match"]]
      log_info("Setting variable '#{grep["var"]}' to '#{matching}'")
      ENV[grep["var"]] = matching
    end
  end
end

# API CLASS TO CALL FROM DEVICE CLASS
class Api
  def self.get_call(action)
    get_method(action)
  end

  def self.post_call(action)
    bodys = action["Body"]

    if bodys.is_a? Array
      bodys.each do |body|
        post_method(action, body)
      end
    else
      post_method(action, bodys)
    end
  end

  def self.put_call(action)
    put_method(action)
  end

  def self.delete_call(action)
    delete_method(action)
  end
end