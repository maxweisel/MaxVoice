# Fix Plan for MaxVoice

## Learnings from max-voice-assistant

The working implementation uses several patterns we should adopt:

1. **NSPanel instead of NSWindow** - with `canBecomeKey = false` to prevent focus stealing
2. **`.nonactivatingPanel` style mask** - critical for overlay not stealing focus
3. **Synchronous permission check** - not in async Task
4. **`@MainActor` class annotations** - for thread safety
5. **Cursor-following timer** - overlay follows mouse continuously
6. **AppKit NSTextField** - simpler than SwiftUI for this use case

---

## Issue 0: No Permission Prompts

**Root Cause:**
- Permission check is in async Task - may not complete or may have race conditions
- `NSApp.setActivationPolicy(.accessory)` called too early

**Fixes (based on max-voice-assistant):**
1. Do accessibility check **synchronously** in `applicationDidFinishLaunching`, not in async Task
2. Call `AXIsProcessTrustedWithOptions` with `prompt: true` directly
3. Add restart-after-grant mechanism: check again after 5 seconds, relaunch if granted
4. Use `NSAlert` for critical config errors instead of overlay

**Code pattern from max-voice-assistant:**
```swift
// Request accessibility permission - this will show the system prompt
let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)

if !accessibilityEnabled {
    print("⚠️ Accessibility permission required. Will restart once granted...")
    let appPath = Bundle.main.bundleURL.path
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
        if AXIsProcessTrusted() {
            Process.launchedProcess(launchPath: "/usr/bin/open", arguments: ["-n", appPath])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        }
    }
}
```

---

## Issue 1: Toggle Instead of Hold

**Root Cause:**
- Current implementation fires on both press AND release
- User wants: press once to start, press again to stop

**Fixes:**
1. Change `HotkeyMonitor` to only call delegate on **press** (ignore release)
2. Change `AppState` to **toggle** state on each press:
   - If not recording → start recording
   - If recording → stop recording
3. Consider using **Right CMD only** (keyCode 0x36) like max-voice-assistant to avoid conflicts with normal CMD shortcuts

**Updated HotkeyMonitor approach:**
```swift
private func handleEvent(_ event: NSEvent) {
    let flags = event.modifierFlags
    let cmdPressed = flags.contains(.command)

    // Only fire on press transition (not release)
    if cmdPressed && !isCommandPressed {
        isCommandPressed = true
        delegate?.onHotkeyToggle()  // Single callback for toggle
    } else if !cmdPressed && isCommandPressed {
        isCommandPressed = false
        // No callback on release for toggle mode
    }
}
```

---

## Issue 2: No HUD Visible

**Root Cause:**
- Using `NSWindow` instead of `NSPanel`
- Missing `.nonactivatingPanel` style mask
- Window may be stealing focus or getting hidden

**Fixes (based on max-voice-assistant):**

1. **Create custom NSPanel subclass:**
```swift
private class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

2. **Use correct style mask:**
```swift
let panel = OverlayPanel(
    contentRect: NSRect(x: 0, y: 0, width: 420, height: 44),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.hidesOnDeactivate = false  // Keep visible when app loses focus
```

3. **Use AppKit NSTextField instead of SwiftUI:**
```swift
let textField = NSTextField(labelWithString: "Listening...")
textField.font = NSFont.systemFont(ofSize: 14)
textField.textColor = .white
textField.backgroundColor = .clear
// ... simpler than NSHostingView + SwiftUI
```

4. **Add cursor-following timer:**
```swift
cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
    Task { @MainActor in
        self?.positionAtCursor()
    }
}
```

---

## Issue 3: No Text Pasted

**Root Cause:**
- Depends on transcription working (fix issues 0-2 first)
- Accessibility permission required for CGEvent

**Fixes:**
1. Fix issues 0-2 first
2. Ensure accessibility permission is granted before attempting paste
3. Add logging to verify paste operation is being called
4. Verify transcription API is returning results

---

## Issue 4: Show in Dock

**Root Cause:**
- `LSUIElement=true` in Info.plist
- `NSApp.setActivationPolicy(.accessory)` in code

**Fixes:**
1. Change `LSUIElement` to `false` in Info.plist
2. Remove `NSApp.setActivationPolicy(.accessory)` line

---

## Issue 5: Thread Safety (NEW)

**Root Cause:**
- Event monitors call handlers on arbitrary threads
- UI updates must be on main thread

**Fixes (based on max-voice-assistant):**
1. Add `@MainActor` annotation to `HotkeyMonitor` and `TranscriptionOverlay` classes
2. Wrap event handler callbacks in `Task { @MainActor in ... }`
3. Verify monitor creation succeeded and log appropriately

---

## Summary of Files to Modify

| File | Changes |
|------|---------|
| `Info.plist` | Set `LSUIElement` to `false` |
| `MaxVoiceApp.swift` | Remove `setActivationPolicy(.accessory)`, do synchronous permission check with restart mechanism |
| `HotkeyMonitor.swift` | Add `@MainActor`, change to toggle mode, wrap in `Task { @MainActor }`, verify monitor creation |
| `AppState.swift` | Change to single `onHotkeyToggle()` callback that toggles recording state |
| `TranscriptionOverlay.swift` | Replace with `NSPanel` subclass, use `.nonactivatingPanel`, use NSTextField, add cursor timer |
| `OverlayContent.swift` | Can be deleted (replaced by AppKit approach) |
| `OverlayState.swift` | Simplify or merge into TranscriptionOverlay |

---

## Testing Steps After Fix

1. Kill any running MaxVoice: `pkill -9 MaxVoice`
2. Build and install
3. Launch app - verify it appears in dock
4. Verify accessibility permission prompt appears
5. Grant permission, verify app restarts automatically
6. Press CMD once - verify HUD appears at cursor with "Listening..."
7. Speak something
8. Press CMD again - verify HUD shows transcription then hides
9. Verify text is pasted into focused window
