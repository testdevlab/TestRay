require_relative "device_handler"
require_relative "types_control_flow"
include ControlFlowTypes

# Class describing a Selenium/Appium test runner, for a single top-level test case.
# Calls DeviceHandler to instantiate all required Selenium/Appium devices,
# and subsequently iterates through the test structure.
class CaseRunner
  attr_reader :device_handler
  SYNC_ACTIONS = ["case", "loop", "if", "sync", "timer"]

  def initialize(all_cases, case_name, parent_setup_params)
    # validate case and load environment, variables, log file
    @cases = all_cases
    @main_steps = check_case_exists(@cases, case_name, initial = true)
    check_case_structure(@main_steps)
    load_case_specific_parameters(case_name, @main_steps, parent_setup_params)
    check_case_roles_apps(@main_steps)

    # create devices for all requested roles
    @device_handler = DeviceHandler.new(@main_steps["Roles"])
  end

  # main entrypoint method for the actual test case execution
  # called from TestRay CLI methods, or other test cases
  # Parameters: test case name; parent role/environment/variables
  def run(case_name, parent_params = {})
    unless @main_case
      @main_case = case_name
      @main_case_id = " #{Time.now.strftime("%Y-%m-%d %H:%M:%S.%L")}"
      log_info("Starting main case #{case_name}")
      steps = @main_steps
    else
      # if not main, validate case, load its environment and variables
      steps = check_case_exists(@cases, case_name)
      load_env_and_vars(steps)
      load_env_and_vars(parent_params)
    end

    # first run any precases
    if steps["Precases"]
      steps["Precases"].each do |pre_case|
        begin
          run(convert_value(pre_case))
        rescue => e
          log_warn("Pre-Case '#{pre_case}' Error: #{e.message}")
        end
      end
    end
    begin
          
      logger_step(case_name + ' Started ' + Time.now.strftime("%Y-%m-%d %H:%M:%S.%L"), @main_case, @main_case_id)
      steps_handler(case_name, parent_params["Role"], steps)
      logger_step(case_name + ' Completed ' + Time.now.strftime("%Y-%m-%d %H:%M:%S.%L"), @main_case, @main_case_id)
      log_info("All cases have finished") if case_name == @main_case
    rescue => e
      # if encountered error, first run any aftercases
      if steps["Aftercases"]
        steps["Aftercases"].each do |after_case|
          begin
            run(convert_value(after_case))
          rescue => e_after
            log_warn("After Case '#{after_case}' Error: #{e_after.message}")
          end
        end
      end

      # fail case unless specified otherwise
      unless steps["NoRaise"]
        logger_step_fail(case_name, @main_case, @main_case_id, e.message) #if case_name != @main_case
        raise "There was an error in case '#{case_name}': #{e.message}" 
      end
        
      # error was not raised -> return so that aftercases are not called twice
      return
    end

    # after successful execution, run any aftercases
    if steps["Aftercases"]
      steps["Aftercases"].each do |after_case|
        begin
          run(convert_value(after_case))
        rescue => e
          log_warn("After Case '#{after_case}' Error: #{e.message}")
        end
      end
    end
  end

  # method for iterating through the test case actions
  # and calling the respective execution handlers 
  # Parameters: test case name; parent role; test case steps
  def steps_handler(case_name, parent_role, steps)
    case_threads = {}
    @start ||= 0

    # first determine if execution is parallel or sequential
    is_parallel_roles = steps.key?("ParallelRoles") && steps["ParallelRoles"]
    exec_type = is_parallel_roles ? "parallel" : "sequential"
    actions = is_parallel_roles ? {} : []
    action_exec_method = "start_#{exec_type}_actions"

    # identify the main role (either from case header or parent case)
    main_role = convert_value(steps["Roles"][0]["Role"]) if steps.key?("Roles")
    main_role = convert_value(parent_role) unless parent_role.nil?
    ENV["MAINROLE"] = main_role

    # iterate through case actions
    steps["Actions"].each do |action|
      # first check if gherkin step is used
      g_case, g_prefix =  check_gherkin_step(action)
      if g_case
        action["Type"] = "case"
        action["Value"] = g_case
      end

      # determine role that should execute action, and log this
      action_role = action.key?("Role") ? convert_value(action["Role"]) : main_role
      action_string = "Case '#{case_name}': adding "
      action_string += SYNC_ACTIONS.include?(action["Type"]) ? "" : "#{exec_type} "
      if action["Type"] == "case"
        action_string += "case '#{action["Value"]}' "
      else
        action_string += "action: '#{action["Type"]}' "
      end
      action_string += "for role #{action_role}" if action.key?("Role")
      log_debug(action_string)

      # for generic actions, add to structure and proceed
      unless SYNC_ACTIONS.include?(action["Type"])
        action_role.split(",").each do |role|
          if exec_type == "parallel"
            actions[role] = [] if actions[role] == nil
            actions[role].append(action)
          else
            actions.append([role, action])
          end
        end
        next
      end

      # for control flow actions, first execute all gathered actions
      actions = self.send(action_exec_method, actions)
      # then check for the actual control flow action
      case action["Type"]
      when "case"
        if steps.key?("ParallelCases")
          max_parallel_cases = steps["ParallelCases"]
          case_threads = parallel_case_handler(
            action, case_threads, max_parallel_cases
          )
        else
          case_handler(action, case_name)
        end
        if g_prefix
          logger_step "#{g_prefix} #{g_case}", @main_case, @main_case_id
        end
      when "sync"
        if action.key?("Value")
          sync_steps_handler(action)
        elsif !case_threads.empty?
          sync_cases_handler(case_threads)
          case_threads = {}
        end
      when "if"
        if_handler(action, case_name)
      when "loop"
        loop_handler(action, case_name)
      when "timer"
        @start = timer_handler(action, action_role, @start)
      else
        log_error("Unknown action type: #{action["Type"]}")
      end
    end

    self.send(action_exec_method, actions)
    sync_cases_handler(case_threads) unless case_threads.empty?
  end

  # iterator for executing identified parallel actions
  # 'actions' is a dictionary, where keys are roles,
  # and values are one or more actions for that role
  def start_parallel_actions(actions)
    threads = []
    Thread.report_on_exception = false
    actions.each do |role, role_actions|
      thread = Thread.new do
        role_actions.each do |action|
          single_action_exe(action, role)
        end
      end
      threads.append(thread)
    end
    threads.each do |thread|
      thread.join
    end
    return {}
  end

  # iterator for executing identified sequential actions
  # 'actions' is a list of lists, each of which has
  # exactly 1 role and 1 action
  def start_sequential_actions(actions)
    actions.each do |role, action|
      single_action_exe(action, role)
    end
    return []
  end

  # executor for a single action, for a single role
  def single_action_exe(action, role)
    unless @device_handler.devices[role]
      log_warn("Role '#{role}' was not found! Running next step...")
      return
    end

    begin
      load_vars(action)
      log_step(role, action)
      if action["Type"] == "sleep"
        @device_handler.devices[role].pause(action["Time"])
        report_step(prepare_report_step(role, action) , @main_case, @main_case_id) #Logging action into report
      else
        @device_handler.devices[role].send(action["Type"], action, @main_case, @main_case_id)
        report_step(prepare_report_step(role, action) , @main_case, @main_case_id) #Logging action into report
      end
    rescue RuntimeError => e
      raise e unless action["FailCase"]
      log_info("Received error '#{e.message}' while running #{action} action, " +
            "will execute callback")
      parent_params = {}
      parent_params["Role"] = role if action.key?("Role")
      parent_params["Vars"] = action["Vars"] if action.key?("Vars")
      run(action["FailCase"]["Value"], parent_params)
      raise e unless action["FailCase"]["ContinueOnFail"]
    end
  end
