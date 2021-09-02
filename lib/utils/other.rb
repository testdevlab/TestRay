require "base64"
require "yaml"

# Utility methods not related to loading or finding data,
# primarily used for data conversion

def convert_yaml(yaml)
  converted_str = convert_value(yaml)
  return YAML.load(converted_str.gsub('=>', ':'))
end

def convert_value(value)
  return "" if value.nil?
  value_s = Marshal.load(Marshal.dump(value.to_s))
  if value_s.include?("$AND_CLI_")
    if !value_s.split("$AND_CLI_")[1] ||
       !value_s.split("$AND_CLI_")[1].include?("$")
      raise "Variable: #{value_s} contains a malformed testray variable!"
    end
    cli_var = "$AND_CLI_" + value_s.split("$AND_CLI_")[1].split("$")[0] + "$"
    env_value = ENV[value_s.split("$AND_CLI_")[1].split("$")[0]]
    begin
      value_s.gsub!(cli_var, env_value)
    rescue => e
      value_s.gsub!(cli_var, "")
    end
  elsif value_s.include?("$AND_CMD_")
    cli_var = "$AND_CMD_" + value_s.split("$AND_CMD_")[1].split("$")[0] + "$"
    cmd_value = `#{value_s.split("$AND_CMD_")[1].split("$")[0]}`.gsub!("\n", "")
    begin
      value_s.gsub!(cli_var, cmd_value)
    rescue => e
      value_s.gsub!(cli_var, "")
    end
  end
  if value_s.include?("$AND_CLI_") || value_s.include?("$AND_CMD_")
    value_s = convert_value(value_s)
  end
  while value_s.start_with?(",") ||
        value_s.end_with?(",") ||
        value_s.include?(",,")
    value_s = value_s.gsub(",,", ",").gsub(/^,|,$/, "")
  end
  return value_s
end

def convert_udid(value, udid)
  return "" if value == nil
  if value.include?("$AND_CLI_UDID$")
    cli_var = "$AND_CLI_UDID$"
    value = value.gsub!(cli_var, udid)
  end
  if value.include?("$AND_CLI_UDID$")
    value = convert_value(value)
  end
  return value
end

def execute_powershell(command)
  cmd = %{#{command}}
  encoded_cmd = Base64.strict_encode64(cmd.encode('utf-16le'))
  return `powershell.exe -encodedCommand #{encoded_cmd}`
end

def execute_setupcommands(structure)
  return unless structure.key?("SetupCommands") && structure["SetupCommands"]
  for command in structure["SetupCommands"] do 
    if ENV["LOG_LEVEL"] == "error"
      system(command, out: File::NULL, err: $stderr)
    else
      system(command, out: $stdout, err: $stderr)
    end
  end
end

def prettyprint_devices(device_list)
  prettied_list = ""
  device_list.each_with_index do |device, index|
    prettied_list << "\n\t#{device[0]} (#{device[1]})"
  end
  prettied_list
end

# Parse powershell output and return only positive window handles
def sanitize_powershell_window_handles(powershell_output)
  window_handle_list = powershell_output.split("\n")
  return window_handle_list.select { |wh| wh.to_i.positive? }
end