require 'colorize'
require 'fileutils'

module PLogger
  def log_info(message, no_date=false, _print=false)
  _log(message, "INFO", :light_blue, no_date, _print)
  end

  def log_debug(message, no_date=false, _print=false)
    _log(message, "DEBUG", :cyan, no_date, _print)
  end

  def log_error(message, no_date=false, _print=false)
    _log(message, "ERROR", :red, no_date, _print)
    report_error(message)
  end

  def log_abort(message, no_date=false, _print=false)
    _log(message, "ERROR", :red, no_date, _print)
    abort("")
  end

  def log_warn(message, no_date=false, _print=false)
    _log(message, "WARN", :yellow, no_date, _print)
  end

  def log_case(message, no_date=false)
    _log_dividers(message, "INFO", :green, no_date)
    report_case(message)
  end

  def logger_step(message, main_case, id)
    log_level, log_file = _load_log_env_vars
    _write_to_log_file(log_file, message+"\n")
    report_step(message, main_case, id)
    puts message.green
  end

  def logger_step_fail(case_step, main_case, id, error_message)
    log_level, log_file = _load_log_env_vars
    _write_to_log_file(log_file, case_step+"\n")
    report_step_fail(case_step, main_case, id, error_message)
    puts case_step.red
  end

  def log_case_error(message, no_date=false)
    _log_dividers(message, "ERROR", :red, no_date)
  end

  def log_case_warn(message, no_date=false)
    _log_dividers(message, "WARN", :yellow, no_date)
  end
end

def _load_log_env_vars()
  log_level_array = ["ERROR", "WARN", "INFO", "DEBUG"]
  log_level = ENV.key?("LOG_LEVEL") ? ENV["LOG_LEVEL"].upcase : "INFO"
  log_file = ENV.key?("LOG_FILE") ? ENV["LOG_FILE"] : ""
  if !log_level_array.include?(log_level)
    log_abort "Unknown log level '#{log_level}'! Expected one of #{log_level_array}"
  end
  return log_level, log_file
end

def _log(message, level, color, no_date=false, _print=false)
  log_level_array = ["ERROR", "WARN", "INFO", "DEBUG"]
  time = Time.now.strftime("%Y%m%d-%H%M%S.%L")
  log_level, log_file = _load_log_env_vars
  if log_level_array.index(level) <= log_level_array.index(log_level)
    _put_and_write_file(log_file, level, time, message, color, no_date, _print)
  elsif log_file != ""
    logfile_message = "[#{level}] [#{time}]: #{message}\n"
    _write_to_log_file(log_file, logfile_message)
  end
end

def _log_dividers(message, level, color, no_date=false)
  log_level, log_file = _load_log_env_vars
  time = Time.now.strftime("%Y%m%d-%H%M%S.%L")
  line_length = "[#{level}] [#{time}]: #{message}".length > 100 ? message.length : 80
  _put_and_write_file(log_file, level, time, ("="*80), color, true)
  if message.is_a? Array
    for m in message do
      _put_and_write_file(log_file, level, time, m, color)
    end
  elsif no_date
    puts "#{message}"
  else
    _put_and_write_file(log_file, level, time, message, color)
  end
  _put_and_write_file(log_file, level, time, ("="*80), color, true)
end

def _put_and_write_file(log_file, level, time, message, color, no_date=false, _print=false)
  if no_date
    stdout_message = message.colorize(color)
    logfile_message = "#{message}\n"
  else
    stdout_message = "[#{level}] [#{time}]:".colorize(color) + " #{message}"
    logfile_message = "[#{level}] [#{time}]: #{message}\n"
  end

  if _print
    print(stdout_message)
  else
    puts stdout_message
  end
  _write_to_log_file(log_file, logfile_message) if log_file != ""
end

def _write_to_log_file(log_file, message)
  logfile_folder = File.join(Dir.pwd, "Reports", "logs")
  FileUtils.mkdir_p(logfile_folder) unless Dir.exist? logfile_folder
  logfile_path = File.join(logfile_folder, log_file)
  File.open(logfile_path, "a+") { |f| f.write(message) }
end