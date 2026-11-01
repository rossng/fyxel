# Build Fyxel.app from the Swift package. Needs Xcode or the Command Line Tools.
#
#   make            build build/Fyxel.app
#   make install    copy it to /Applications (and fyxelctl to ~/.local/bin)
#   make run        build and open
#   make zip        build/Fyxel.zip, for copying to another Mac
#   make dmg        build/Fyxel-<version>.dmg for releases (ad-hoc signed, not notarized; needs uv)
#   make demo       run the app against the built-in mock router
#   make test       unit tests (against the mock router)
#   make screenshots  regenerate docs/screenshots from the mock router

APP      := build/Fyxel.app
BIN      := $(shell swift build -c release --show-bin-path 2>/dev/null)
# Sign with an Apple Development identity if there is one (keeps Keychain access stable
# across rebuilds), otherwise ad-hoc. Override with `make IDENTITY=-`.
IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Apple Development[^"]*"' | tr -d '"')
ifeq ($(strip $(IDENTITY)),)
IDENTITY := -
endif

# The Command Line Tools ship swift-testing outside the default search path.
CLT_FW   := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TESTFLAGS := $(if $(wildcard $(CLT_FW)/Testing.framework),-Xswiftc -F$(CLT_FW) -Xlinker -F$(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_FW))

# Sections captured by `make screenshots` (sidebar names, comma-separated).
SECTIONS ?= Overview,Devices,Wi-Fi,Wi-Fi Settings,LAN,Firewall,Diagnostics,Logs,Maintenance

VERSION  := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Support/Info.plist)
DMG      := build/Fyxel-$(VERSION).dmg

.PHONY: all app install run zip dmg clean icon demo test screenshots

all: app

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$(BIN)/Fyxel" $(APP)/Contents/MacOS/Fyxel
	cp Support/Info.plist $(APP)/Contents/Info.plist
	[ -f Support/AppIcon.icns ] && cp Support/AppIcon.icns $(APP)/Contents/Resources/ || true
	codesign --force --options runtime --timestamp=none --sign "$(IDENTITY)" $(APP)
	@echo "Signed with: $(IDENTITY)"

install: app
	rm -rf /Applications/Fyxel.app
	cp -R $(APP) /Applications/
	mkdir -p $(HOME)/.local/bin
	cp "$(BIN)/fyxelctl" $(HOME)/.local/bin/fyxelctl
	@echo "Installed /Applications/Fyxel.app and ~/.local/bin/fyxelctl"

run: app
	open $(APP)

zip: app
	cd build && rm -f Fyxel.zip && ditto -c -k --keepParent Fyxel.app Fyxel.zip
	@echo "build/Fyxel.zip"

# Release disk image with a themed install window. Always ad-hoc signed, so it carries no
# personal certificate. dmgbuild lays out the window without driving Finder.
dmg:
	$(MAKE) app IDENTITY=-
	swift Support/make-dmg-background.swift build/dmg-background
	rm -f $(DMG)
	uvx dmgbuild -s Support/dmg-settings.py -D app=$(APP) -D background=build/dmg-background.tiff Fyxel $(DMG)
	@echo "$(DMG)"

demo: app
	FYXEL_MOCK=1 $(APP)/Contents/MacOS/Fyxel

test:
	swift test $(TESTFLAGS)

screenshots: app
	mkdir -p docs/screenshots
	# Launched via `open` so the window is frontmost (active controls render in colour).
	open -W -n --env FYXEL_MOCK=1 --env FYXEL_SNAPSHOT_DIR=$(CURDIR)/docs/screenshots \
	  --env FYXEL_SNAPSHOT_ONLY="$(SECTIONS)" \
	  $(APP)

icon:
	swift Support/make-icon.swift Support/AppIcon.icns

clean:
	rm -rf build .build
