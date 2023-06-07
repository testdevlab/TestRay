# iOS Device Setup for A/V Automation
This document describes the steps to set up a real iOS device for automation with TestRay.
It is assumed that you have already completed the prerequisite installations described in the TestRay setup - if not, please see [this document](./SETUP.md).

These instructions were tested on an M1 Mac running Xcode 12.4 and Appium 1.20.2, with an iPhone 6s running iOS 14.4. Also, tested with M1 mac using Appium 2.0 beta.

## Core Setup
First and most important thing - you need an Apple ID, which will be used continuously. This Apple ID should NOT already be actively used for iOS automation on another Mac, because running tests builds a developer profile specific to that Mac, and invalidates the profiles on any other Macs using that account (until they are rebuilt again).

1. On computer: launch Xcode, then open Xcode -> Preferences -> Accounts -> + -> Continue and add your Apple ID credentials

2. Connect your iDevice to the computer and trust it

3. On computer: in Xcode, open Window -> Devices and Simulators and check that your iDevice is present

        If you see an error about an incompatible iOS version, update your iDevice

4. On iDevice: enable necessary settings

        Settings -> Developer -> Enable UI Automation -> turn ON
        Settings -> Safari -> Advanced -> Remote Automation -> turn ON (option may not be present)
        Settings -> Safari -> Advanced -> Web Inspector -> turn ON
        Settings -> Display & Brightness -> Auto-Lock -> set to Never (because the device needs to be unlocked to run tests)
        Open Safari and enable Private Browsing Mode (this ensures that state will not be saved between tests)

5. On computer: in terminal, run `xcrun xctrace list devices`
        The command will return a bunch of installed iOS devices. Most of these are simulators, but the first ones on the list should be real devices, and your iDevice name should be among them.
        The entry will also include the device's OS version and UDID (identification string) - you do not need them if you only want to run tests on this device, but if you plan to also develop them, note down the device name and UDID!
6. In Appium 2.x the server and drivers are separated, so you won't find WDA sources in the same package where the server is installed. WDA sources only get fetched as soon as XCUITest driver is installed using the server CLI, Do `appium driver install xcuitest`, run the following: `echo "$(dirname "$(find "$HOME/.appium" -name WebDriverAgent.xcodeproj)")"` and then switch the directory on the output.
7. Run `mkdir -p Resources/WebDriverAgent.bundle`
8. Open the Xcode project by running `open WebDriverAgent.xcodeproj`
9. In the left side panel, click on WebDriverAgent at the top
10. In the middle-left section, under Targets, select WebDriverAgentLib. In the middle section, switch to the Signing & Capabilities tab, and change Team to the one for your Apple ID
11. Repeat Step 10 for the WebDriverAgentRunner target. However, now it should return an error:
12. Still under WebDriverAgentRunner, switch to the Build Settings tab. In the Packaging section, find Product Bundle Identifier (it should be `com.facebook.WebDriverAgentRunner`), and change the facebook part to something unique, for example `com.testray26.WebDriverAgentRunner`. Again, it should be completely unique, otherwise you will break the tests of other people using the same identifier! Then switch back to the Signing & Capabilities tab and confirm that no errors are shown.
13. Repeat Step 10 once more, for the IntegrationApp target. You should also get the same error as in Step 11.
14. Repeat Step 12 for the IntegrationApp target. Your new bundle identifier here should be something like `com.testray26.IntegrationApp`.
15. Still under IntegrationApp, switch to the Info tab. Find Bundle identifier (it should be `com.facebook.wda.integrationApp`) and change it to the bundle identifier you set in Step 14. Make sure to check your capitalization and also change `integrationApp` to `IntegrationApp`!
16. Select Product -> Scheme -> IntegrationApp
17. In the top left, select your iDevice as the target
18. Install the app with Product -> Run
        During the build step, you may receive a prompt from codesign - enter your Mac account password (which may be different from your developer account password!) and press Always Allow. Repeat this several times if necessary.
        Eventually the build step should succeed, the IntegrationApp should get installed on the iDevice, but the test should fail - this is expected!
19. On iDevice: Settings -> General -> Device Management -> Apple Development -> Trust "Apple Development" -> Trust
20. Back in Xcode: select Product -> Scheme -> WebDriverAgentRunner
21. Run Product -> Test. The WebDriverAgentRunner-Runner app should get installed, and the agent should be running, like so:
22. Press the stop button to end the execution.


That’s it! You can now use iOS devices in tests by selecting a device role with the platform: iOS parameter, and adding the role to your test case.
P.S. You may be wondering why two applications are needed. The actual automation part is done by WebDriverAgentRunner-Runner, while IntegrationApp is technically not even necessary. However, if you ever encounter errors with the WebDriverAgentRunner-Runner, it will crash and automatically get uninstalled, and if you try to install it again without already having IntegrationApp on the device, you will have to repeat Step 19, every time. And this step requires physical access to the device, which makes remote testing impossible. In order to avoid this, we install IntegrationApp, so that if WebDriverAgentRunner-Runner crashes, the trust certificate will not be revoked, and a remote reinstall would still be possible.


