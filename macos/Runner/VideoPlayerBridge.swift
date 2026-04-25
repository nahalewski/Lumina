import Cocoa
import FlutterMacOS
import AVFoundation
import AVKit

/// Native macOS video player using AVFoundation
/// Renders video in a child window positioned within the Flutter app
class VideoPlayerBridge: NSObject {
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var playerView: AVPlayerView?
    private var playerWindow: NSWindow?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var durationObserver: NSKeyValueObservation?
    
    private let channel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private var eventSink: FlutterEventSink?
    
    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "com.lumina.media/video_player",
            binaryMessenger: messenger
        )
        eventChannel = FlutterEventChannel(
            name: "com.lumina.media/video_player_events",
            binaryMessenger: messenger
        )
        
        super.init()
        
        channel.setMethodCallHandler { [weak self] (call, result) in
            self?.handleMethodCall(call, result: result)
        }
        eventChannel.setStreamHandler(self)
    }
    
    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "play":
            player?.play()
            result(nil)
            
        case "pause":
            player?.pause()
            result(nil)
            
        case "seek":
            if let args = call.arguments as? [String: Any],
               let positionMs = args["position"] as? Double {
                let time = CMTime(seconds: positionMs / 1000.0, preferredTimescale: 600)
                player?.seek(to: time)
            }
            result(nil)
            
        case "setVolume":
            if let args = call.arguments as? [String: Any],
               let volume = args["volume"] as? Double {
                player?.volume = Float(volume)
            }
            result(nil)
            
        case "open":
            if let args = call.arguments as? [String: Any],
               let path = args["path"] as? String {
                openVideo(path: path)
                result(true)
            } else {
                result(false)
            }
            
        case "close":
            closeVideo()
            result(nil)
            
        case "getPosition":
            if let player = player {
                let seconds = CMTimeGetSeconds(player.currentTime())
                result(seconds * 1000.0)
            } else {
                result(0.0)
            }
            
        case "getDuration":
            if let duration = player?.currentItem?.duration {
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite {
                    result(seconds * 1000.0)
                } else {
                    result(0.0)
                }
            } else {
                result(0.0)
            }
            
        case "isPlaying":
            result((player?.rate ?? 0) > 0)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func openVideo(path: String) {
        closeVideo()
        
        // Support both local file paths and network URLs (HLS streams)
        let url: URL
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            url = URL(string: path)!
        } else {
            url = URL(fileURLWithPath: path)
        }
        let asset = AVAsset(url: url)
        playerItem = AVPlayerItem(asset: asset)
        
        player = AVPlayer(playerItem: playerItem)
        
        // Create a borderless, non-activating window for video
        // This window will be positioned to overlay the Flutter app's video area
        let windowRect = NSRect(x: 0, y: 0, width: 800, height: 600)
        
        playerView = AVPlayerView(frame: windowRect)
        playerView?.player = player
        playerView?.controlsStyle = .none
        playerView?.videoGravity = .resizeAspect
        
        playerWindow = NSWindow(
            contentRect: windowRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        playerWindow?.title = (url.lastPathComponent as NSString).deletingPathExtension
        playerWindow?.contentView = playerView
        playerWindow?.isReleasedWhenClosed = false
        playerWindow?.level = .normal
        playerWindow?.collectionBehavior = [.transient, .ignoresCycle]
        playerWindow?.delegate = self
        
        // Position the window relative to the main app window
        if let mainWindow = NSApplication.shared.mainWindow {
            let mainFrame = mainWindow.frame
            let videoHeight: CGFloat = mainFrame.height - 160 // Leave room for controls
            let videoRect = NSRect(
                x: mainFrame.origin.x + 80, // Account for sidebar
                y: mainFrame.origin.y + 80, // Account for bottom controls
                width: mainFrame.width - 80,
                height: videoHeight
            )
            playerWindow?.setFrame(videoRect, display: true)
            mainWindow.addChildWindow(playerWindow!, ordered: .above)
        }
        
        playerWindow?.makeKeyAndOrderFront(nil)
        
        // Observe status
        statusObserver = playerItem?.observe(\.status) { [weak self] item, _ in
            if item.status == .readyToPlay {
                self?.sendEvent(["event": "ready"])
                self?.player?.play()
            } else if item.status == .failed {
                self?.sendEvent(["event": "error", "message": item.error?.localizedDescription ?? "Unknown error"])
            }
        }
        
        // Observe duration
        durationObserver = playerItem?.observe(\.duration) { [weak self] item, _ in
            let seconds = CMTimeGetSeconds(item.duration)
            if seconds.isFinite {
                self?.sendEvent(["event": "duration", "duration": seconds * 1000.0])
            }
        }
        
        // Periodic time observer
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = CMTimeGetSeconds(time)
            self?.sendEvent(["event": "position", "position": seconds * 1000.0])
        }
        
        // Playback ended notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
    }
    
    private func closeVideo() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        durationObserver?.invalidate()
        durationObserver = nil
        
        player?.pause()
        player = nil
        playerItem = nil
        playerView = nil
        
        if let window = playerWindow {
            window.parent?.removeChildWindow(window)
            window.close()
        }
        playerWindow = nil
        
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func playerDidFinishPlaying() {
        sendEvent(["event": "completed"])
    }
    
    private func sendEvent(_ data: [String: Any]) {
        eventSink?(data)
    }
}

extension VideoPlayerBridge: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}

extension VideoPlayerBridge: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        sendEvent(["event": "closed"])
        closeVideo()
    }
}
