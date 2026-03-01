# VoiceInput Project Guidelines

## CRITICAL REQUIREMENTS

1. **ONLY use Google Cloud APIs** - Do NOT use Apple's SFSpeechRecognizer or any other speech recognition service. Use Google Cloud Speech-to-Text exclusively.

2. **Match the Python implementation** - This is a port of the Python voice-input-assistant. Follow the same architecture and API usage patterns as the original Python version.

3. **Google Streaming API** - For real-time transcription, use Google's `streamingRecognize` gRPC API, not the batch REST API. This matches how the Python version streams audio to Google.

## Current Implementation Status

**gRPC Bidirectional Streaming (Implemented):** Uses true gRPC streaming like the Python version. Audio is streamed continuously to Google Speech-to-Text and results are typed in real-time as they arrive.

**Build:** `swift build -c release` then create .app bundle manually or use the Makefile.

## Architecture

- Xcode project (not Swift Package Manager CLI)
- Use NSEvent.addGlobalMonitorForEvents for hotkey detection (like VoiceInk)
- Use system sounds (NSSound) for audio feedback
- Background app with no dock icon (LSUIElement=true)

## Config

User config lives at `~/.maxvoice/config.json` with:
- `googleApiKey` - Google Cloud API key (works for both Speech-to-Text and Gemini)
- `language` - Language code (e.g., "en-US")
- `postProcessingPrompt` - Optional Gemini prompt
- `replacements` - Word replacement pairs
