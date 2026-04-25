import Foundation
import AVFoundation
import FlutterMacOS

/// Bridge between Flutter and native macOS AVFoundation + whisper.cpp
@available(macOS 10.15, *)
public class SubtitleBridge: NSObject, FlutterStreamHandler {
    private var audioEngine: AVAudioEngine?
    private var eventSink: FlutterEventSink?
    
    private let channel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    
    init(messenger: FlutterBinaryMessenger) {
        self.channel = FlutterMethodChannel(
            name: "com.lumina.media/subtitle_engine",
            binaryMessenger: messenger
        )
        self.eventChannel = FlutterEventChannel(
            name: "com.lumina.media/audio_chunks",
            binaryMessenger: messenger
        )
        super.init()
        self.channel.setMethodCallHandler(handle)
        self.eventChannel.setStreamHandler(self)
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
            
        case "requestMicrophonePermission":
            requestMicrophonePermission(result: result)
            
        case "toggleFullscreen":
            toggleFullscreen(result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - FlutterStreamHandler
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
    
    // MARK: - Audio Extraction
    
    private func extractAudio(from videoPath: String, result: @escaping FlutterResult) {
        let url = URL(fileURLWithPath: videoPath)
        let asset = AVAsset(url: url)
        
        guard asset.tracks(withMediaType: .audio).first != nil else {
            result(FlutterError(code: "NO_AUDIO", message: "No audio track found", details: nil))
            return
        }
        
        let outputPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(
            UUID().uuidString + ".wav"
        )
        let outputURL = URL(fileURLWithPath: outputPath)
        
        Task {
            do {
                try await extractAudioTrack(from: asset, outputURL: outputURL)
                result(outputPath)
            } catch {
                result(FlutterError(code: "EXTRACT_FAILED", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    private func extractAudioTrack(from asset: AVAsset, outputURL: URL) async throws {
        // For WAV extraction, we use AVAssetReader and AVAssetWriter for reliability
        // instead of AVAssetExportSession which has limited WAV support.
        
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            throw NSError(domain: "SubtitleBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio track"])
        }
        
        let duration = CMTimeGetSeconds(asset.duration)
        print("Native: Starting extraction of audio track (\(duration) seconds)")
        
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 16000, // Downsample to 16kHz for Whisper
            AVNumberOfChannelsKey: 1
        ]
        
        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(trackOutput)
        
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writer.add(writerInput)
        
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        let queue = DispatchQueue(label: "audio-extraction-queue")
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var sampleCount = 0
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = trackOutput.copyNextSampleBuffer() {
                        writerInput.append(sampleBuffer)
                        sampleCount += 1
                        if sampleCount % 1000 == 0 {
                            print("Native: Extracted \(sampleCount) audio samples...")
                        }
                    } else {
                        writerInput.markAsFinished()
                        let finalSampleCount = sampleCount
                        writer.finishWriting {
                            if writer.status == .completed {
                                print("Native: Audio extraction COMPLETED. Total samples: \(finalSampleCount)")
                                if reader.status == .failed {
                                    print("Native: WARNING - Reader failed at end: \(reader.error?.localizedDescription ?? "unknown")")
                                }
                                continuation.resume()
                            } else {
                                let error = writer.error ?? reader.error ?? NSError(domain: "SubtitleBridge", code: -4, userInfo: [NSLocalizedDescriptionKey: "Writer failed with status \(writer.status.rawValue)"])
                                print("Native: Audio extraction FAILED: \(error.localizedDescription)")
                                continuation.resume(throwing: error)
                            }
                        }
                        break
                    }
                }
            }
        }
    }
    
    // MARK: - Live Transcription (Audio Capture)
    
    private func startLiveTranscription(result: @escaping FlutterResult) {
        do {
            // Clean up any existing engine first
            audioEngine?.stop()
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine = nil
            
            audioEngine = AVAudioEngine()
            guard let engine = audioEngine else { return }
            
            let inputNode = engine.inputNode
            let nativeFormat = inputNode.outputFormat(forBus: 0)
            
            // Target format: 16kHz mono float32 (what Whisper expects)
            guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            ) else {
                result(FlutterError(code: "FORMAT_ERROR", message: "Cannot create 16kHz format", details: nil))
                return
            }
            
            // Use a smaller buffer size (4096 frames) to send chunks more frequently
            // This reduces the latency between speech and when Dart sees the audio
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
                guard let self = self, let sink = self.eventSink else { return }
                
                // Convert from native format to 16kHz mono using AVAudioConverter
                let frameCount = AVAudioFrameCount(targetFormat.sampleRate * Double(buffer.frameLength) / nativeFormat.sampleRate)
                guard frameCount > 0,
                      let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }
                
                var error: NSError?
                let converter = AVAudioConverter(from: nativeFormat, to: targetFormat)
                let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                converter?.convert(to: converted, error: &error, withInputFrom: inputBlock)
                
                if error != nil { return }
                
                let frameLength = Int(converted.frameLength)
                guard frameLength > 0, let channelData = converted.floatChannelData?[0] else { return }
                
                // Convert Float32 (-1.0...1.0) to Int16 (-32768...32767)
                var pcmData = Data(capacity: frameLength * 2)
                for i in 0..<frameLength {
                    let sample = channelData[i]
                    // Clipping protection
                    let clipped = max(-1.0, min(1.0, sample))
                    let int16Sample = Int16(clipped * 32767.0)
                    
                    withUnsafeBytes(of: int16Sample.littleEndian) { pcmData.append(contentsOf: $0) }
                }
                
                let base64String = pcmData.base64EncodedString()
                
                DispatchQueue.main.async {
                    if self.eventSink != nil {
                        sink(["data": base64String])
                    }
                }
            }
            
            try engine.start()
            print("Native: Live audio capture started at \(nativeFormat.sampleRate)Hz → 16000Hz mono")
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
        return 0.5
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
    
    private func requestMicrophonePermission(result: @escaping FlutterResult) {
        if #available(macOS 10.14, *) {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    result(granted)
                }
            }
        } else {
            result(true)
        }
    }
    
    private func toggleFullscreen(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            // Find the main window of the application
            if let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.className.contains("Window") }) ?? NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first {
                window.toggleFullScreen(nil)
                result(true)
            } else {
                result(false)
            }
        }
    }
}
