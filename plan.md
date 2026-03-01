# MaxVoice Swift Implementation Plan

## Overview

Port the Python `voice-input-assistant` to a native Swift/macOS application with identical features, using Google Cloud Speech-to-Text gRPC streaming for real-time transcription.

---

## 1. Project Structure

```
MaxVoice/
├── MaxVoice.xcodeproj/
├── MaxVoice/
│   ├── App/
│   │   ├── MaxVoiceApp.swift          # App entry point (NSApplicationDelegate)
│   │   ├── AppState.swift             # Global app state coordinator
│   │   └── Info.plist                 # LSUIElement=true, permissions
│   │
│   ├── Audio/
│   │   ├── AudioRecorder.swift        # AVAudioEngine capture (16kHz mono LINEAR16)
│   │   └── AudioQueue.swift           # Thread-safe queue for audio chunks
│   │
│   ├── Services/
│   │   ├── SpeechTranscriber.swift    # Google Speech-to-Text gRPC streaming
│   │   ├── GeminiPostProcessor.swift  # Optional Gemini post-processing
│   │   └── TextReplacer.swift         # Regex word replacements
│   │
│   ├── Input/
│   │   ├── HotkeyMonitor.swift        # NSEvent global monitor for CMD key
│   │   └── ClipboardPaster.swift      # Clipboard swap + Cmd+V simulation
│   │
│   ├── UI/
│   │   ├── TranscriptionOverlay.swift # Floating HUD window near cursor
│   │   └── OverlayContent.swift       # SwiftUI view for overlay content
│   │
│   ├── Config/
│   │   ├── ConfigManager.swift        # Read/write ~/.maxvoice/config.json
│   │   └── Config.swift               # Codable config struct
│   │
│   ├── Accessibility/
│   │   └── AccessibilityChecker.swift # Check/prompt for permissions
│   │
│   └── Resources/
│       └── Assets.xcassets            # (empty, no icons needed)
│
├── LaunchAgent/
│   ├── com.maxvoice.agent.plist       # launchd plist
│   └── install.sh                     # Install/uninstall script
│
├── Makefile                           # Build automation
└── README.md
```

---

## 2. Xcode Project Configuration

### Info.plist Settings
```xml
<key>LSUIElement</key>
<true/>                                    <!-- No dock icon -->

<key>NSMicrophoneUsageDescription</key>
<string>MaxVoice needs microphone access for speech recognition.</string>

<key>LSApplicationCategoryType</key>
<string>public.app-category.utilities</string>

<key>CFBundleIdentifier</key>
<string>com.maxweisel.maxvoice</string>
```

### Permission Requests at Runtime

The app must request both **Accessibility** and **Microphone** permissions at startup:

**Microphone Permission:**
```swift
import AVFoundation

func requestMicrophonePermission() async -> Bool {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    switch status {
    case .authorized:
        return true
    case .notDetermined:
        return await AVCaptureDevice.requestAccess(for: .audio)
    case .denied, .restricted:
        return false
    @unknown default:
        return false
    }
}
```

**Accessibility Permission:**
```swift
import ApplicationServices

func requestAccessibilityPermission() -> Bool {
    // Check without prompting first
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
    if AXIsProcessTrustedWithOptions(options as CFDictionary) {
        return true
    }
    // Prompt user - this opens System Preferences
    let promptOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    AXIsProcessTrustedWithOptions(promptOptions as CFDictionary)
    return false
}
```

**Startup Flow:**
1. Request microphone permission (async, blocks until user responds)
2. If denied, show error overlay and exit
3. Check accessibility permission
4. If not granted, prompt and enter polling loop (see Section 12)

### Build Settings
- Deployment target: macOS 13.0+ (for modern SwiftUI/gRPC compatibility)
- Code signing: Sign to run locally or with Developer ID for distribution
- Output: .app bundle

### Entitlements

**For non-sandboxed app (recommended):** No entitlements file needed. The `NSMicrophoneUsageDescription` in Info.plist is sufficient for AVAudioEngine access. The system will prompt the user when the app first tries to access the microphone.

**If sandboxing is required later:** Add `MaxVoice.entitlements`:
```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
```

**Note:** Sandboxing is not required for a personal utility app. The `com.apple.security.device.audio-input` entitlement is only needed when `com.apple.security.app-sandbox` is enabled. For this app, we'll skip sandboxing to simplify development.

