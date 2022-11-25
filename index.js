var reporter = require('cucumber-html-reporter');

process.argv.forEach(function (val, index, array) {
    if (index === 2) {
        json_file = val
    }
  });

var options = {
        theme: 'bootstrap',
        jsonFile: json_file,
        output: 'cucumber_report.html',
        reportSuiteAsScenarios: true,
        scenarioTimestamp: true,
        launchReport: true,
        metadata: {
            "Executed": "Remote"
        }
    };

    reporter.generate(options);