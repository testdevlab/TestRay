require "thor"
require_relative "core/case_runner"
require_relative "core/device"
require_relative "core/logger"
require_relative "core/reports"
require_relative "core/ui_grid"
require_relative "platforms/android"
require_relative "platforms/ios"
require_relative "utils/find"
require_relative "utils/load"
require_relative "utils/other"
require_relative "version"
include PLogger
include Reports

module TestRay
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    $pageobjects = load_pageobject_files()

    desc "execute_help", "help for creating an testray project"
    option :types,
           :desc => "Show Action Types",
           :default => false,
           :type => :boolean
    option :create_project,
           :desc => "Creates an example project",
           :default => false,
           :type => :boolean
    def execute_help()
      if options[:types]
        log_info "Types:\n" + Device.public_instance_methods(false).to_s
      elsif options[:create_project]
        log_warn "Not yet implemented"
      end
    end

    desc "testui_grid <server>", "Manage testUI Grid"
    option :release_device,
           :desc => "Releases device specified",
           :default => ""
    option :release_selenium,
           :desc => "Releases all selenium nodes",
           :default => false,
           :type => :boolean
    def testui_grid(server)
      UIGrid.releaseAllSelenium(server) if options[:release_selenium]
      if options[:release_device] != ""
        device_json = { :deviceName => options[:release_device] }
        UIGrid.releaseAndroidDevice(server, device_json)
      end
    end

    desc "execute <case>", "Execute test case file from testray " +
                           "folder. Default cases/case*.yaml"
    option :retries,
           :desc => "number of test retries",
           :default => 0,
           :type => :numeric
    option :log_file,
           :desc => "sets log file name. Default CASE_NAME_log.txt",
           :default => ""
    option :log_level,
           :desc => "sets log level. Default 'info', possible values: 'info','debug','error'",
           :default => "info"
    option :report,
           :desc => "types of report. Default 'cucumber', possible values: 'cucumber','testray', 'none'",
           :default => "cucumber"
    option :env,
           :desc => "Sets the environment to load from config.yaml file",
           :default => ""
    def execute(case_name, *args)
      load_common_execute_parameters(options[:log_level])
      cases = load_case_files()
      parent_setup_params = {
        "Log" => options[:log_file],
        "Environment" => options[:env],
      }
      run_single_case(cases, case_name, parent_setup_params, options)
    end

    desc "execute_set <set>", "Execute set of test cases defined in set_*.yaml files "
    option :retries,
           :desc => "number of test retries",
           :default => 0,
           :type => :numeric
    option :log_level,
           :desc => "sets log level. Default 'info', possible values: 'info','debug','error'",
           :default => "info"
    option :report,
           :desc => "types of report. Default 'cucumber', possible values: 'cucumber','testray', 'none'",
           :default => "cucumber"
    option :env,
           :desc => "Sets the environment to load from config.yaml file",
           :default => ""
    def execute_set(set_name)
      load_common_execute_parameters(options[:log_level])
      sets = load_set_files()
      log_abort "Could not find set '#{set_name}'!" unless sets.key?(set_name)
      cases = load_case_files()
      set_cases = sets[set_name]
      log_case("Loading Set-Wide Environment and Vars for '#{set_name}'")
      load_env_and_vars(set_cases)
      load_environment(options[:env])
      log_case("Running Set-Wide Set-Up Commands for '#{set_name}'")
      execute_setupcommands(set_cases)
      errors = []
      log_case("Starting Set Execution for '#{set_name}'")
      for set_case in set_cases["Cases"]
        case_name = set_case["Case"]
        parent_setup_params = {
          "Environment" => set_case["Environment"],
          "Vars" => set_case["Vars"],
          "SetupCommands" => set_case["SetupCommands"],
        }
        begin
          retries ||= 0
          error_message = run_single_case(cases, case_name,
                                          parent_setup_params, options, true)
          errors.append("Case #{case_name} with error: #{error_message}") if error_message
        rescue Interrupt
          next
        rescue => e
          if (retries += 1) <= options[:retries]
            log_warn "Retrying Test Case #{case_name}..."
            retry
          end
          errors.append("Case #{case_name} with error: #{e.message}")
          log_error("Encountered error: #{e.message}")
        end
      end

      jsonfile_path = generate_report(options[:report], set_name) 

      unless errors.empty?
        errors.unshift("End of set '#{set_name}' with #{errors.length} errors! " + 
                       "Report in #{jsonfile_path}")
        log_case_error(errors)
        abort()
      else
        log_case("End of set '#{set_name}'. Report in #{jsonfile_path}")
      end
    end

    desc "execute_file <file>", "Execute all cases within the case_*.yaml file. Give relative path from cases folder Ex: case_*.yaml or */case_*yaml"
    option :retries,
           :desc => "number of test retries",
           :default => 0,
           :type => :numeric
    option :log_level,
           :desc => "sets log level. Default 'info', possible values: 'info','debug','error'",
           :default => "info"
    option :report,
           :desc => "types of report. Default 'cucumber', possible values: 'cucumber','testray', 'none'",
           :default => "cucumber"
    option :env,
           :desc => "Sets the environment to load from config.yaml file",
           :default => ""
    def execute_file(case_file_name)
      load_common_execute_parameters(options[:log_level])
      file_cases = load_case_file(case_file_name)
      all_cases =  load_case_files();
      load_environment(options[:env])  
      errors = []
      log_case("Starting Execution for '#{case_file_name}'")
      for case_name in file_cases.keys do
        begin
          retries ||= 0
          error_message = run_single_case(all_cases, case_name, {}, options, true)
          errors.append("Case #{case_name} with error: #{error_message}") if error_message
        rescue Interrupt
          next
        rescue => e
          if (retries += 1) <= options[:retries]
            log_warn "Retrying Test Case #{case_name}..."
            retry
          end
          errors.append("Case #{case_name} with error: #{e.message}")
          log_error("Encountered error: #{e.message}")
        end
      end

      jsonfile_path = generate_report(options[:report], File.basename(case_file_name, ".*")) 

      unless errors.empty?
        errors.unshift("End of file '#{case_file_name}' with #{errors.length} errors! " + 
                       "Report in #{jsonfile_path}")
        log_case_error(errors)
        abort()
      else
        log_case("End of file '#{case_file_name}'. Report in #{jsonfile_path}")
      end
    end

    desc "execute_folder <folder_name>", "Execute all cases within a folder containing case_*.yaml files. Give relative path from project folder Ex: cases/<folder_name>"
    option :retries,
           :desc => "number of test retries",
           :default => 0,
           :type => :numeric
    option :log_level,
           :desc => "sets log level. Default 'info', possible values: 'info','debug','error'",
           :default => "info"
    option :report,
           :desc => "types of report. Default 'cucumber', possible values: 'cucumber','testray', 'none'",
           :default => "cucumber"
    option :env,
           :desc => "Sets the environment to load from config.yaml file",
           :default => ""
    def execute_folder(foldername)
      load_common_execute_parameters(options[:log_level])
      folder_cases = load_case_files_from_folder(foldername)
      all_cases =  load_case_files();
      load_environment(options[:env])  
      errors = []
      log_case("Starting Execution for '#{foldername}'")
      for case_name in folder_cases.keys do
        begin
          retries ||= 0
          error_message = run_single_case(all_cases, case_name, {}, options, true)
          errors.append("Case #{case_name} with error: #{error_message}") if error_message
        rescue Interrupt
          next
        rescue => e
          if (retries += 1) <= options[:retries]
            log_warn "Retrying Test Case #{case_name}..."
            retry
          end
          errors.append("Case #{case_name} with error: #{e.message}")
          log_error("Encountered error: #{e.message}")
        end
      end

      jsonfile_path = generate_report(options[:report], File.basename(foldername, ".*")) 

      unless errors.empty?
        errors.unshift("End of file '#{foldername}' with #{errors.length} errors! " + 
                       "Report in #{jsonfile_path}")
        log_case_error(errors)
        abort()
      else
        log_case("End of file '#{foldername}'. Report in #{jsonfile_path}")
      end
    end
   
    desc "android <action> [app]", "Executes given action on all local Android "+
                                   "devices. A udid can be provided to select " +
                                   "a specific device. Some actions also " +
                                   "require providing the application name."
    option :udid,
           :desc => "device identification number"
    def android(action, app=nil)
      load_config_file()

      extra_params = []
      apkpure_commands = ["latest", "install", "reinstall"]
      if apkpure_commands.include?(action)
        extra_params = [Android.latest(app)]
        return if action == "latest"
      elsif action == "version"
        extra_params = [true]
      end

      devices, output = Android.list_devices
      if action == "list_devices"
        log_info output
        return
      end
      if options[:udid]
        udid = options[:udid]
        log_abort "Device #{udid} not found!\n#{output}" unless devices.include?(udid)
        log_info "\n===== Running '#{action}' for device #{udid}... ====="
        Android.send(action, app, udid, *extra_params)
      else
        devices.each do |device|
          log_info "\n===== Running '#{action}' for device #{device}... ====="
          Android.send(action, app, device, *extra_params)
        end
      end
    end

    desc "ios <action> [app]", "Executes given action on all local iOS devices. "+
                               "A udid can be provided to select a specific " +
                               "device. Some actions also require providing " +
                               "the application name."
    option :udid,
           :desc => "device identification number"
    def ios(action, app=nil)
      load_config_file()

      extra_params = []
      if action == "version"
        extra_params = [true]
      end

      udids_conns, output = Ios.list_devices
      if action == "list_devices"
        log_info output
        return
      end
      if options[:udid]
        udid = options[:udid]
        log_abort "Device #{udid} not found!\n#{output}" unless udids_conns.include?(udid)
        log_info "\n===== Running '#{action}' for device #{udid}... ====="
        udid = [udid, udids_conns[udid]]
        Ios.send(action, app, udid, *extra_params)
      else
        udids_conns.each do |udid_conn|
          log_info "\n===== Running '#{action}' for device #{udid_conn[0]}... ====="
          Ios.send(action, app, udid_conn, *extra_params)
        end
      end
    end
  end