---

## 3. Dependencies

### Swift Package Manager Dependencies
```swift
// Package.swift or Xcode SPM integration
dependencies: [
    .package(url: "https://github.com/grpc/grpc-swift.git", from: "2.0.0"),
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.25.0"),
]
```

### Proto Files Required
- Generate Swift code from Google Speech-to-Text proto files
- Files needed:
  - `google/cloud/speech/v1/cloud_speech.proto`
  - `google/api/annotations.proto`
  - `google/rpc/status.proto`

---

## 4. Audio Recording

### AudioRecorder.swift

**Sample Rate**: 16,000 Hz (Google Speech-to-Text requirement)
**Bit Depth**: 16-bit signed integer (LINEAR16)
**Channels**: Mono

```swift
class AudioRecorder {
    private let audioEngine = AVAudioEngine()
    private let mixerNode = AVAudioMixerNode()  // For stereo→mono conversion
    private let audioQueue = AudioQueue()

    func startRecording()
    func stopRecording()  // Push nil sentinel to signal end
    func getAudioChunk() -> Data?  // Non-blocking pop from queue
}
```

**Key Implementation Details:**
- Install tap on `audioEngine.inputNode`
- Convert Float32 samples to Int16 PCM bytes
- If device sample rate ≠ 16kHz, use `AVAudioConverter`
- Block size: 1024 frames per chunk (64ms at 16kHz)
- Thread-safe queue using `DispatchQueue` or `NSLock`

### Stereo-to-Mono Handling (Parallels VM Support)

Virtual microphones (e.g., Parallels) may report as stereo. Use `AVAudioMixerNode` for proper stereo-to-mono downmix with automatic gain adjustment:

```swift
func setupAudioPipeline() {
    let inputNode = audioEngine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)

    // Target format: 16kHz mono Float32 (will convert to Int16 later)
    let monoFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    // Insert mixer node for automatic stereo→mono downmix
    // AVAudioMixerNode handles gain adjustment internally (averages channels, no clipping)
    audioEngine.attach(mixerNode)

    // Connect: inputNode → mixerNode (stereo→mono happens here)
    audioEngine.connect(inputNode, to: mixerNode, format: inputFormat)

    // Install tap on mixer output (now mono)
    mixerNode.installTap(onBus: 0, bufferSize: 1024, format: monoFormat) { buffer, time in
        self.processAudioBuffer(buffer)
    }
}

private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.floatChannelData?[0] else { return }
    let frameCount = Int(buffer.frameLength)

    // Convert Float32 [-1.0, 1.0] to Int16 [-32768, 32767]
    var int16Data = [Int16](repeating: 0, count: frameCount)
    for i in 0..<frameCount {
        let sample = max(-1.0, min(1.0, channelData[i]))  // Clamp
        int16Data[i] = Int16(sample * 32767.0)
    }

    let data = Data(bytes: &int16Data, count: frameCount * 2)
    audioQueue.push(data)
}
```

**Why AVAudioMixerNode:**
- Automatically handles channel count conversion (stereo→mono)
- Uses proper gain staging (averages channels instead of summing, preventing clipping)
- Also handles sample rate conversion if needed
- More robust than manual vDSP operations

---

## 5. Google Speech-to-Text gRPC Streaming

### SpeechTranscriber.swift

**API Configuration (matching Python):**
```swift
struct StreamingConfig {
    let encoding: AudioEncoding = .linear16
    let sampleRateHertz: Int32 = 16000
    let languageCode: String  // from config, e.g., "en-US"
    let model: String = "latest_long"
    let useEnhanced: Bool = true
    let enableAutomaticPunctuation: Bool = true
    let interimResults: Bool = true  // CRITICAL for live updates
}
```

**Streaming Flow:**
1. Create bidirectional gRPC stream with API key auth
2. Send `StreamingRecognizeRequest` with config as first message
3. Spawn background task to continuously send audio chunks
4. Receive responses on main/callback thread
5. Emit interim results (live transcription updates)
6. Accumulate final results (is_final=true segments)
7. End stream when nil sentinel received

**Callbacks:**
```swift
protocol TranscriptionDelegate: AnyObject {
    func onInterimResult(_ text: String)      // Live updates
    func onFinalResult(_ text: String)        // Complete transcript
    func onError(_ error: Error)
}
```

