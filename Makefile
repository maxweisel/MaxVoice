.PHONY: build release install uninstall clean run logs status

SCHEME = MaxVoice
PROJECT = MaxVoice.xcodeproj
BUILD_DIR = .build
APP_NAME = MaxVoice.app
INSTALL_DIR = /Applications

# Build debug version
build:
	@echo "Building MaxVoice (Debug)..."
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(BUILD_DIR) build
	@echo "Build complete: $(BUILD_DIR)/Build/Products/Debug/$(APP_NAME)"

# Build release version
release:
	@echo "Building MaxVoice (Release)..."
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -derivedDataPath $(BUILD_DIR) build
	@echo "Build complete: $(BUILD_DIR)/Build/Products/Release/$(APP_NAME)"

# Install to /Applications and set up launch agent
install: release
	@echo "Installing MaxVoice..."
	@if [ -d "$(INSTALL_DIR)/$(APP_NAME)" ]; then \
		echo "Removing existing installation..."; \
		rm -rf "$(INSTALL_DIR)/$(APP_NAME)"; \
	fi
	cp -r "$(BUILD_DIR)/Build/Products/Release/$(APP_NAME)" "$(INSTALL_DIR)/"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME)"
	@echo ""
	@echo "Installing launch agent..."
	cd LaunchAgent && ./install.sh install
	@echo ""
	@echo "Installation complete!"
	@echo ""
	@echo "IMPORTANT: Grant permissions when prompted:"
	@echo "  1. Microphone access"
	@echo "  2. Accessibility (System Settings > Privacy & Security > Accessibility)"
	@echo ""
	@echo "To start MaxVoice now: make run"

# Uninstall
uninstall:
	@echo "Uninstalling MaxVoice..."
	cd LaunchAgent && ./install.sh uninstall
	rm -rf "$(INSTALL_DIR)/$(APP_NAME)"
	@echo "Uninstall complete"

# Run the app (debug build)
run: build
	@echo "Starting MaxVoice..."
	"$(BUILD_DIR)/Build/Products/Debug/$(APP_NAME)/Contents/MacOS/MaxVoice"

# Run the installed app
run-installed:
	@echo "Starting MaxVoice from /Applications..."
	open "$(INSTALL_DIR)/$(APP_NAME)"

# View logs
logs:
	@echo "=== MaxVoice Logs ==="
	@echo ""
	@echo "--- stdout ---"
	@cat /tmp/maxvoice.log 2>/dev/null || echo "(no stdout log)"
	@echo ""
	@echo "--- stderr ---"
	@cat /tmp/maxvoice.err 2>/dev/null || echo "(no stderr log)"
	@echo ""
	@echo "--- System logs (last 50 lines) ---"
	@log show --predicate 'subsystem == "com.maxweisel.maxvoice"' --last 5m --style compact 2>/dev/null | tail -50 || echo "(no system logs)"

# Follow logs in real-time
logs-follow:
	@echo "Following MaxVoice system logs (Ctrl+C to stop)..."
	log stream --predicate 'subsystem == "com.maxweisel.maxvoice"' --style compact

# Check status
status:
	@cd LaunchAgent && ./install.sh status

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)
	rm -rf "$(APP_NAME)"
	@echo "Clean complete"

# Reset accessibility marker (to retry after granting permission)
reset-marker:
	@echo "Removing accessibility failure marker..."
	rm -f ~/.maxvoice/.accessibility_failed
	@echo "Done. You can now restart MaxVoice."

# Help
help:
	@echo "MaxVoice Build System"
	@echo "===================="
	@echo ""
	@echo "Commands:"
	@echo "  make build          - Build debug version"
	@echo "  make release        - Build release version"
	@echo "  make install        - Install to /Applications and set up launch agent"
	@echo "  make uninstall      - Remove from /Applications and launch agent"
	@echo "  make run            - Build and run debug version"
	@echo "  make run-installed  - Run installed version"
	@echo "  make logs           - View recent logs"
	@echo "  make logs-follow    - Follow logs in real-time"
	@echo "  make status         - Check launch agent status"
	@echo "  make clean          - Remove build artifacts"
	@echo "  make reset-marker   - Reset accessibility failure marker"
	@echo "  make help           - Show this help"
	@echo ""
	@echo "Config file: ~/.maxvoice/config.json"
	@echo ""
	@echo "Usage:"
	@echo "  Hold CMD key to record, release to transcribe and paste"
