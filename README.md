# iOS CDM

<b>Software Requirements</b>

The following software must be installed on your development machine:
- OSX 10.9 or higher
- XCode 6.3 or higher

The following iOS targets are supported:
- iOS 8
- iOS 9

<b>Components</b>
- CDM Host Interface
- iOS SDK
- Reference Player
- CDM Dynamic Library

In addition, the following XCode project files will be included:
- Cocoa HTTP Server
- TBXML

<b>Build Steps</b>

Type the following inside an OSX terminal: 

1. <code>./setup_cdm_ios_project.sh</code>
2. Open XCode (Script prompts to open)
3. Change Target to CDMPlayer in XCode at the top of the menu
4. Set output device as iPhone or Simulator 
5. Run

<b>What the Script Does</b>

Downloads the following Third Party utilities:
- Cocoa HTTP Server: https://github.com/robbiehanson/CocoaHTTPServer
- TBXML: https://github.com/71squared/TBXML

Places each subproject into properly named directories for the XCode project to use.

<b>CHANGELOG</b>

v2.0.3 (2015 November)
 - Redesign project structure
 - Push to Git repository for easy cloning
 - Fix SIDX, MVHD and SPS bugs in Dash Transmuxer

v2.0.2 (2015 October)
 - Create Separate Controls for Buttons and Scrubber
 - Add Full Screen Support
 - Integrate Offline support (License Manager)
 - Breakout Tableview from SplitViewController
 - Remove Storyboards
 - Add Download Manager
 - Update UDT with Bug Fixes / Requests

v2.0.1 (2015 August)
 - Add Playback controls
 - Enable both Simulator and Device support
 - Build Dynamic Library containing CDM and UDT
 - Improve XML Parsing
 - Update UDT version

v2.0.0 (2015 March)
 - Build OEMCrypto Static Library
 - Integrated UDT
 - Integrated XML Parsing
 - Added Local HTTP Server