**API Key Authentication:**
- Use `CallOptions` with `customMetadata` for `x-goog-api-key` header
- Or use `GoogleCloudAuth` if available in Swift SDK

---

## 6. Hotkey Detection

### HotkeyMonitor.swift

**Implementation:**
```swift
class HotkeyMonitor {
    private var globalMonitor: Any?
    private var isCommandPressed = false

    func start() {
        // Monitor for flagsChanged to detect modifier key state
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged]
        ) { [weak self] event in
            let cmdPressed = event.modifierFlags.contains(.command)

            if cmdPressed && !self.isCommandPressed {
                // CMD pressed - start recording
                self.delegate?.onHotkeyPressed()
            } else if !cmdPressed && self.isCommandPressed {
                // CMD released - stop recording
                self.delegate?.onHotkeyReleased()
            }

            self.isCommandPressed = cmdPressed
        }
    }
}
```

**Notes:**
- Using `flagsChanged` event type for modifier keys (CMD)
- Track state to detect press/release transitions
- Requires accessibility permissions

---

## 7. Transcription Overlay

### TranscriptionOverlay.swift

**Window Configuration:**
```swift
class TranscriptionOverlay {
    private var window: NSWindow?

    func show(near point: NSPoint) {
        window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window?.level = .floating
        window?.backgroundColor = .clear
        window?.isOpaque = false
        window?.hasShadow = true
        window?.ignoresMouseEvents = true

        // Position 24px offset from cursor
        // Use NSHostingView with SwiftUI content
    }
}
```

### OverlayContent.swift (SwiftUI)

```swift
struct OverlayContent: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        Text(state.displayText)
            .foregroundColor(state.textColor)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.86))  // 220/255
            )
            .frame(maxWidth: 420)
    }
}
```

