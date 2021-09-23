# TestRay Setup - Overview

This document aims to describe the full setup procedure for TestRay, in three sections:

1. Installing prerequisites for TestRay
2. Installing TestRay
3. Installing optional prerequisites for specific test platforms

(This is because TestRay is partially modular - you do not need to install software for platforms that you do not need to automate.)
Installations are provided either as a link, or as a command that should be run in the terminal (or PowerShell on Windows).
Also note that some steps differ depending on the computer on which you want to install TestRay (Windows or Mac). In order to distinguish these, icons will be used:

    ⊞ - this indicates a step that is specific to installations on Windows
    ⌘ - this indicates a step that is specific to installations on Mac

## Prerequisites: TestRay

First you need to install some common prerequisites, regardless of the platform you want to test.

### Core

    ⌘ Homebrew: https://brew.sh/
        After installation: echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        Check that brew is installed by opening a new terminal window and running brew -v
    ⌘ Optional but suggested for convenience
        wget: brew install wget
        oh-my-zsh: sh -c "$(wget https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)"
        iTerm2: brew install --cask iterm2
        You can now use iTerm2 as a substitute for the terminal.
        Visual Studio Code: https://code.visualstudio.com/
    Java 11

    Only for M1 macs: You may be prompted to install Rosetta, install that first

    After installation you need to add the path for the JAVA_HOME environmental variable:

    ⌘ nano ~/.zshrc -> scroll to the bottom and paste the following 3 lines:

        export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-11.0.10.jdk/Contents/Home
        export PATH=$PATH:$JAVA_HOME
        export PATH=$PATH:$JAVA_HOME/bin

        Save and exit nano with Ctrl+X -> Y
    ⊞ Start menu -> type 'path' -> Edit the system environment variables -> Environment Variables… -> section System variables -> New
        Variable name: JAVA_HOME
        Variable value: C:\Program Files\Java\jdk-11.0.10
        Save with OK -> OK -> OK

        Check that Java is installed by opening a new terminal/PowerShell window and running java -version

    Node.js: https://nodejs.org/en/ (LTS version is sufficient)
        Check that Node.js (specifically, npm) is installed by opening a new terminal/Powershell window and running npm -v
        Appium: npm install -g appium
        ⌘ If you receive an error about permission denied:
            In Finder, open /usr/local/lib, and find the node_modules folder
            Right-click it and select Get Info
            At the bottom of the new window there should be a Sharing & Permissions menu, open it
            Grant ‘everyone’ permission to Read & Write. You may need to open the lock in the bottom right corner to do this
            Repeat the above steps for the bin folder inside /usr/local
            After the permissions are granted, run the install command again
            Check that Appium is installed by opening a new terminal/Powershell window and running appium -v
        ⊞ PowerShell may complain that running scripts is disabled - fix it like so:
            Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -> Y
    Ruby 2.7 (we have had issues with Ruby 3.0)
        ⊞ https://github.com/oneclick/rubyinstaller2/releases/download/RubyInstaller-2.7.2-1/rubyinstaller-devkit-2.7.2-1-x64.exe
        ⌘ Install gnupg -> rvm -> Ruby:
    brew install gnupg
        gpg --keyserver hkp://ipv4.pool.sks-keyservers.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
        \curl -sSL https://get.rvm.io | bash -s stable
        Check that rvm is installed by opening a new terminal/Powershell window and running rvm -v
        Only for M1 macs:
            export PKG_CONFIG_PATH="/opt/homebrew/opt/libffi/lib/pkgconfig"
            LDFLAGS="-L/opt/homebrew/opt/libffi/lib" CPPFLAGS="-I/opt/homebrew/opt/libffi/include" rvm install 2.7.1
        Only for Intel macs: rvm install 2.7.1
            Check that Ruby is installed by opening a new terminal/Powershell window and running ruby -v
        ⊞ Additional configuration:
            gem uninstall eventmachine
            gem install eventmachine --platform ruby

### Video Analysis

Skip this section if you do not need to do video analysis.
ffmpeg

        ⌘ brew install ffmpeg
        ⊞ https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip
            Make a folder in your user directory called av-applications/ffmpeg
            Open the zip file and move all the contents (directories bin/doc/presets) to the new folder
            Start menu -> type 'path' -> Edit the system environment variables -> Environment Variables… -> section User variables -> select Path -> Edit -> New
            Paste C:\Users\[your username]\av-applications\ffmpeg\bin
            Save with OK -> OK -> OK
            Check that ffmpeg is installed by opening a new terminal/Powershell window and running ffmpeg -version
        If you plan to use ffmpeg to record the computer screen and launch TestRay using a CI tool (like TeamCity or Jenkins), this action may get stuck. One solution is to additionally install Java 8 and temporarily delete the Java 11 folder when registering the computer with the CI tool.

### Audio Analysis

Skip this section if you do not need to do audio analysis.
sox

        ⌘ brew install sox
        ⊞ https://sourceforge.net/projects/sox/files/sox/14.4.2/sox-14.4.2-win32.exe
            Start menu -> type 'path' -> Edit the system environment variables -> Environment Variables… -> section System variables -> select Path -> Edit -> New
            Paste C:\Program Files (x86)\sox-14-4-2
            Save with OK -> OK -> OK
            Unfortunately, unlike the Mac version, the Windows version of sox does not include handling for .mp3 files, which you may need for spectrogram generation. You can add this support with the following steps:
            Download the two files at https://drive.google.com/drive/folders/1FipUjNGpzHaWgimstxjA7YcE6NmxpLVr
            Paste the files in the sox install directory (C:\Program Files (x86)\sox-14-4-2)
            Check that sox is installed by opening a new terminal/Powershell window and running sox --version

