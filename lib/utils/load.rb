require "yaml"

# Utility methods that are related to loading data,
# either from files or into environment variables

# Load common data used in all types of execution
def load_common_execute_parameters(log_level)
  ENV["LOG_LEVEL"] = log_level
  check_folder_exists
  load_config_file
end

# Load data specific to an individual case
def load_case_specific_parameters(case_name, steps, parent_setup_params)
  # testRay Sets Environments have been load already
  load_env_and_vars(parent_setup_params) # Loads environment vars and commands for main case
  load_env_and_vars(steps) # Loads case Vars and setup commands
  load_env_and_vars(parent_setup_params, false) # Loads environment vars so that cases vars 
                                                # can fill the information for Env vars with $AND_CLI$ wrappers
  execute_setupcommands(parent_setup_params) # Runs the setup command for the TestRay Set file specific case commands 
  if parent_setup_params.key?("Log") && !parent_setup_params["Log"].empty?
    logfile_name = parent_setup_params["Log"]
  else
    logfile_name = "#{case_name}_log.txt"
  end
  File.delete(logfile_name) if File.exist?(logfile_name)
  ENV["LOG_FILE"] = logfile_name
  set_case_log_report(case_name, File.join(Dir.pwd, "Reports", "logs", logfile_name))
end

########################################################
### Methods that load files
########################################################

# Load the YAML config file, from cases/config.yaml
def load_config_file(print_path = false)
  conf_path = File.join(Dir.getwd(), "cases/config.yaml")
  log_abort("Could not find config file! Please ensure it is located " +
            "in the 'cases' directory!") unless File.exist?(conf_path)
  log_debug("Using configuration file: #{conf_path}") if print_path
  $config = nil
  begin
    $config = YAML.load_file(conf_path)
  rescue => e
    log_abort("Could not load config file!\n#{e.message}")
  end
end

# Load all the YAML case files, matched by cases/**/case*.yaml
def load_case_files()
  case_name_files = {}
  cases = {}
  begin
    Dir.glob("cases/**/case*.yaml").each do |filename|
      casefile_path = File.join(Dir.getwd(), filename)
      log_debug("Found case file: #{casefile_path}")
      yaml_file = YAML.load_file(casefile_path)
      next unless yaml_file
      cases.merge!(yaml_file)

      # gather the case names to identify duplicates
      File.open(casefile_path, "r") do |file|
        # find words with no preceding spaces and a succeeding colon (= case names)
        case_names = file.read.scan(/(?:\n|^)(\w+):/).flatten
        for case_name in case_names
          if case_name_files.key?(case_name)
            case_name_files[case_name].append(filename)
          else
            case_name_files[case_name] = [filename]
          end
        end
      end
    end
  rescue => e
    log_abort("Could not load case files!\n#{e.message}")
  end

  # check for duplicates
  found_duplicates = false
  case_name_files.each do |case_name, files|
    next if files.length == 1
    log_error("Found #{files.length} declarations for case " +
              "'#{case_name}'! Check files: #{files}")
    found_duplicates = true
  end
  log_abort("Encountered duplicate cases!") if found_duplicates

  return cases
end


# Load all the YAML pageobject files, matched by page_objects/**/page*.yaml
def load_pageobject_files()
  pageobject_name_files = {}
  pageobjects = {}
  begin
    Dir.glob("page_objects/*.yaml").each do |filename|
      pageobjectfile_path = File.join(Dir.getwd(), filename)
      log_debug("Found page object file: #{pageobjectfile_path}")
      yaml_file = YAML.load_file(pageobjectfile_path)
      next unless yaml_file
      pageobjects.merge!(yaml_file)

      # gather the case names to identify duplicates
      File.open(pageobjectfile_path, "r") do |file|
        # find words with no preceding spaces and a succeeding colon (= case names)
        pageobjects_names = file.read.scan(/(?:\n|^)(\w+):/).flatten
        for pageobject_name in pageobjects_names
          if pageobject_name_files.key?(pageobject_name)
            pageobject_name_files[pageobject_name].append(filename)
          else
            pageobject_name_files[pageobject_name] = [filename]
          end
        end
      end
    end
  rescue => e
    log_abort("Could not load pageobject files!\n#{e.message}")
  end

  # check for duplicates
  found_duplicates = false
  pageobject_name_files.each do |pageobject_name, files|
    next if files.length == 1
    log_error("Found #{files.length} declarations for page object " +
              "'#{pageobject_name}'! Check files: #{files}")
    found_duplicates = true
  end
  log_abort("Encountered duplicate pageobject!") if found_duplicates

  return pageobjects
end