**States:**
- **Listening**: "Listening…" placeholder, white text
- **Transcribing**: Live interim text, white text
- **Processing**: Final text + spinning braille (⣾⣽⣻⢿⡿⣟⣯⣷), semi-white
- **Error**: Error message, light red text (#FF6B6B)

**Position Updates:**
- Track mouse position during recording
- Update window origin to follow cursor

---

## 8. Clipboard & Paste

### ClipboardPaster.swift

```swift
class ClipboardPaster {
    func paste(text: String) {
        let pasteboard = NSPasteboard.general

        // 1. Save current clipboard
        let oldContents = pasteboard.string(forType: .string)

        // 2. Set transcript
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. After 80ms, simulate Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.simulatePaste()
        }

        // 4. After 350ms, restore clipboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            pasteboard.clearContents()
            if let old = oldContents {
                pasteboard.setString(old, forType: .string)
            }
        }
    }

    private func simulatePaste() {
        // Use CGEvent to simulate Cmd+V
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)  // V
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
```

---

## 9. Configuration

### Config.swift

```swift
struct Config: Codable {
    var googleApiKey: String
    var language: String = "en-US"
    var postProcessingPrompt: String?
    var replacements: [[String]]  // [["find", "replace"], ...]
}
```

### ConfigManager.swift

```swift
class ConfigManager {
    private let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".maxvoice/config.json")

    func load() -> Config? {
        guard let data = try? Data(contentsOf: configPath) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    func save(_ config: Config) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configPath)
        }
    }
}
```

---

## 10. Gemini Post-Processing

### GeminiPostProcessor.swift

```swift
class GeminiPostProcessor {
    private let apiKey: String
    private let model = "gemini-2.5-flash"

    func process(transcript: String, prompt: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let fullPrompt = """
        \(prompt)

        Transcript:
        \(transcript)

        Respond ONLY with the processed text, nothing else.
        """

        let body: [String: Any] = [
            "contents": [["parts": [["text": fullPrompt]]]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        // Parse response JSON for generated text
        return parsedText
    }
}
```

---

## 11. Word Replacements

### TextReplacer.swift

```swift
class TextReplacer {
    func apply(replacements: [[String]], to text: String) -> String {
        var result = text
        for pair in replacements where pair.count == 2 {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: pair[0]) + "\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: pair[1]
                )
            }
        }
        return result
    }
}
```

---

## 12. Accessibility Permission Handling

### AccessibilityChecker.swift

```swift
class AccessibilityChecker {
    static func hasAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func promptForPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
```

### App Startup Logic

```swift
@main
struct MaxVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var attemptCount = 0
    private let maxAttempts = 3
    private var checkTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check for accessibility permission
        if !AccessibilityChecker.hasAccessibilityPermission() {
            AccessibilityChecker.promptForPermission()
            startPermissionCheck()
        } else {
            startApp()
        }
    }

    private func startPermissionCheck() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 3.3, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            if AccessibilityChecker.hasAccessibilityPermission() {
                self.checkTimer?.invalidate()
                self.startApp()
            } else {
                self.attemptCount += 1
                if self.attemptCount >= 3 {
                    // After ~10 seconds (3 checks × 3.3s), give up
                    self.checkTimer?.invalidate()
                    self.exitWithAccessibilityFailure()
                }
            }
        }
    }

    private func exitWithAccessibilityFailure() {
        // Write marker file indicating accessibility failure
        let markerPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".maxvoice/.accessibility_failed")
        try? "".write(to: markerPath, atomically: true, encoding: .utf8)

        NSApp.terminate(nil)
    }

    private func startApp() {
        // Remove failure marker if it exists
        let markerPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".maxvoice/.accessibility_failed")
        try? FileManager.default.removeItem(at: markerPath)

        // Initialize app components
    }
}
```

---

## 13. Launch Agent

### com.maxvoice.agent.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.maxvoice.agent</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>
            MARKER="$HOME/.maxvoice/.accessibility_failed"
            if [ -f "$MARKER" ]; then
                exit 1
            fi
            /Applications/MaxVoice.app/Contents/MacOS/MaxVoice
        </string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>

    <key>ThrottleInterval</key>
    <integer>10</integer>

    <key>StandardErrorPath</key>
    <string>/tmp/maxvoice.err</string>

    <key>StandardOutPath</key>
    <string>/tmp/maxvoice.log</string>
</dict>
</plist>
```

**Smart Restart Logic:**
- `KeepAlive.SuccessfulExit: false` = restart if app crashes (non-zero exit)
- The shell wrapper checks for `.accessibility_failed` marker
- If marker exists, shell exits with 1 (no restart loop)
- App removes marker on successful permission grant
- `ThrottleInterval: 10` prevents rapid restart loops

### install.sh

```bash
#!/bin/bash
PLIST_NAME="com.maxvoice.agent.plist"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME"

install() {
    mkdir -p "$HOME/Library/LaunchAgents"
    cp "$PLIST_NAME" "$PLIST_PATH"
    launchctl load "$PLIST_PATH"
    echo "Launch agent installed and loaded"
}

uninstall() {
    launchctl unload "$PLIST_PATH" 2>/dev/null
    rm -f "$PLIST_PATH"
    rm -f "$HOME/.maxvoice/.accessibility_failed"
    echo "Launch agent uninstalled"
}

case "$1" in
    install) install ;;
    uninstall) uninstall ;;
    *) echo "Usage: $0 {install|uninstall}" ;;
esac
```

---

## 14. Sounds

### SoundPlayer.swift

```swift
class SoundPlayer {
    static let startSound = NSSound(contentsOfFile:
        "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/AlertTones/Text-Message-Acknowledgement-ThumbsUp.caf",
        byReference: true)

    static let stopSound = NSSound(contentsOfFile:
        "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/AlertTones/Text-Message-Acknowledgement-ThumbsDown.caf",
        byReference: true)

    static let errorSound = NSSound(named: "Basso")

    static func playStart() { startSound?.play() }
    static func playStop() { stopSound?.play() }
    static func playError() { errorSound?.play() }
}
```

---

## 15. Main App Flow

### AppState.swift (Coordinator)

```swift
class AppState: ObservableObject {
    private let config: ConfigManager
    private let recorder: AudioRecorder
    private let transcriber: SpeechTranscriber
    private let postProcessor: GeminiPostProcessor
    private let replacer: TextReplacer
    private let hotkeyMonitor: HotkeyMonitor
    private let overlay: TranscriptionOverlay
    private let paster: ClipboardPaster

    @Published var isRecording = false
    @Published var currentTranscript = ""

