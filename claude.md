# MaxVoice Project Guidelines

## CRITICAL REQUIREMENTS

1. **ONLY use Google Cloud APIs** - Do NOT use Apple's SFSpeechRecognizer or any other speech recognition service. Use Google Cloud Speech-to-Text exclusively.

2. **Match the Python implementation** - This is a port of the Python voice-input-assistant. Follow the same architecture and API usage patterns as the original Python version.

3. **Google Speech-to-Text API** - Currently uses the REST `speech:recognize` API with interim updates. True gRPC bidirectional streaming would require additional proto generation.

## Current Implementation Status

**Implemented:**
- CMD key hotkey detection (hold to record, release to stop)
- Audio recording via AVAudioEngine (16kHz mono LINEAR16)
- Stereo-to-mono downmix with AVAudioMixerNode (Parallels VM support)
- Google Speech-to-Text transcription (REST API with interim updates)
- Live transcription overlay near cursor
- Gemini post-processing (optional)
- Regex word replacements
- Clipboard swap + Cmd+V paste
- Microphone permission handling
- Accessibility permission handling with smart restart
- Launch agent for auto-start
- System sounds for feedback (start/stop/error)
- Comprehensive logging via os.log

**Build:**
```bash
make build      # Debug build
make release    # Release build
make install    # Install to /Applications with launch agent
make run        # Build and run debug
make logs       # View logs
```

## Architecture

- Xcode project (MaxVoice.xcodeproj)
- NSEvent.addGlobalMonitorForEvents for hotkey detection
- AVAudioEngine + AVAudioMixerNode for audio capture
- NSSound for audio feedback
- SwiftUI for overlay content
- Background app with no dock icon (LSUIElement=true)

## Key Files

- `App/MaxVoiceApp.swift` - Entry point, permission handling
- `App/AppState.swift` - Main coordinator
- `Audio/AudioRecorder.swift` - 16kHz mono recording
- `Services/SpeechTranscriber.swift` - Google Speech-to-Text
- `Services/GeminiPostProcessor.swift` - Gemini AI cleanup
- `Input/HotkeyMonitor.swift` - CMD key detection
- `UI/TranscriptionOverlay.swift` - Floating HUD

## Config

User config lives at `~/.maxvoice/config.json`:
```json
{
  "googleApiKey": "YOUR_API_KEY",
  "language": "en-US",
  "postProcessingPrompt": null,
  "replacements": []
}
```

## Logging

View logs with:
```bash
make logs           # Recent logs
make logs-follow    # Real-time stream
log show --predicate 'subsystem == "com.maxweisel.maxvoice"' --last 1h
```
