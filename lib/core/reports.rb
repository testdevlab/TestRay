require 'warning'
require 'fileutils'
require 'report_builder'
Warning.ignore(/Passing/)

module Reports
  @@report = {
      "CASES" => {},
      "ERRORS" => {},
      "TOTAL_CASES" => [],
      "CASE_LOGS" => {}
  }
  @@cucumber_report = nil

  def report_error(message)
    _case = message.match(/case '(\S+)'/)[1] if  message.match(/case '(\S+)'/)
    screenshot_path = message.match(/Screenshot: (.*)/)[1] if message.match(/Screenshot: (.*)/)
    if _case && !_case.empty?
      @@report["ERRORS"][_case] = [] unless @@report["ERRORS"][_case]
      @@report["ERRORS"][_case].append(
      {"error_message" => message, "screenshot_path" => screenshot_path}) 
    end
  end

  def report_case(message)
    _case = message.match(/Case Execution for '(.*)'/)[1] if  message.match(/Case Execution for '(.*)'/)
    @@report["TOTAL_CASES"].append _case if _case
  end

  def report_step(message, main_case, id)
    @@report["CASES"][main_case+id] = {} unless @@report["CASES"][main_case+id]
    @@report["CASES"][main_case+id]["passed"] = [] unless @@report["CASES"][main_case+id]["passed"]
    @@report["CASES"][main_case+id]["passed"].append({"step" => message})
  end

  def report_step_fail(_case, main_case, id, error_message)
    @@report["CASES"][main_case+id] = {} unless @@report["CASES"][main_case+id]
    @@report["CASES"][main_case+id]["failed"] = [] unless @@report["CASES"][main_case+id]["fail_steps"]
    screenshot_path = error_message.match(/Screenshot: (.*)/)[1] if error_message.match(/Screenshot: (.*)/)
    @@report["CASES"][main_case+id]["failed"].append(
      {"step" => _case, "error_message" => error_message, "screenshot_path" => screenshot_path})
  end

  def set_case_log_report(_case, path)
    @@report["CASE_LOGS"][_case] = path
  end
  
  # process_report_cucumber() Parses the @@report var into cucumber json format
  def process_report_cucumber()
    cucumber_report = []
    @@report["CASES"].each do |main_case_id, main_case_info|
      main_case = main_case_id.match(/(.*)\$.*\$/)[1]
      cucumber_report_s = {
      "description" => main_case, # Case File Description
      "keyword" => main_case, # Case File Keywords
      "name" => main_case,
      "id" => main_case_id, # Case File ID = Relative Path
      "tags" => [], # Case File Tags
      "uri" => main_case_id, # Case File
      "elements" => []
      }
      # GET STEPS
      case_info = nil
      steps_cucumber = []
      case_file = find_case_file(main_case)
      # GETTING CASE LOGS FROM @@report TO INCLUDE THEM IN CUCUMBER REPORT
      main_case_info.each do |step_type, steps_report|
        # step_type CAN BE failed/succeed FOR NOW, BUT MIGHT INCREASE TO warn/others
        steps_report.each do |step|
          keyword, step_description = "Then ", ""
          if step["error_message"]
            # ERROR STEPS DO NOT HAVE GHERKIN PREFIX
            step_description = keyword + step["step"] if step["step"]
          else
            step_description = step["step"]
            if step_description.match(/\w+ /)
              keyword = step_description.match(/\w+ /)[0] 
            end
          end
          begin
           step_description.slice! keyword
          rescue => e
            step_description.dup.slice! keyword
          end
          # GETS MAIN CASE INFO: FILE AND LINE WHERE IT START, LINE WHERE THE STEP IS CALLED
          case_info = get_case_info(main_case, case_file, step_description)
          # GETS STEP CASE INFO: FILE AND LINE WHERE IT START
          step_info = get_case_info(step_description, find_case_file(step_description))
          data = _convert_into_cucumber_emb(step)
          steps_cucumber.append(
            {
              "arguments" => [],
              "keyword" => keyword,
              "embeddings" => data,
              "line" => case_info["step_line"].to_i,
              "name" => step_description,
              "match" => {
              "location" => "#{step_info["case_file"]}:#{step_info["case_line"]}"
              },
              "result" => {
              "status" => step_type,
              "error_message" => step["error_message"],
              "duration" => 0
              }
            }
          )
        end
      end
      # ADD STEPS INFO FROM @@report
      cucumber_report_s["elements"].append(
        {
          "id" => main_case,
          "keyword" => "Scenario",
          "line" => case_info["case_line"],
          "name" => main_case,
          "tags" => [], # Case Tags,
          "type" => "scenario",
          "steps" => steps_cucumber
        }
      )
      # APPEND CUCUMBER SCENARIO TO THE LIST OF CASES RAN
      cucumber_report.append(cucumber_report_s)
    end
    @@cucumber_report = cucumber_report
  end

  # generate_report() Generates the JSON file under Reports/logs/*.json
  def generate_report(report_type, file_name)
    jsonfile_path = ""
    if report_type == "testray"
        jsonfile_path = File.join(Dir.pwd, "Reports", "logs", "#{file_name}.json")
        File.open(jsonfile_path, "w+") { |f| f.write(@@report.to_json) }
    elsif report_type == "cucumber"
        jsonfile_path = File.join(Dir.pwd, "Reports", "logs", "cucumber_#{file_name}.json")
        File.open(jsonfile_path, "w+") { |f| f.write(process_report_cucumber().to_json) }
    end
    #generates html report with report_builder gem. Report is saved on the Reports/logs directory
    options = {
      input_path: jsonfile_path,
      report_path: File.join(Dir.pwd, "Reports", "logs", "cucumber_#{file_name}"),
      report_types: ['html'],
      report_title: file_name,
    }  
    ReportBuilder.build_report options

    return jsonfile_path
  end
end

def _convert_into_cucumber_emb(data)
  embeddings = []
  return embeddings unless data || data["screenshot_path"]
  img_b64 = nil
  if data["screenshot_path"] && File.exist?(data["screenshot_path"])
    File.open(data["screenshot_path"], 'rb') do |img|
        img_b64 = Base64.strict_encode64(img.read)
    end
    embedding = {
        "media" => {
            "type" => "image/png"
        },
        "mime_type" => "image/png",
        "data" => img_b64
    }
    embeddings.append(embedding)
  end

  return embeddings
end
