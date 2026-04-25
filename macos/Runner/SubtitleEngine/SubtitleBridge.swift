import Foundation
import AVFoundation
import FlutterMacOS

/// Bridge between Flutter and native macOS AVFoundation + whisper.cpp
@available(macOS 10.15, *)
public class SubtitleBridge: NSObject {
    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayer?
    private var audioFile: AVAudioFile?
    private var audioBuffer: AVAudioPCMBuffer?
    
    private let channel: FlutterMethodChannel
    
    init(messenger: FlutterBinaryMessenger) {
        self.channel = FlutterMethodChannel(
            name: "com.lumina.media/subtitle_engine",
            binaryMessenger: messenger
        )
        super.init()
        self.channel.setMethodCallHandler(handle)
    }
    
    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "extractAudio":
            guard let args = call.arguments as? [String: Any],
                  let videoPath = args["videoPath"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing videoPath", details: nil))
                return
            }
            extractAudio(from: videoPath, result: result)
            
        case "startLiveTranscription":
            startLiveTranscription(result: result)
            
        case "stopLiveTranscription":
            stopLiveTranscription(result: result)
            
        case "getAudioLevel":
            result(getCurrentAudioLevel())
            
        case "exportSubtitles":
            guard let args = call.arguments as? [String: Any],
                  let srtContent = args["srtContent"] as? String,
                  let filePath = args["filePath"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing parameters", details: nil))
                return
            }
            exportSrtFile(content: srtContent, to: filePath, result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Audio Extraction
    
    private func extractAudio(from videoPath: String, result: @escaping FlutterResult) {
        let outputPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(
            UUID().uuidString + ".wav"
        )
        
        // Use ffmpeg for reliable audio extraction (supports all formats)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        process.arguments = [
            "-i", videoPath,
            "-vn",                    // No video
            "-acodec", "pcm_s16le",   // 16-bit PCM WAV
            "-ar", "16000",           // 16kHz sample rate (optimal for whisper)
            "-ac", "1",               // Mono
            "-y",                     // Overwrite output
            outputPath
        ]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                result(outputPath)
            } else {
                // Fallback: try AVFoundation export
                fallbackExtractAudio(from: videoPath, outputPath: outputPath, result: result)
            }
        } catch {
            // Fallback to AVFoundation
            fallbackExtractAudio(from: videoPath, outputPath: outputPath, result: result)
        }
    }
    
    private func fallbackExtractAudio(from videoPath: String, outputPath: String, result: @escaping FlutterResult) {
        let url = URL(fileURLWithPath: videoPath)
        let asset = AVAsset(url: url)
        
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            result(FlutterError(code: "NO_AUDIO", message: "No audio track found", details: nil))
            return
        }
        
        let outputURL = URL(fileURLWithPath: outputPath)
        
        Task {
            do {
                let composition = AVMutableComposition()
                guard let compositionTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    result(FlutterError(code: "COMPOSITION_FAILED", message: "Failed to create composition track", details: nil))
                    return
                }
                
                let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
                try compositionTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
                
                guard let exportSession = AVAssetExportSession(
                    asset: composition,
                    presetName: AVAssetExportPresetAppleM4A
                ) else {
                    result(FlutterError(code: "EXPORT_SESSION_FAILED", message: "Failed to create export session", details: nil))
                    return
                }
                
                let m4aURL = outputURL.deletingPathExtension().appendingPathExtension("m4a")
                exportSession.outputURL = m4aURL
                exportSession.outputFileType = .m4a
                
                await exportSession.export()
                
                if let error = exportSession.error {
                    result(FlutterError(code: "EXPORT_FAILED", message: error.localizedDescription, details: nil))
                } else {
                    result(m4aURL.path)
                }
            } catch {
                result(FlutterError(code: "EXTRACT_FAILED", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    // MARK: - Live Transcription (Audio Capture)
    
    private func startLiveTranscription(result: @escaping FlutterResult) {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)
            
            audioEngine = AVAudioEngine()
            guard let engine = audioEngine else { return }
            
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, time in
                guard let self = self else { return }
                // Convert buffer to float array and send to Flutter
                let channelData = buffer.floatChannelData
                let frameLength = Int(buffer.frameLength)
                var samples = [Float](repeating: 0, count: frameLength)
                
                if let data = channelData?[0] {
                    for i in 0..<frameLength {
                        samples[i] = data[i]
                    }
                }
                
                // Send audio chunk to Flutter for whisper.cpp processing
                let audioData = Data(bytes: samples, withUnsafeBytes { $0.base64EncodedString() })
                self.channel.invokeMethod("onAudioChunk", arguments: ["data": audioData])
            }
            
            try engine.start()
            result(true)
        } catch {
            result(FlutterError(code: "AUDIO_CAPTURE_FAILED", message: error.localizedDescription, details: nil))
        }
    }
    
    private func stopLiveTranscription(result: @escaping FlutterResult) {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        result(true)
    }
    
    private func getCurrentAudioLevel() -> Float {
        guard let engine = audioEngine, engine.isRunning else { return 0 }
        return engine.inputNode.lastRenderTime?.audioTime?.seconds.map { _ in 0.5 } ?? 0
    }
    
    // MARK: - SRT Export
    
    private func exportSrtFile(content: String, to filePath: String, result: @escaping FlutterResult) {
        let url = URL(fileURLWithPath: filePath)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            result(true)
        } catch {
            result(FlutterError(code: "EXPORT_FAILED", message: error.localizedDescription, details: nil))
        }
    }
}
