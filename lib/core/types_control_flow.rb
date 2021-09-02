# Module describing the handling of control flow 'Type' values in test cases
module ControlFlowTypes
  # execute a case
  def case_handler(action, _case)
    run(action["Value"], get_parent_params(action))
    log_info("Finished case #{action["Value"]}, resuming parent case #{_case}")
  end

  # execute a case that can be run in parallel with another case
  def parallel_case_handler(action, case_threads, max_parallel_cases)
    case_name = action["Value"]
    unless case_threads.empty?
      alive_threads = case_threads.keys.each.map {|t| t.alive?}.length
      if max_parallel_cases <= alive_threads
        log_debug("Waiting on a free thread for case #{case_name}...")
        case_threads.keys[0].join
        log_debug("Case thread freed up")
      end
    end
    log_debug("Starting new case thread for #{case_name}")
    case_thread = Thread.new do
      run(case_name, get_parent_params(action))
      log_info("Finished parallel-enabled case #{case_name}")
    end
    case_threads[case_thread] = case_name
    return case_threads
  end

  # synchronize any asynchronous/parallel steps
  def sync_steps_handler(action)
    value, time = action["Value"], action["Time"]
    if time
      log_info("Sync: Checking for synchronized step...")
      start = Time.now
      while (Time.now - start) < time
        if File.exist? "sync.txt"
          File.open("sync.txt", "r") {
            |file_data|
            file_lines = file_data.readlines.map(&:chomp)
            file_lines.each do |line|
              if line == value
                log_info("Sync: found sync file")
                return
              end
            end
          }
        end
        sleep 0.5
      end
      log_warn("Sync: Sync file NOT FOUND!")
      return
    else
      log_info("Sync: Creating sync file...")
      File.open("sync.txt", "wb") { |f| f.write value }
    end
    log_info("Sync: Synced step with value: #{value}")
  end

  # synchronize any asynchronous/parallel cases
  def sync_cases_handler(case_threads)
    case_threads.each do |case_thread, case_name|
      case_thread.join
      log_info("Sync: Synced parallel-enabled case #{case_name}")
    end
    log_info("Sync: Finished sync for cases #{case_threads.values}")
  end

  # execute a case only if some condition is true
  def if_handler(action, _case)
    if !action["If_Cases"] || !action["If_Cases"].is_a?(Array)
      raise "If_Cases should be present and should be an Array!"
    end
    if_succeeded = false
    action["If_Cases"].each do |if_case|
      raise "If_Case is not declared in group: #{if_case}" unless if_case.key?("If_Case")
      if_case_name = if_case["If_Case"]
      do_case_name = if_case.key?("Do_Case") ? if_case["Do_Case"] : nil
      begin
        run(if_case_name, get_parent_params(action))
        if_succeeded = true
        if !do_case_name.nil?
          run(do_case_name, get_parent_params(action))
          log_info("Finished case #{do_case_name}, resuming parent case #{_case}")
        else
          log_info("Finished case #{if_case_name}, resuming parent case #{_case}")
        end
        break
      rescue => e
        # will only ever be entered if run() fails, so if if_succeeded -> do_case exists
        raise "The case #{do_case_name} has failed!" if if_succeeded # && !do_case_name.nil?
      end
    end
    if !if_succeeded && action.key?("Else_Case") && !action["Else_Case"].nil?
      else_case_name = action["Else_Case"]
      run(else_case_name, get_parent_params(action))
      log_info("Finished case #{else_case_name}, resuming parent case #{_case}")
    end
  end

  # execute a case several times in a loop
  def loop_handler(action, _case)
    parent_params = get_parent_params(action)
    (0...action["Times"]).each do
      run(action["Case"], parent_params)
    end
    log_info("Finished looping case #{action["Case"]}, resuming parent case #{_case}")
  end

  # record the execution time of some actions
  def timer_handler(action, action_role, start_time)
    if !["start", "end"].include?(action_role)
      log_abort "Unexpected timer role '#{action_role}' - expected 'start' or 'end'!"
    end
    return Time.now if action_role == "start"

    # can only have value 'end' here
    elapsed = Time.now - start_time
    if action["Description"]
      log_info("Total time #{action["Description"]}: #{elapsed}")
    else
      log_info("Total time: #{elapsed}")
    end
    if action["File"]
      file_action = action["Rewrite"] ? "w" : "a+"
      File.open(convert_value(action["File"]), file_action) {
        |f|
        f.write "#{elapsed}"
      }
    end
    return start_time
  end

end

def get_parent_params(action)
  parent_params = {}
  parent_params["Role"] = convert_value(action["Role"]) if action["Role"]
  parent_params["Vars"] = action["Vars"] if action["Vars"]
  return parent_params
end