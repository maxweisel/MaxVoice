# MaxVoice

A native macOS voice-to-text application that uses Google Cloud Speech-to-Text for real-time transcription.

## Features

- **Push-to-talk**: Hold CMD key to record, release to transcribe and paste
- **Live transcription**: See your speech transcribed in real-time via floating overlay
- **Auto-paste**: Transcribed text is automatically pasted into the focused window
- **Gemini post-processing**: Optional AI-powered text cleanup using Google Gemini
- **Word replacements**: Configurable regex-based word substitutions
- **Background operation**: Runs silently with no dock or menu bar icon
- **Auto-start**: Launch agent for automatic startup on login

## Requirements

- macOS 13.0 or later
- Google Cloud API key with Speech-to-Text API enabled
- Microphone access permission
- Accessibility permission (for global hotkey and pasting)

## Installation

### Build from source

```bash
# Clone the repository
cd MaxVoice

# Build and install
make install
```

This will:
1. Build the release version
2. Copy `MaxVoice.app` to `/Applications`
3. Install the launch agent for auto-start

### Grant permissions

When first run, MaxVoice will prompt for:

1. **Microphone access**: Required for voice recording
2. **Accessibility access**: Required for global hotkey detection and auto-paste

Go to **System Settings > Privacy & Security** to grant these permissions.

## Configuration

Create `~/.maxvoice/config.json`:

```json
{
  "googleApiKey": "YOUR_GOOGLE_CLOUD_API_KEY",
  "language": "en-US",
  "postProcessingPrompt": null,
  "replacements": []
}
```

### Options

| Key | Type | Description |
|-----|------|-------------|
| `googleApiKey` | string | Your Google Cloud API key (required) |
| `language` | string | Language code for transcription (default: "en-US") |
| `postProcessingPrompt` | string | Optional Gemini prompt for text cleanup |
| `replacements` | array | Word replacement pairs `[["find", "replace"], ...]` |

### Supported languages

- `en-US` - English (US)
- `en-GB` - English (UK)
- `cmn-Hans-CN` - Mandarin Chinese
- `es-ES` - Spanish
- `fr-FR` - French
- `de-DE` - German
- `ja-JP` - Japanese
- `ko-KR` - Korean
- `pt-BR` - Portuguese (Brazil)
- `sv-SE` - Swedish
- `hi-IN` - Hindi

### Post-processing example

Set `postProcessingPrompt` to clean up transcripts:

```json
{
  "postProcessingPrompt": "Fix any grammatical errors and add proper punctuation. Keep the meaning exactly the same."
}
```

### Word replacements example

Fix common transcription errors:

```json
{
  "replacements": [
    ["recieve", "receive"],
    ["dont", "don't"],
    ["thier", "their"]
  ]
}
```

## Usage

1. **Start recording**: Press and hold the **CMD** key
2. **Speak**: A floating overlay shows "Listening..." then your transcription
3. **Stop recording**: Release the **CMD** key
4. **Auto-paste**: The transcribed text is pasted into the focused window

### Audio feedback

- **Start sound**: Thumbs up tone when recording starts
- **Stop sound**: Thumbs down tone when transcription completes
- **Error sound**: "Basso" system sound on errors

## Makefile commands

```bash
make build          # Build debug version
make release        # Build release version
make install        # Install to /Applications with launch agent
make uninstall      # Remove from /Applications and launch agent
make run            # Build and run debug version
make run-installed  # Run installed version
make logs           # View recent logs
make logs-follow    # Follow logs in real-time
make status         # Check launch agent status
make clean          # Remove build artifacts
make reset-marker   # Reset accessibility failure marker
make help           # Show help
```

## Troubleshooting

### App won't start

Check the logs:
```bash
make logs
```

### Accessibility permission issues

1. Go to **System Settings > Privacy & Security > Accessibility**
2. Remove MaxVoice from the list
3. Run `make reset-marker`
4. Restart MaxVoice and grant permission when prompted

### No transcription

1. Verify your Google Cloud API key is correct
2. Ensure Speech-to-Text API is enabled in Google Cloud Console
3. Check the logs for API errors: `make logs`

### Recording but no paste

Ensure Accessibility permission is granted in System Settings.

## Architecture

```
MaxVoice/
├── App/
│   ├── MaxVoiceApp.swift      # App entry point
│   ├── AppState.swift         # Main coordinator
│   └── SoundPlayer.swift      # Audio feedback
├── Audio/
│   ├── AudioRecorder.swift    # AVAudioEngine recording
│   └── AudioQueue.swift       # Thread-safe audio buffer
├── Services/
│   ├── SpeechTranscriber.swift    # Google Speech-to-Text
│   ├── GeminiPostProcessor.swift  # Gemini AI processing
│   └── TextReplacer.swift         # Regex replacements
├── Input/
│   ├── HotkeyMonitor.swift    # CMD key detection
│   └── ClipboardPaster.swift  # Clipboard + Cmd+V
├── UI/
│   ├── TranscriptionOverlay.swift  # Floating window
│   ├── OverlayContent.swift        # SwiftUI view
│   └── OverlayState.swift          # View state
├── Config/
│   ├── Config.swift           # Config model
│   └── ConfigManager.swift    # File I/O
└── Accessibility/
    └── AccessibilityChecker.swift  # Permission handling
```
