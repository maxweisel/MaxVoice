# MaxVoice Project Guidelines

## CRITICAL REQUIREMENTS - READ CAREFULLY

### MANDATORY: Google Cloud Speech-to-Text V2 API ONLY

1. **USE ONLY Google Cloud Speech-to-Text V2 API** - This is non-negotiable.
   - Use `google.cloud.speech.v2` protos and gRPC client
   - Use `StreamingRecognize` for real-time transcription
   - Use Chirp model (`model: "chirp"` or `"chirp_2"` or `"chirp_3"`)
   - Project ID: `claude-code-voice-assistant`

2. **DO NOT USE ANY OF THESE:**
   - ❌ Google Cloud Speech-to-Text V1 API (`google.cloud.speech.v1`) - NEVER
   - ❌ Apple SFSpeechRecognizer - NEVER
   - ❌ Any other speech recognition service - NEVER
   - ❌ REST API for streaming - use gRPC only

3. **Authentication:** API key via `x-goog-api-key` gRPC metadata header

### Why V2 Only?
- Chirp models (best quality) are ONLY available in V2
- V2 is the modern API with better features
- The user has explicitly requested V2 multiple times

## Current Implementation Status

**gRPC Bidirectional Streaming (Implemented):** Uses true gRPC streaming with V2 API. Audio is streamed continuously to Google Speech-to-Text and results arrive in real-time.

**Build:** `swift build -c release` (uses SPM with grpc-swift)

**Key Components:**
- Right CMD key toggle (not hold-to-talk)
- Audio recording via AVAudioEngine (16kHz mono LINEAR16)
- Live transcription overlay at cursor
- Gemini post-processing (optional)
- Word replacements
- Clipboard paste via Cmd+V simulation

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