## Advanced Setup


TestRay is additionally able to support two specific actions for iOS:
- retrieving the version number of any third-party app
- taking a screenshot

If your tests do not require either of these actions, you can freely skip this part.

The two above functionalities in TestRay are provided by `ideviceinstaller` and `idevicescreenshot`, respectively. However, by default `ideviceinstaller` returns the internal app build number (which differs from the App Store version), whereas the current release version 1.3.0 of `idevicescreenshot` does not fully support iOS 14+. We will fix both of these issues.

### Version number retrieval
The goal here is to download the source code and make a couple modifications before installing it.
1. Set up the dependencies - install `ideviceinstaller` through Homebrew by running `brew install ideviceinstaller`
2. Uninstall `ideviceinstaller` by running `brew uninstall ideviceinstaller`
3. Download the `ideviceinstaller` source code: `git clone https://github.com/libimobiledevice/ideviceinstaller.git`
4. Open `src/ideviceinstaller.c` in your favorite text editor (like VS Code)
5. You need to change 3 lines of code, by just replacing `CFBundleVersion` with `CFBundleShortVersionString`:

        Line 127: CFBundleVersion -> CFBundleShortVersionString
        Line 142: CFBundleVersion -> CFBundleShortVersionString
        Line 784: CFBundleVersion -> CFBundleShortVersionString

6. Save the file
7. In the terminal, open the `ideviceinstaller` directory
8. Run the following 3 commands:

    a) `./autogen.sh`

	    You may receive the following error:
	    
	    	Package 'openssl', required by 'libimobiledevice-1.0', not found
	    
	    The fix now depends on where your Homebrew is installed - run where brew.
		If you get /usr/local/bin/brew, run these:

		    export PATH="/usr/local/opt/openssl/bin:$PATH"
		    export LD_LIBRARY_PATH="/usr/local/opt/openssl/lib:$LD_LIBRARY_PATH"
		    export CPATH="/usr/local/opt/openssl/include:$CPATH"
		    export LIBRARY_PATH="/usr/local/opt/openssl/lib:$LIBRARY_PATH"
		    export PKG_CONFIG_PATH="/usr/local/opt/openssl/lib/pkgconfig"

		If you get /opt/homebrew/bin/brew, run these:

		    export PATH="/opt/homebrew/opt/openssl/bin:$PATH"
		    export LD_LIBRARY_PATH="/opt/homebrew/opt/openssl/lib:$LD_LIBRARY_PATH"
		    export CPATH="/opt/homebrew/opt/openssl/include:$CPATH"
		    export LIBRARY_PATH="/opt/homebrew/opt/openssl/lib:$LIBRARY_PATH"
		    export PKG_CONFIG_PATH="/opt/homebrew/opt/openssl/lib/pkgconfig"

	    Then run the autogen command again, it should work fine.

    b) `make`
    
    c) `sudo make install` (enter your password if required)
9. Confirm that `ideviceinstaller` was successfully installed by running `ideviceinstaller -v` - should be 1.1.2


### Taking a screenshot
The goal here is to download a newer version of `libimobiledevice`, <u>but not the very latest one</u>, as it includes some breaking changes.
1. Download the source code of `libimobiledevice`, from the revision before the breaking changes: https://github.com/libimobiledevice/libimobiledevice/archive/24abbb9450c723617e10a6843978aa04a576523e.zip
2. Unzip the archive
3. In the terminal, open the `libimobiledevice-24abbb9450c723617e10a6843978aa04a576523e` directory
4. Run the following 3 commands:

    a) `./autogen.sh`

	    You may receive the following error:
	    
	    	configure: error: OpenSSL support explicitly requested but OpenSSL could not be found
	    
	    The fix now depends on where your Homebrew is installed - run where brew.
		If you get /usr/local/bin/brew, run these:

		    export PATH="/usr/local/opt/openssl/bin:$PATH"
		    export PKG_CONFIG_PATH="/usr/local/opt/openssl/lib/pkgconfig"

		If you get /opt/homebrew/bin/brew, run these:

		    export PATH="/opt/homebrew/opt/openssl/bin:$PATH"
		    export PKG_CONFIG_PATH="/opt/homebrew/opt/openssl/lib/pkgconfig"

	    Then run the autogen command again, it should work fine.

    b) `make`
    
    c) `sudo make install` (enter your password if required)
9. Confirm that the correct `idevicescreenshot` was successfully installed by running `idevicescreenshot -v` - should be 1.3.1