end

def log_step(role, action)
  if action["Type"] == "command"
    log_info("Role: '#{role}', Action: '#{action["Type"]}', " +
    "Value: '#{action["Value"]}'")
  elsif action["Type"] == "sleep"
    log_info("Role: '#{role}', Action: '#{action["Type"]}', " +
    "Time: '#{action["Time"]}'")
  elsif action["Type"] == "get_call"
    log_info("Role: '#{role}', Action: '#{action["Type"]}', " +
    "Url: '#{action["Url"]}'")
  elsif action["Type"] == "post_call"
    log_info("Role: '#{role}', Action: '#{action["Type"]}', " +
    "Body: '#{action["Body"]}', Url: '#{action["Url"]}'")
  elsif action["Type"] == "swipe_coord"
    log_info("Role: '#{role}', Action: '#{action["Type"]}', " +
    "Coords: Start -> X:'#{action["StartX"]}', Y: '#{action["StartY"]}' - " +
    "End -> X:'#{action["EndX"]}', Y: '#{action["EndY"]}'")
  else
    if action["Strategy"] && action["Value"]
      log_info("Role: '#{role}', Action: '#{action["Type"]}', " +
            "Element: '#{action["Strategy"]}:#{action["Id"]}', " +
            "Value: '#{convert_value(action["Value"])}'")
    elsif action["Strategy"]
      log_info("Role: '#{role}', Action: '#{action["Type"]}', " +
          "Element: '#{action["Strategy"]}:#{action["Id"]}'")
    else
      log_info("Role: '#{role}', Action: '#{action["Type"]}', " +
        "Value: '#{convert_value(action["Value"])}'")
    end
  end