end

# Highest level common method for running tests.
# Does everything that's necessary, within the boundaries of one test case.
def run_single_case(cases, case_name, parent_setup_params, options, no_abort=false)
  log_case("Starting Case Execution for '#{case_name}'")
  begin
    retries ||= 0
    case_run = CaseRunner.new(cases, case_name, parent_setup_params)
    case_run.device_handler.start_drivers
    case_run.run(case_name)
    generate_report(options[:report], case_name) unless no_abort
    log_case("Finished Case Execution for '#{case_name}'")
    return
  rescue Interrupt
    log_warn "Found interrupt!"
  rescue  => e
    log_error("Try ##{retries} is unsuccessful.")
    log_error("Error: #{e.message}")
    if (retries += 1) <= options[:retries]
      case_run.device_handler.stop_drivers if case_run
      case_run.device_handler.stop_servers if case_run
      log_case_warn("Retrying Test Case #{case_name}...")
      retry
    end
    unless no_abort
      generate_report(options[:report], case_name)
      log_abort("Case execution failed!") 
    end
    return e.message
  ensure
    log_info("Stopping Appium drivers and servers...")
    case_run.device_handler.stop_drivers if case_run
    case_run.device_handler.stop_servers if case_run
  end
  File.delete "sync.txt" if File.exist? "sync.txt"
end
