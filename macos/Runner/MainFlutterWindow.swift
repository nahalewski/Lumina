import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var videoPlayerBridge: VideoPlayerBridge?
  private var subtitleBridge: SubtitleBridge?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = NSRect(x: 0, y: 0, width: 1440, height: 960)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    
    // Initialize our custom bridges using the flutterViewController's messenger
    let messenger = flutterViewController.engine.binaryMessenger
    videoPlayerBridge = VideoPlayerBridge(messenger: messenger)
    subtitleBridge = SubtitleBridge(messenger: messenger)

    super.awakeFromNib()
  }
}
