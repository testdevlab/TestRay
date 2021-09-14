require "yaml"

# Utility methods that are related to finding data,
# with either just validation or also returning it

def check_folder_exists(folder = "cases")
  unless Dir.exist?(folder)
    log_abort("'#{folder}' directory doesn't exist! Please ensure you are running " +
              "TestRay in the main directory of your test repository!")
  end
end

def check_case_exists(cases, _case, initial = false)
  step = false
  case_tag = _case
  unless cases.key?(_case)
    cases.each { |k, v| 
      if v["Step"] && v["Step"] == _case
        step = true
        case_tag = k
        break
      end
    }
    log_abort "Could not find case '#{_case}'!" unless step
  end
  
  unless step
    if initial 
      log_info("Found main case: #{_case}")
    else
      log_info("Found case: #{_case}")
    end
  end
  return cases[case_tag]
end

def check_case_structure(case_steps)
  errors = ""
  if !case_steps.key?("Roles") || case_steps["Roles"].nil?
    errors += "\nCase section 'Roles' is missing or empty!"
  elsif !case_steps["Roles"].is_a?(Array)
    errors += "\nCase section 'Roles' should be a list!"
  else
    case_steps["Roles"].each do |case_role_set|
      errors += "\nFound role set without role!" unless case_role_set.key?("Role")
      errors += "\nFound role set without app!" unless case_role_set.key?("App")
    end
  end
  if !case_steps.key?("Actions") || case_steps["Actions"].nil?
    errors += "\nCase section 'Actions' is missing or empty!"
  elsif !case_steps["Actions"].is_a?(Array)
    errors += "\nCase section 'Actions' should be a list!"
  end
  log_abort "Case structure is invalid:#{errors}" unless errors.empty?
end

# Main case must have all roles defined at the top - no need to check actions
def check_case_roles_apps(case_steps)
  found_roles = []
  extra_apps = $config["Apps"] ? $config["Apps"].keys : [] 
  valid_apps = extra_apps + ["browser", "command", "desktop"]
  case_steps["Roles"].each do |case_role_set|
    convert_value(case_role_set["Role"]).split(",").each do |case_role|
      found = false
      $config["Devices"].each do |d|
        d["role"].split(",").each do |config_role|
          next unless case_role == config_role
          found_roles.append(case_role)
          found = true
          break
        end
        break if found
      end
      log_abort "Role '#{case_role}' was not found in config file!" unless found
    end
    app = convert_value(case_role_set["App"])
    log_abort "App '#{app}' was not found in config file!" unless valid_apps.include?(app)
  end
  log_debug("Found roles: " + found_roles.to_s)
end

def check_for_app_name(app)
  log_abort "This action requires an app name!" if app.nil?
end

def check_app_data_present(app, data)
  if $config["Apps"] && $config["Apps"][app] 
    if !$config["Apps"][app][data]
      log_abort "The config file does not have Apps data '#{data}' for '#{app}' application"
    end
  else
    log_abort "The config file does not have Apps data for '#{app}' application"
  end
end

def check_gherkin_step(action)
  gherkin_prefixes = ["Given", "Then", "And", "But", "When"]
  gherkin_prefixes.each do |gherkin_prefix|
    if action[gherkin_prefix]
      return action[gherkin_prefix], gherkin_prefix
    end
  end

  return false, false
end

def find_case_file(_case, step=nil)
  case_info = {}
  case_dir = "cases"
  unless Dir.exist?(case_dir)
    log_abort("'cases' directory doesn't exists! please move all " +
          "your case*.yaml cases to 'cases' directory in your parent project folder")
  end

  begin
    Dir.glob("#{case_dir}/**/case*.yaml").each do |filename|
      casefile_path = File.join(Dir.getwd(), filename)
      yaml_file = YAML.load_file(casefile_path)
      next unless yaml_file
      case_exists = false
      unless yaml_file.key? _case
        yaml_file.each { |k, v| 
          if v["Step"] && v["Step"] == _case
            case_exists = true
            break
          end
        }
        next unless case_exists
      end

      return casefile_path
    end
  rescue => e
    log_abort "Could not parse case files!\n#{e.message}"
  end
end

def get_case_info(_case, file_path, step=nil)
  begin
    case_info = {}
    File.open(file_path, "r") do |file|
      line_n_c, case_found = 1, false
      file.readlines.each do |line|
        line_n_c += 1 
        if line.match(/#{_case}:/) || line.match(/Step: #{_case}/)
          case_info["case_line"] = line_n_c
          case_found = true
          break unless step
        end
        if step && case_found && line.match(/#{step}/)
          case_info["step_line"] = line_n_c
          break
        end
      end
    end

    return case_info
  rescue => e
    log_abort "Could not parse case files!\n#{e.message}"
  end
end

# For windows only, gets window handle from a provided window title returns window handle in dec and time to find window
def get_window_handle(identifier, scenario, window_number = -1, timeout = 30)
  start = Time.now
  powershell_output = ''
  while Time.now - start < timeout
    begin
      powershell_output = nil
      case scenario
      when 'app' # Find window by app name
        log_info("Getting window for app: #{identifier}")
        powershell_output = execute_powershell("(Get-Process #{identifier}).MainWindowHandle")
      when 'title' # Find window by window title
        log_info("Getting window with title: #{identifier}")
        powershell_output = execute_powershell("Get-Process | Where-Object {$_.MainWindowTitle -like \"#{identifier}\"} | Select-Object MainWindowHandle")
      else # Default option, find by app name
        log_warn('No scenario provided, defaulting to searching for window by app name')
        powershell_output = execute_powershell("(Get-Process #{identifier}).MainWindowHandle")
      end
      window_handles=sanitize_powershell_window_handles(powershell_output)
      log_info("Window handle retrieved: #{window_handles}")
      
      if window_handles[window_number].to_i.positive?
        log_info('Found window handle: ', window_handles[window_number].to_i.to_s(16), '')
        return window_handles[window_number].to_i
      end
    rescue
    end
  end
  log_warn('Did not find a window with provided parameters from window title. Last Powershell output:', powershell_output)
  0 # return 0 if no window was found with timeout
end