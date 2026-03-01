# Plan: Implement True gRPC Streaming with Chirp3

## Goal
Replace the fake "streaming" (repeated batch REST calls) with true bidirectional gRPC streaming using Google Speech-to-Text V2 API and Chirp3 model.

## Current State
- Using REST API `speech:recognize` endpoint
- Calling it every ~1 second with accumulated audio (not real streaming)
- No gRPC dependencies

## Target State
- True bidirectional gRPC streaming via `StreamingRecognize`
- Audio chunks sent as they arrive
- Results received in real-time
- Using Chirp3 model via V2 API

---

## Phase 1: Add gRPC Dependencies

1. Create/update Package.swift with:
   - grpc-swift (1.24.0+)
   - swift-protobuf (1.25.0+)

2. Update Xcode project to use SPM packages

---

## Phase 2: Get V2 Proto Files

1. Download Google Speech V2 proto files from googleapis:
   - google/cloud/speech/v2/cloud_speech.proto
   - Required dependencies (google/api/*, google/rpc/*, etc.)

2. Create Protos directory structure

---

## Phase 3: Generate Swift Code

1. Install protoc and grpc-swift plugin if needed
2. Generate Swift files:
   - CloudSpeechV2.pb.swift (protobuf messages)
   - CloudSpeechV2.grpc.swift (gRPC client stubs)

---

## Phase 4: Implement Streaming Transcriber

1. Create new `GRPCStreamingTranscriber.swift`:
   - Establish gRPC channel to speech.googleapis.com:443
   - Create bidirectional stream for StreamingRecognize
   - Send StreamingRecognizeRequest with config (first message)
   - Send audio chunks as they arrive
   - Receive StreamingRecognizeResponse with interim/final results
   - Handle errors and reconnection

2. Config for Chirp3:
   ```
   recognizer: "projects/{project}/locations/global/recognizers/_"
   config:
     model: "chirp_2" or "chirp"
     language_codes: ["en-US"]
     features:
       enable_automatic_punctuation: true
   ```

---

## Phase 5: Integrate with App

1. Update AppState to use new GRPCStreamingTranscriber
2. Wire up audio chunks from AudioRecorder directly to gRPC stream
3. Handle interim results -> update overlay
4. Handle final results -> paste text

---

## Phase 6: Test & Debug

1. Test streaming connection
2. Verify real-time transcription
3. Check Chirp3 model output (should format numbers as digits)
4. Test error handling and reconnection

---

## Files to Create/Modify

### New Files:
- `Protos/google/cloud/speech/v2/*.proto`
- `MaxVoice/Services/GRPCStreamingTranscriber.swift`
- `MaxVoice/Generated/CloudSpeechV2.pb.swift`
- `MaxVoice/Generated/CloudSpeechV2.grpc.swift`

### Modified Files:
- `Package.swift` - add dependencies
- `MaxVoice.xcodeproj` - add SPM packages
- `AppState.swift` - use new transcriber
- `SpeechTranscriber.swift` - remove or keep as fallback

---

## Implementation Order

1. Phase 1 → Phase 2 → Phase 3 (setup)
2. Phase 4 (core implementation)
3. Phase 5 → Phase 6 (integration & test)