### Network Analysis

Skip this section if you do not need to do network analysis.
Wireshark:

        ⌘ brew install --cask wireshark
            nano ~/.zshrc -> scroll to the bottom and paste the following:
            export PATH=$PATH:/Applications/Wireshark.app/Contents/MacOS/
            Save and exit nano with Ctrl+X -> Y
        ⊞ https://www.wireshark.org/#download
            Start menu -> type 'path' -> Edit the system environment variables -> Environment Variables… -> section System variables -> select Path -> Edit -> New
            Paste C:\Program Files\Wireshark
            Save with OK -> OK -> OK
            Check that Wireshark (specifically, tshark) is installed by opening a new terminal/Powershell window and running tshark -v

## Installing TestRay

You can clone this project and the use:

        rake install

## Prerequisites: Test Platforms

Now you can install optional prerequisites, depending on your tested target platform.

### Running Web Tests

Chrome - https://www.google.com/chrome/
Other Chromium-based browsers are probably fine too, but have not been tested

chromedriver

    ⌘ brew install --cask chromedriver
    ⊞ https://chromedriver.chromium.org/downloads - select depending on your Chrome version

        Make a folder in your user directory called av-applications (if not already present)
        Open the zip file and move chromedriver.exe to the new folder
        Start menu -> type 'path' -> Edit the system environment variables -> Environment Variables… -> section User variables -> select Path -> Edit -> New
        Paste C:\Users\[your username]\av-applications
        Save with OK -> OK -> OK
        Check that chromedriver is installed by opening a new terminal/Powershell window and running chromedriver -v

    ⌘ You may receive a warning that the developer cannot be verified, press Cancel:

        Open System Preferences -> Security & Privacy -> General -> Allow Anyway
        Rerun the previous command - a new warning should pop up. Press Open and the command should execute

#### Running Android Tests

Android Studio - https://developer.android.com/studio

    ⌘ After installing and opening the app, it will open a Setup Wizard

        Select Custom install type
        In JDK Location, click the dropdown and select JAVA_HOME (version 11 which you installed previously)
        In SDK Components, ensure that Android SDK and the API are checked. Intel HAXM and Android Virtual Device can be unchecked
        Proceed with the installation
        After everything is done, close Android Studio and add the necessary paths:
        nano ~/.zshrc -> scroll to the bottom and paste the following 2 lines:
        export ANDROID_HOME=~/Library/Android/sdk
        export PATH=$PATH:$ANDROID_HOME/platform-tools
        Save and exit nano with Ctrl+X -> Y

    ⊞ During the installation, you can uncheck Android Virtual Device to save space

        After the installation, add the necessary paths
        Start menu -> type 'path' -> Edit the system environment variables -> Environment Variables… -> section User variables -> New
        Variable name: ANDROID_HOME
        Variable value: C:\Users\[your username]\AppData\Local\Android\Sdk
        Save with OK
        Under section User variables -> select Path -> Edit -> New, paste %ANDROID_HOME%\platform-tools
        Save with OK -> OK -> OK
        Check that the platform tools (specifically, adb) are installed by opening a new terminal/Powershell window and running adb --version
        Check that the TestRay integration works by running testray android list_devices (inside the av-automation-tests directory)
        Setting up a real Android device is simple:
        On the phone, enable USB debugging:
        Check that developer options are available (should be somewhere in Advanced options, next to Accessibility) - if not, go into About phone and tap on the build number seven times
        In Developer options, enable USB Debugging. It is also suggested to enable Prevent sleeping while charging or its equivalent
        Physically connect the mobile device to the computer. The phone will ask you for permissions - allow them
        Run adb devices - you should see the connected device and its UDID (identification number/string), for example, 1cd982880d027ece. The device should now also show up if you run testray android list_devices.
        If you require the phone to be connected over the network:
        adb -s <UDID> tcpip 5555
        adb connect <phone IP>:5555, for example, adb connect 192.168.0.1:5555
        Unplug the phone from the computer
        adb devices - the previous UDID should now be replaced with the IP of the phone

#### Running iOS Tests

Note that iOS automation is only possible on macOS - TestRay will return an error if you try to run iOS commands on Windows.
Xcode - download from the Mac App Store (requires Apple ID; can log out after installation)

Afterwards open Xcode->Preferences->Locations, and under Command Line Tools, ensure that the Xcode instance is selected
Check that the command-line tools are working by running xcrun xctrace version
Check that the TestRay integration works by running testray ios list_devices (inside the av-automation-tests directory)

For setting up a real iOS device, see [this document](./SETUP_IOS.md)

#### Running Mac Tests

Starting Appium v.1.20, no further installations are needed! (before v.1.20, a separate program AppiumForMac was required)
However, one additional configuration is still required:

Open System Preferences -> Security & Privacy -> Privacy -> Accessibility, open the lock icon to allow changes
Run open /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Xcode/Agents/
Drag and drop the Xcode Helper application to the app list in the System Preferences window

#### Running Windows Tests

In Windows Settings, open Update & Security -> For developers -> switch to Developer Mode -> Yes
You may also need to first start PowerShell as an administrator before running your tests

To install the Edge webdriver (non-chromium) open Powershell and write this command:

<pre>
DISM.exe /Online /Add-Capability /CapabilityName:Microsoft.WebDriver~~~~0.0.1.0
</pre>

Admin priviledges may be needed. After installation there is no need to add the driver to the path.
