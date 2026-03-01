import SwiftUI

/// SwiftUI view for the transcription overlay content
struct OverlayContent: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        Text(state.displayText)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(state.textColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.86))  // 220/255 opacity
            )
            .frame(maxWidth: 420, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Listening state
        OverlayContent(state: {
            let s = OverlayState()
            s.setListening()
            return s
        }())

        // Transcribing state with text
        OverlayContent(state: {
            let s = OverlayState()
            s.setTranscribing()
            s.updateTranscript("Hello, this is a test transcription")
            return s
        }())

        // Processing state
        OverlayContent(state: {
            let s = OverlayState()
            s.updateTranscript("Processing this text")
            s.setProcessing()
            return s
        }())

        // Error state
        OverlayContent(state: {
            let s = OverlayState()
            s.setError("API key missing — open Settings...")
            return s
        }())
    }
    .padding()
    .background(Color.gray)
}