# Load all the YAML set files, matched by sets/**/set*.yaml
def load_set_files()
  set_name_files = {}
  sets = {}
  check_folder_exists("sets")
  begin
    Dir.glob("sets/**/set*.yaml").each do |filename|
      setfile_path = File.join(Dir.getwd(), filename)
      log_info("Found set file: #{setfile_path}")
      yaml_file = YAML.load_file(setfile_path)
      next unless yaml_file
      sets.merge!(yaml_file)

      # gather the sets names to identify duplicates
      File.open(setfile_path, "r") do |file|
        # find words with no preceding spaces and a succeeding colon (= set names)
        set_names = file.read.scan(/(?:\n|^)(\w+):/).flatten
        for set_name in set_names
          if set_name_files.key?(set_name)
            set_name_files[set_name].append(filename)
          else
            set_name_files[set_name] = [filename]
          end
        end
      end
    end
  rescue => e
    log_abort "Could not load set files!\n#{e.message}"
  end

  # check for duplicates
  found_duplicates = false
  set_name_files.each do |set_name, files|
    next if files.length == 1
    log_warn("Found #{files.length} declarations for set " +
             "'#{set_name}'! Check files: #{files}")
    found_duplicates = true
  end
  log_abort "Encountered duplicate sets!" if found_duplicates

  return sets
end

# Load an individual YAML case file, matched by the provided path
def load_case_file(filename)
  case_names = []
  case_file = {}
  casefile_path = File.join(Dir.getwd() + "/cases", filename)
  unless File.exist?(casefile_path)
    log_abort("The case file '#{filename}' doesn't exist!")
  end
  begin
    case_file = YAML.load_file(casefile_path)
    File.open(casefile_path, "r") do |file|
      # find words with no preceding spaces and a succeeding colon (= case names)
      case_names = file.read.scan(/(?:\n|^)(\w+):/).flatten
    end
  rescue => e
    log_abort("Could not parse the case file!\n#{e.message}")
  end

  # check for duplicates
  if case_names.uniq.length != case_names.length
    log_abort("File contains duplicate case names!\n" +
              "Found case names: #{case_names}")
  end

  return case_file
end

def load_case_files_from_folder(foldername)
  case_name_files = {}
  cases = {}
  begin
    Dir.glob("cases/#{foldername}/case*.yaml").each do |filename|
      casefile_path = File.join(Dir.getwd(), filename)
      log_debug("Found case file: #{casefile_path}")
      yaml_file = YAML.load_file(casefile_path)
      next unless yaml_file
      cases.merge!(yaml_file)

      # gather the case names to identify duplicates
      File.open(casefile_path, "r") do |file|
        # find words with no preceding spaces and a succeeding colon (= case names)
        case_names = file.read.scan(/(?:\n|^)(\w+):/).flatten
        for case_name in case_names
          if case_name_files.key?(case_name)
            case_name_files[case_name].append(filename)
          else
            case_name_files[case_name] = [filename]
          end
        end
      end
    end
  rescue => e
    log_abort("Could not load case files!\n#{e.message}")
  end

  # check for duplicates
  found_duplicates = false
  case_name_files.each do |case_name, files|
    next if files.length == 1
    log_error("Found #{files.length} declarations for case " +
              "'#{case_name}'! Check files: #{files}")
    found_duplicates = true
  end
  log_abort("Encountered duplicate cases!") if found_duplicates

  return cases
end

########################################################
### Methods that load environment variables
########################################################

def load_env_and_vars(structure, setup_commands=true)
  load_environment(convert_value(structure["Environment"]), setup_commands) if structure.key?("Environment")
  load_vars(structure)
end

# Load the specified vars into the environment
def load_vars(structure)
  if structure.key?("Vars") && structure["Vars"]
    structure["Vars"].each do |key, value|
      log_debug("Adding var: #{key} = #{convert_value(value)}")
      ENV[key] = convert_value(value)
    end
  end
end

# Load an environment, which is a set of environment variables
def load_environment(wanted_envs, setup_commands=true)
  return if wanted_envs.nil? || wanted_envs == "" 
  if wanted_envs.is_a? Array
    wanted_envs.each do |wanted_env|
      load_environment(wanted_env)
    end
    return
  end
  envs = $config["Environments"]
  return unless envs
  log_abort "Could not find environment '#{wanted_envs}'!" unless envs.key? wanted_envs
  # It will first Load the Inherit Envs and then the child ones
  if envs[wanted_envs].key?("Inherit")
    for inh_env in envs[wanted_envs]["Inherit"] do
      load_environment(inh_env)
    end
  end
  if setup_commands
    log_info("Loading environment '#{wanted_envs}'") 
  else
    log_info("Loading vars for '#{wanted_envs}'") 
  end
  load_vars(envs[wanted_envs])
  if envs[wanted_envs]["SetupCommands"] && setup_commands
    for command in envs[wanted_envs]["SetupCommands"] do 
      if ENV["LOG_LEVEL"] == "error"
        system(command, out: File::NULL, err: $stderr)
      else
        system(command, out: $stdout, err: $stderr)
      end
    end
  end
end

# Load grepped values from case actions into the environment
def load_grep(grep, value)
  actual_value = convert_value(value);
  matching = actual_value.match(/#{grep["match"]}/)
  begin
    end_value = matching[0]
    end_value.slice! grep["remove"] if grep["remove"]
    ENV[grep["var"]] = end_value
    log_info("Var '#{grep["var"]}' with Match: '#{end_value}'")
  rescue => e
    ENV[grep["var"]] = ""
    log_warn("No Match for '#{actual_value}' and grep '#{grep}'")
  end
end