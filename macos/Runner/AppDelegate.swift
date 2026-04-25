import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var videoPlayerBridge: VideoPlayerBridge?
  private var subtitleBridge: SubtitleBridge?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ application: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Bridges are now initialized in MainFlutterWindow to ensure they use the correct registrar/messenger
  }
}
