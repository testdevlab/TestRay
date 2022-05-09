![TestRay Logo](resources/testray_png.png)

# About
TestRay is a Ruby gem used to run YAML-based automation tests, using Selenium and Appium. While originally compatible only with Android, in its current iteration it can also automate iOS, web, Windows and Mac applications - and with multi-platform support!

## Index
1. [Installation](#installation)
2. [TestRay Examples](#examples)
3. [Configuration and Steps](#conf_steps)
4. [Usage](#usage)
5. [Writing Steps](#writing_steps)
6. [Creating Config File for Apps and Devices](#conf_file_app_dev)
7. [Create Test Case](#test_case)
8. [Vars](#vars)
9. [Roles](#roles)
10. [Action Types](#actions)


## <a id="installation"></a>Installation
TestRay has been tested to work on both Mac (Intel/M1) and Windows.

One way to install the framework is by creating a Gemfile with the following content and then running `bundle install`:

<pre>
gem "testray", :git => "https://github.com/testdevlab/TestRay.git"
</pre>

then you can use `bundle install --binstubs` to generate a bin folder with the testray exec and execute it like:

<pre>
./bin/testray -h
</pre>

Another way to install master is to download this project and use `rake install`

[See here for full installation instructions.](./SETUP.md)

If you do not need the full YAML test suite alongside TestRay, and have set up the prerequisites, you can install TestRay on its own like so:
<pre>rake install</pre>

## <a id="examples"></a>TestRay Examples

There is a folder `examples` that contains different use cases for TestRay. The basic one, with most of the possible roles and cases is under `examples/tests` folder. In order to execute this tests you can either download this folder into your project as a template, or directly clone TestRay Project and navigate to the folder:

<pre>
cd examples/tests
testray execute TestAssertsGreaterError
</pre>

In this previous example we are executing `TestAssertsGreaterError` case which is under `examples/tests/cases/case_asserts.yaml`. More about the folder extructure, configuration and steps in the next section.

## <a id="conf_steps"></a>Configuration and Steps

For most actions, TestRay will require a config file. This should exist as `cases/config.yaml`, relative to your current working directory.

Executing tests further requires test files, which should also be placed in the aforementioned `cases` folder.

It is **not** advised to use the `cases` folder of TestRay itself, since that folder is meant for tests to validate TestRay functionality.

## <a id="usage"></a>Usage

Run `testray help` to see available commands. Help can also be called for each command to see available options.

Specifically for execution: To execute a test case called `MyTestCase`, run `testray execute MyTestCase`.

<!-- [See here for a full list of available commands.]() -->

## <a id="writing_steps"></a>Writing Steps

Template for step file:

    <App>:
        Actions:
        - Type: <type>          
          Role: <role>
          Strategy: <locator_strategy>
          Id: <element_id>
          FailCase:
            - Value: <case>
            - ContinueOnFail: <boolean>
        - Type: <type>
          ...

**app** is app which has it's app package and activity in config \
**type** can be click|press|get_attribute|set_attribute|remove_attribute|wait_for|swipe_up|swipe_coord|send_keys|swipe|clear_field (and many more)\
**role** which role executes given step (roles are defined for each device in config) \
**strategy** is appium locator strategy like accessibility_id|id|xpath ... \
**id** is locator for the given strategy

**FailCase** can be specified for a step. This will be executed if *RuntimeError* was encountered while executing step \
*case* is the name of test case that will be executed \
*boolean* value can be true|false which will determine if test execution will continue after failcase execution

One step file includes all needed apps.

## <a id="conf_file_app_dev"></a>Creating Config File for Apps and Devices

Adding Apps configuration:
<pre>
Apps:
  SomeApp:
    Package: com.some.App
    Activity: com.some.App.auth.StartScreenActivity
    Download: https://apkpure.com/someApp-SomeApp/com.some.App
    iOSBundle: com.some.SomeApp
    WinPath: C:\Users\user\AppData\Local\Programs\SomeApp\SomeApp.exe
    UWPAppName: SOMEAPP.1234567890ABC_defghijklmnop!App
    MacAppName: com.someapp
</pre>

This will add all the necessary capabilities to run on iOS, MacOS, Windows and Android

Adding Test Device Configuration:

Selenium Browser (Two roles defined with the same capabilities - desktop1 and desktop2)
<pre>
Devices:
  - role: desktop1,desktop2
    seleniumUrl: http://192.168.1.1:4444/wd/hub/
    capabilities:
      prefs:
          profile.default_content_setting_values.notifications: 2
      chromeOptions:
        args:
          - use-fake-ui-for-media-stream
          - use-fake-device-for-media-stream
          - no-sandbox
          - use-file-for-fake-audio-capture=/home/testdevlab/silence.wav
          - use-file-for-fake-video-capture=/home/testdevlab/video_720.y4m
          - --headless
    browser: chrome
</pre>

Android Browser
<pre>
Devices:
  - role: localMobileBrowser
    platform: Android
    capabilities:
      chromeOptions:
        args:
          - use-fake-ui-for-media-stream
          - use-fake-device-for-media-stream
          - use-file-for-fake-audio-capture=/home/testdevlab/silence.wav
          - no-sandbox
</pre>

Android App
<pre>
Devices:
  - role: androidTest
    platform: Android
</pre>

iOS App/Browser
<pre>
Devices:
  - role: mobileiOS
    platform: iOS
</pre>

MacOS/Windows
<pre>
Devices:
  - role: macLocal
    platform: Mac
  - role: localWindows
    platform: Windows
</pre>


## <a id="test_case"></a>Create Test Case

All the test cases need to be in YAML files called `case_*.yaml` (case_example.yaml), and placed in the `cases` folder in your working directory.

<pre>
MyTestDesktopAndroidApp:
  ParallelRoles: true
  Vars:
    SOME_VAR: value
  Roles:
  - Role: androidTest
    App: SomeApp
  - Role: desktop1
    Capabilities:
      chromeOptions:
        args:
          - use-file-for-fake-audio-capture=/home/testdevlab/audio.wav
          - use-file-for-fake-video-capture=/home/testdevlab/video.y4m
    App: desktop
  - Role: command1
    App: command
  Actions:
    - Type: case
      Value: MyTestDesktopChromeStart
    - Type: sync
    - Type: case
      Value: MyTestJoinAndroidAppDeepLink

MyTestDesktopChromeStart:
  ParallelRoles: true
  Roles:
    - Role: desktop1
      App: desktop
  Actions:
  - Type: navigate
    Value: https://www.SomeApp.com/login/
  - Type: maximize
  - Type: click
    Strategy: xpath
    Condition:
      - Value: 5
        Operation: visible
        Result: true
    Id: //button[text()="Accept Cookies"]
  - Type: send_keys
    Value: $AND_CLI_SOME_VAR$
    Strategy: id
    Id: email

MyTestJoinAndroidAppDeepLink:
  ParallelRoles: true
  Roles:
    - Role: androidTest
      App: SomeApp
  Actions:
  - Type: navigate
    Role: $AND_CLI_USER$
    Value: https://someapp.com/$AND_CLI_LINK$
  - Type: click
    Role: $AND_CLI_USER$
    Strategy: uiautomator
    Id: descriptionContains("JOIN CALL")
</pre>

Here we can see that `Roles` need to be defined for every case, which the roles that will be used for each of them.
You can call `cases` within `cases` like:

<pre>
    - Type: case
      Value: CaseName
</pre>

We can start now with the Basics of TestRay Cases:

## <a id="vars"></a>Vars

Vars are used to share information among cases or define some specific values that are repeated, so in case you need to change them, you can do it from a single point. Also, all the vars are ENV vars, which means they can be accessed from anywhere.

You can assign values for vars in two ways:

1) directly - at the start of a case/set, or under a specific action/case
<pre>
Vars:
  SOME_VAR: value
</pre>
2) grepping the returned value of some action:
<pre>
- Type: get_attribute
  Strategy: xpath
  Id: //input[contains(@value, "http")]
  Greps:
    - var: SOME_VAR
      attr: value
      condition: nempty
      remove: msngr.com/
      match: "msngr.com(.*)"
</pre>
You can then access the vars from anywhere by using the wrapper `$AND_CLI_SOME_VAR$`

The order in which the vars and environments are loaded is shown in this image:

<img src="resources/variable_order.png" alt="Variable Order" width="300"/>

## <a id="roles"></a>Roles

Roles are ALWAYS defined at the begining of the cases. You have to write always the name of the role (which is defined first in config.yaml file) and the application that will run:

<pre>
  Roles:
    - Role: androidTest
      App: SomeApp
</pre>


## <a id="actions"></a>Action Types

## Appium/Selenium

1. [click](#click)
2. [send_keys](#send_keys)
3. [wait_for](#wait_for)
4. [navigate](#navigate)
5. [get_url](#get_url)
6. [get_text](#get_text)
7. [get_attribute](#get_attribute)
8. [context](#context)
9. [get_current_context](#get_current_context)
10. [get_contexts](#get_contexts)
11. [get_source](#get_source)
12. [set_network](#set_network)
13. [scroll_to](#scroll_to)
14. [screenshot](#screenshot)
15. [wait_for_attribute](#wait_for_attribute)
16. [visible_for](#visible_for)
17. [visible_for_not_raise](#visible_for_not_raise)
18. [wait_for_page_to_load](#wait_for_page_to_load)
19. [collection_visible_for](#collection_visible_for)
20. [wait_not_visible](#wait_not_visible)

## Only Browser

1. [clear_field](#clear_field)
2. [set_attribute](#set_attribute)
3. [remove_attribute](#remove_attribute)
4. [switch_window](#switch_window)
5. [switch_frame](#switch_frame)
6. [maximize](#maximize)
7. [minimize](#minimize)
8. [submit](#submit)
9. [click_js](#click_js)
10. [add_cookie](#add_cookie)


## Only Mobile

1. [set_orientation](#set_orientation)
2. [close_app](#close_app)
3. [launch_app](#launch_app)
4. [start_record/end_record](#start_record/end_record)
5. [tap_by_coord](#tap_by_coord)
6. [press](#press)
7. [click_and_hold](#click_and_hold)
8. [swipe_up/swipe_down](#swipe_up/swipe_down)
9. [swipe_elements](#swipe_elements)
10. [swipe_coord](#swipe_coord)
11. [click_coord](#click_coord)
12. [clipboard](#clipboard)
13. [terminate_app](#terminate_app)
14. [notifications](#notifications)
15. [back](#back)

## API

1. [get_call](#get_call)
2. [post_call](#post_call)

## Not Selenium/Appium

1. [command](#command)
2. [write_file](#write_file)
3. [get_timestamp](#get_timestamp)
4. [set_env_var](#set_env_var)
5. [sleep](#sleep)
6. [assert](#assert)
7. [sync](#sync)
8. [operation](#sync)

This is not a type but can be used in different Types as a Validation for the action to happen: `Condition`

9. [Conditions](#condition)

## Appium/Selenium

#### <a id="click"></a>click 

	- Type: click
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  Strategy: id/css/xpath/uiautomator/class_chain/...
	  Id: //some/path
	  NoRaise: false/true (Default - false -> will rise error on fail)

Strategy and Id can by put as a list, in which case it will define a list of elements, and the first one to be clickable will be clicked.
Both lists for Startegy and Id must have the same size (Number of elements):

	- Type: click
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  Strategy: 
	  	- id/css/xpath/uiautomator/class_chain/... (First Strategy goes with the First Id)
		- id/css/xpath/uiautomator/class_chain/... (Second Strategy goes with the Second Id)
	  Id: 
	  	- //some/path
		- //some/path2
	  NoRaise: false/true (Default - false -> will rise error on fail)

It is possible to add conditions, in which case it will do the click depending on the condition to be fullfiled:

	- Type: click
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  Strategy: id/css/xpath/uiautomator/class_chain/...
	  Id: //some/path
	  Condition:
		- Value: 5 (Time in seconds)
			Operation: visible
			Result: true
	  NoRaise: false/true (Default - false -> will rise error on fail)

Check [Conditions](#condition) section for more information.

### <a id="send_keys"></a>send_keys

	- Type: send_keys
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  Strategy: id/css/xpath/uiautomator/class_chain/...
	  Id: //some/path
	  Value: text to send
	  NoRaise: false/true (Default - false -> will rise error on fail)

You can also set different Strategies and Ids as in the `click`  Type, and also you can set [Conditions](#condition).

### <a id="wait_for"></a>wait_for

	- Type: wait_for
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  Strategy: id/css/xpath/uiautomator/class_chain/...
	  Id: //some/path
	  NoRaise: false/true (Default - false -> will rise error on fail)

You can also set different Strategies and Ids as in the `click`  Type, and also you can set [Conditions](#condition).

### <a id="navigate"></a>navigate

	- Type: navigate
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  Value: https://google.com

### <a id="get_url"></a>get_url

	- Type: get_url
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  Greps:
		- var: SOME_VAR
		  condition: nempty (Optional)
		  remove: google.com/ (Optional)
		  match: "google.com(.*)"

Greps explained in `command` Type

### <a id="get_text"></a>get_text

  	- Type: get_text
      Strategy: id/css/xpath/uiautomator/class_chain/predicate
      Id: //div[contains(text(), "http")]
      Condition:
        - Value: 3
          Operation: visible
          Result: true
      Greps:
        - var: LINK
          condition: nempty
          remove: google.com/
          match: "google.com(.*)"
	  NoRaise: false/true (Default - false -> will rise error on fail)

You can also set different Strategies and Ids as in the `click` Type. Greps explained in `command` Type and Condition explained in [Conditions](#condition) Section.

### <a id="get_attribute"></a>get_attribute

  	- Type: get_attribute
      Strategy: id/css/xpath/uiautomator/class_chain/predicate
      Id: //div[contains(text(), "http")]
	  Condition:
        - Value: 3
          Operation: visible
          Result: true
	  Greps:
		- var: SOME_VAR
		  attr: value (Mandatory)
		  condition: nempty (Optional)
		  remove: google.com/ (Optional)
		  match: "google.com(.*)"
	  NoRaise: false/true (Default - false -> will rise error on fail)

You can also set different Strategies and Ids as in the `click` Type. Greps explained in `command` Type and Condition explained in [Conditions](#condition) Section.

### <a id="context"></a>context

	- Type: context
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  Value: context

### <a id="get_current_context"></a>get_current_context
### <a id="get_contexts"></a>get_contexts
### <a id="get_source"></a>get_source
### <a id="set_network"></a>set_network
### <a id="scroll_to"></a>scroll_to
### <a id="screenshot"></a>screenshot
### <a id="wait_for_attribute"></a>wait_for_attribute
### <a id="visible_for"></a>visible_for
### <a id="visible_for_not_raise"></a>visible_for_not_raise
### <a id="wait_for_page_to_load"></a>wait_for_page_to_load
### <a id="collection_visible_for"></a>collection_visible_for
### <a id="wait_not_visible"></a>wait_not_visible

## Only Browser

### <a id="clear_field"></a>clear_field

	- Type: clear_field
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  Strategy: id/css/xpath/uiautomator/class_chain/...
	  Id: //some/path
	  NoRaise: false/true (Default - false -> will rise error on fail)

### <a id="set_attribute"></a>set_attribute

	- Type: set_attribute
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  Strategy: id/css/xpath/uiautomator/class_chain/... 
	  Id: //some/path 
	  Attribute: value
	  Value: something
	  NoRaise: false/true (Default - false -> will rise error on fail)

### <a id="remove_attribute"></a>remove_attribute

	- Type: remove_attribute
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  Strategy: id/css/xpath/uiautomator/class_chain/... 
	  Id: //some/path 
	  Attribute: value
	  Value: something
	  NoRaise: false/true (Default - false -> will rise error on fail)

### <a id="switch_window"></a>switch_window
### <a id="switch_frame"></a>switch_frame
  - Type: switch_frame
    Strategy: css (Only if Value isn't declared)
    Id: "[name='iFrameName']" (Only if Value isn't declared)
    Value: Iframe_ID (Only if Strategy and Id aren't declared)

### <a id="maximize"></a>maximize
### <a id="minimize"></a>minimize
### <a id="submit"></a>submit
### <a id="click_js"></a>click_js
### <a id="add_cookie"></a>add_cookie


## Only Mobile

### <a id="set_orientation"></a>set_orientation (Mobile)

	- Type: set_orientation
      Role: role1
      Value: landscape/portrait

### <a id="close_app"></a>close_app (Mobile)

Closes the app and leaves it running in the background.

	- Type: close_app
      Role: role1

### <a id="launch_app"></a>launch_app (Mobile)

	- Type: launch_app
      Role: role1
      Value: com.android.vending (Optional - Android app package / iOS bundle ID)

### <a id="terminate_app"></a>terminate_app

	- Type: terminate_app
      Role: role1
      Value: com.apple.Preferences (Optional - Android app package / iOS bundle ID)

### <a id="start_record/end_record"></a>start_record/end_record (Mobile)

    - Type: start_record
      Bitrate: 3000000 (Recording Bitrate - optional - Android)
	  Resolution: 1200x900 (Optional - Android)
	  FPS: 30 (Optional - iOS)
	  Video_Type: h264 (Optional - iOS)
	  Video_Quality: medium (Optional - iOS)
      Role: role1
      Time: "180" (Timeout - optional)

You must use `end_record` after this previous method.

    - Type: end_record
      Value: video.mp4
      Height: $AND_CLI_SCREEN_HEIGHT$ (Optional - crops the height to the specified value)
      Width: $AND_CLI_SCREEN_WIDTH$ (Optional - crops the width to the specified value)
      Role: role1

### <a id="tap_by_coord"></a>tap_by_coord (Works the same as click)

It works the same as click, but it will get the coordinates of the element internally and then click on it, but the labels and options that you can use are exactly the same. Refer to `click` for more information.

	- Type: tap_by_coord
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  Strategy: id/css/xpath/uiautomator/class_chain/...
	  Id: //some/path
	  NoRaise: false/true (Default - false -> will rise error on fail)

### <a id="press"></a>press (Works simillar as click)

It works simillar as click, but it will use Appium Actions of the element internally. The labels and options that you can use are exactly the same. Refer to `click` for more information.

### <a id="click_and_hold"></a>click_and_hold

It works simillar as click, but it holds the pressing. The labels and options that you can use are exactly the same. Refer to `click` for more information.

### <a id="swipe_up/swipe_down"></a>swipe_up/swipe_down (Mobile)

	- Type: swipe_up/swipe_down
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  Strategy: id/css/xpath/uiautomator/class_chain/... (Element from where to start the swipe)
	  Id: //some/path (Element from where to start the swipe)
	  NoRaise: false/true (Default - false -> will rise error on fail)

### <a id="swipe_elements"></a>swipe_elements (Mobile)

	- Type: swipe_elements
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  Element1: (From element)
		Strategy: id/css/xpath/uiautomator/class_chain/... (Element from where to start the swipe)
		Id: //some/path (Element from where to start the swipe)
	  Element2: (To element)
		Strategy: id/css/xpath/uiautomator/class_chain/... (Element from where to start the swipe)
		Id: //some/path (Element from where to start the swipe)

### <a id="swipe_coord"></a>swipe_coord (Mobile)

	- Type: swipe_coord
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  StartX: 100
	  StartY: 200
	  EndX: 300
	  EndY: 400

### <a id="click_coord"></a>click_coord (Mobile)

	- Type: click_coord
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  X: 100
	  Y: 200

if `X` and `Y` are not provided then middle of the screen is clicked.

### <a id="clipboard"></a>clipboard
### <a id="notifications"></a>notifications
### <a id="back"></a>back


## API

### <a id="get_call"></a>get_call

	- Type: get_call
      Role: role1
      Url: http://url.com
      Greps:
        - match: access_token
          var: TOKEN
	  Asserts: (Optional)
		- Type: code
          Value: 200

### <a id="post_call"></a>post_call

	- Type: post_call
      Role: role1
      Url: http://url.com
	  Body: { "data": "data" }
      Greps:
        - match: access_token
          var: TOKEN
	  Asserts: (Optional)
		- Type: code
          Value: 200

You can also get files with post_call:

	- Type: post_call
      Role: role1
      Url: http://url.com
	  Body: { "file": "./file.wav" }
	  File_Response: $AND_CLI_folderPath$/file.wav

You can also send multiple files:

    - Type: post_call
      Role: command1
      Url: http://url.com
      Body:
        - Multipart: true
          File: $AND_CLI_folderPath$/$AND_CLI_FILE_NAME$
        - Multipart: true
          File: $AND_CLI_folderPath$/file2.txt


## Not Selenium/Appium

### <a id="command"></a>command

	- Type: command
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  Value: echo Hello
	  Raise: true/false (Raises an error if the command fails - Default false)
	  Detach: true/false (Detaches the command line from main thread. Can't be used with Raise. Default false)

You can use Greps using regex to get specific values from the input command or output:

	- Type: command
	  Role: role1 (Optional. if not specified will use the first one defined in the case Roles)
	  Value: echo Hello
	  Greps:
		- var: SOME_VAR
		  condition: nempty (Optional)
		  remove: google.com/ (Optional)
		  match: "google.com(.*)"

You can access any var throgout the code by using the wrapper `$AND_CLI_*$`, in this case -> `$AND_CLI_SOME_VAR$`


### <a id="write_file"></a>write_file
### <a id="get_timestamp"></a>get_timestamp
### <a id="set_env_var"></a>set_env_var
### <a id="sleep"></a>sleep
### <a id="assert"></a>assert

### <a id="operation"></a>operation

There are a lot of operations, look at https://github.com/project-eutopia/keisan

    - Type: operation
      Operation: 3+5*3+(3+5)**2+4/2
      ExpectedResult: 84 # (Optional)
      ResultVar: Result # (Optional) You can later use the var like $AND_CLI_Result$ since Result becomes an Environment Variable

Operation examples:

      Operation: "'textlength'.size"
      Operation: "[1,3,5].max"
      Operation: "[1,3,5].min"
      Operation: "1 > 0"
      Operation: "1 < 0"
      Operation: "'Concatenate' + ' text'"

### <a id="condition"></a>Conditions

  - Type: wait_for/click/send_keys/press/... Anything that calls an element by `Strategy:Id` labels
    Strategy: id/css/xpath/uiautomator/class_chain/predicate
    Id: //div[contains(text(), "http")]
    Condition:
      - Value: 5 # Time in seconds for the condition to fullfil (or not)
        Result: true/false # If you expect the condition to be true or false
        Operation: visible/eq/neq/visible_for
        Raise: true/false # If you want the condition to raise an error


