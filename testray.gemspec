lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "version"

Gem::Specification.new do |spec|
  spec.name          = "testray"
  spec.version       = TestRay::VERSION
  spec.authors       = ["Alvaro Laserna","Arnis Gustins"]
  spec.email         = ["alvaro.lasernalopez@testdevlab.com","arnis.gustins@testdevlab.com"]

  spec.summary       = "Ruby CLI gem containing appium/selenium scripts."
  spec.homepage      = "https://github.com/testdevlab/TestRay"

  spec.metadata["allowed_push_host"] = "http://dont-push-this-gem-anywhere.com'"

  spec.files         = Dir['lib/**/*.rb']
  spec.bindir        = "bin"
  spec.executables   = ["testray"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0.6"

  spec.add_runtime_dependency "thor"
  spec.add_runtime_dependency "nokogiri"
  spec.add_runtime_dependency "appium_lib"
  spec.add_runtime_dependency "httparty"
  spec.add_runtime_dependency "json"
  spec.add_runtime_dependency "rest-client"
  spec.add_runtime_dependency "selenium-webdriver", "3.142.7"
  spec.add_runtime_dependency 'screen-recorder', "1.4.0"
  spec.add_runtime_dependency "colorize"
  spec.add_runtime_dependency "keisan"
  spec.add_runtime_dependency "ffi"
  spec.add_runtime_dependency "report_builder"
  spec.add_runtime_dependency "warning"
end