    func onHotkeyPressed() {
        // 1. Play start sound
        SoundPlayer.playStart()

        // 2. Show overlay at cursor position
        let mouseLocation = NSEvent.mouseLocation
        overlay.show(near: mouseLocation)
        overlay.setState(.listening)

        // 3. Start recording
        recorder.startRecording()

        // 4. Start streaming transcription
        transcriber.startStreaming(
            audioSource: recorder,
            config: loadedConfig
        )

        isRecording = true
    }

    func onHotkeyReleased() {
        guard isRecording else { return }
        isRecording = false

        // 1. Stop recording (sends nil sentinel)
        recorder.stopRecording()

        // 2. Wait for final transcript
        // (handled in transcriber delegate callback)
    }

    func onFinalTranscript(_ text: String) {
        // 1. Play stop sound
        SoundPlayer.playStop()

        // 2. Show processing state
        overlay.setState(.processing)

        Task {
            var result = text

            // 3. Optional Gemini post-processing
            if let prompt = config.postProcessingPrompt, !prompt.isEmpty {
                result = try await postProcessor.process(transcript: result, prompt: prompt)
            }

            // 4. Apply word replacements
            result = replacer.apply(replacements: config.replacements, to: result)

            // 5. Paste result
            await MainActor.run {
                overlay.hide()
                paster.paste(text: result)
            }
        }
    }

    func onTranscriptError(_ error: Error) {
        SoundPlayer.playError()
        overlay.showError(error.localizedDescription)

        // Hide after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            self.overlay.hide()
        }
    }
}
```

---

## 16. Build & Distribution

### Makefile

```makefile
.PHONY: build release install clean

SCHEME = MaxVoice
BUILD_DIR = .build
APP_NAME = MaxVoice.app
INSTALL_DIR = /Applications

build:
	xcodebuild -scheme $(SCHEME) -configuration Debug -derivedDataPath $(BUILD_DIR)

release:
	xcodebuild -scheme $(SCHEME) -configuration Release -derivedDataPath $(BUILD_DIR)
	cp -r "$(BUILD_DIR)/Build/Products/Release/$(APP_NAME)" .

install: release
	cp -r $(APP_NAME) $(INSTALL_DIR)/
	cd LaunchAgent && ./install.sh install

uninstall:
	rm -rf $(INSTALL_DIR)/$(APP_NAME)
	cd LaunchAgent && ./install.sh uninstall

clean:
	rm -rf $(BUILD_DIR) $(APP_NAME)
```

---

## 17. Implementation Order

### Phase 1: Foundation
1. Create Xcode project with correct Info.plist settings
2. Add gRPC-Swift and Swift Protobuf dependencies
3. Generate proto files for Google Speech-to-Text
4. Implement ConfigManager for ~/.maxvoice/config.json

### Phase 2: Audio Pipeline
5. Implement AudioRecorder with AVAudioEngine (16kHz mono)
6. Implement thread-safe AudioQueue
7. Test audio capture locally

### Phase 3: gRPC Streaming
8. Implement SpeechTranscriber with bidirectional streaming
9. Handle interim/final results
10. Test transcription end-to-end

### Phase 4: User Interaction
11. Implement HotkeyMonitor for CMD key
12. Implement TranscriptionOverlay with SwiftUI
13. Implement ClipboardPaster
14. Add sound effects

### Phase 5: Post-Processing
15. Implement GeminiPostProcessor
16. Implement TextReplacer
17. Wire everything together in AppState

### Phase 6: Permissions & Launch
18. Implement AccessibilityChecker with smart restart
19. Create launch agent with accessibility failure handling
20. Create install/uninstall scripts

### Phase 7: Polish
21. Error handling throughout
22. Logging for debugging
23. Testing and refinement

---

## 18. Key Technical Challenges

1. **gRPC Swift Integration**: May need to manually generate protos or find existing Google Cloud Swift SDK
2. **Audio Format Conversion**: If device doesn't support 16kHz, need AVAudioConverter
3. **Stereo Microphone Input (Parallels)**: Virtual microphones may report as stereo; use AVAudioMixerNode for proper downmix with automatic gain adjustment to avoid clipping
4. **CMD Key Edge Cases**: CMD is used system-wide (Cmd+C, Cmd+V), need to avoid conflicts
5. **Timing for Paste**: 80ms/350ms delays are empirical, may need adjustment
6. **Overlay Position**: Need to handle multi-monitor setups correctly
7. **Permission Flow**: Must handle both microphone and accessibility permissions gracefully, with clear user feedback if denied