end
#method to add report step for action type
def prepare_report_step(role, action)
    if action["Type"] == "command"
      return "Role: '#{role}', Action: '#{action["Type"]}', " +
      "Value: '#{action["Value"]}', '#{Time.now.strftime("%Y-%m-%d %H:%M:%S.%L")}'"
    elsif action["Type"] == "sleep"
      return "Role: '#{role}', Action: '#{action["Type"]}', " +
      "Time: '#{action["Time"]}', '#{Time.now.strftime("%Y-%m-%d %H:%M:%S.%L")}'"
    elsif action["Type"] == "get_call"
      return "Role: '#{role}', Action: '#{action["Type"]}', " +
      "Url: '#{action["Url"]}', '#{Time.now.strftime("%Y-%m-%d %H:%M:%S.%L")}'"
    elsif action["Type"] == "post_call"
     return "Role: '#{role}', Action: '#{action["Type"]}', " +
      "Body: '#{action["Body"]}', Url: '#{action["Url"]}', '#{Time.now.strftime("%Y-%m-%d %H:%M:%S.%L")}'"
    elsif action["Type"] == "swipe_coord"
     return "Role: '#{role}', Action: '#{action["Type"]}', " +
      "Coords: Start -> X:'#{action["StartX"]}', Y: '#{action["StartY"]}' - " +
      "End -> X:'#{action["EndX"]}', Y: '#{action["EndY"]}', '#{Time.now.strftime("%Y-%m-%d %H:%M:%S.%L")}'"
    elsif action["Type"] == "maximize"
      return "Role: '#{role}', Action: '#{action["Type"]}', '#{Time.now.strftime("%Y-%m-%d %H:%M:%S.%L")}'"
    else
      if action["Strategy"] && action["Value"]
       return "Role: '#{role}', Action: '#{action["Type"]}', " +
              "Element: '#{action["Strategy"]}:#{action["Id"]}', " +
              "Value: '#{action["Value"]}', '#{Time.now.strftime("%Y-%m-%d %H:%M:%S.%L")}'"
      elsif action["Strategy"]
       return "Role: '#{role}', Action: '#{action["Type"]}', " +
            "Element: '#{action["Strategy"]}:#{action["Id"]}', '#{Time.now.strftime("%Y-%m-%d %H:%M:%S.%L")}'"
      else
        return "Role: '#{role}', Action: '#{action["Type"]}', " +
          "Value: '#{action["Value"]}', '#{Time.now.strftime("%Y-%m-%d %H:%M:%S.%L")}'"
      end
    end
end
