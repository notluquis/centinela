# Centinela is built with SwiftPM and the app bundle is assembled here, by hand.
#
# There is no `.xcodeproj` on purpose. A `project.pbxproj` is a generated file tens of thousands
# of lines long that nobody reviews in a diff and that conflicts just from opening it. For an app
# with one binary and no extensions, `swift build` plus a few lines of `Makefile` do the same and
# can be read end to end.

# The compiler resolves to the toolchain's REAL binary, not to whatever `swift` is on PATH.
#
# With swiftly installed, `~/.swiftly/bin/swift` is a proxy that picks the toolchain at run time.
# Under `make` that decision comes out differently than under an interactive shell: SwiftPM ends
# up compiling the manifest with `/Library/Developer/CommandLineTools/usr/bin/swiftc`, whose
# `PackageDescription` does not know `swiftLanguageMode`, and `Package.swift` fails to parse with
# an error that mentions none of this. Asking swiftly where the toolchain lives takes the proxy
# out of the picture.
SWIFTLY   := $(shell command -v swiftly 2>/dev/null)
TOOLCHAIN := $(if $(SWIFTLY),$(shell $(SWIFTLY) use --print-location 2>/dev/null))
SWIFT     ?= $(if $(TOOLCHAIN),$(TOOLCHAIN)/usr/bin/swift,swift)

# swiftlint needs `sourcekitdInProc.framework`, which it only looks for inside Xcode. With a
# swiftly toolchain it has to be pointed at it by hand or it dies with a dlopen `Fatal error`.
SOURCEKIT := $(if $(TOOLCHAIN),$(TOOLCHAIN)/usr/lib)

# Where SwiftPM unpacked Sparkle's XCFramework. Resolved rather than hardcoded so it survives a
# version bump.
#
# `=` and NOT `:=`: an immediate assignment is evaluated when the Makefile is PARSED, which is
# before `swift build` has downloaded the artifact. On a machine that already had it the variable
# was fine and on a clean CI runner it came out empty, so the recipe ran `cp -R "" …`. Lazy
# assignment evaluates it when the recipe actually uses it, by which time `build` has run.
SPARKLE        = $(shell find .build/artifacts -maxdepth 5 -name Sparkle.framework -type d 2>/dev/null | head -1)

APP           := Centinela
BUNDLE_ID     := cl.bioalergia.centinela
VERSION       ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' | grep . || echo 0.0.0)
BUILD         ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
CONFIG        ?= release
BUILD_DIR     := .build/$(CONFIG)
APP_DIR       := build/$(APP).app
# The signing identity. This is not cosmetic: with an ad-hoc signature the app's designated
# requirement is literally its code hash, so every build looks like a different application to the
# Keychain and macOS asks the user for their password on every update. Measured: the same read took
# 23 ms from the build that wrote the item and 7709 ms from a rebuild, the gap being the dialog.
#
# A self-signed certificate makes the requirement identity-based instead:
#
#     designated => identifier "cl.bioalergia.centinela" and certificate root = H"303ec746…"
#
# which is stable across builds. Measured after switching: 25 ms, 18 ms, 18 ms, and no dialog.
# See SECURITY.md for how to create one. Falls back to ad-hoc when it is not installed, which
# builds and runs fine and only costs the Keychain prompt.
SIGNING_NAME  ?= Centinela Signing
IDENTITY      ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q "$(SIGNING_NAME)" && echo "$(SIGNING_NAME)" || echo "-")

.PHONY: build app run test lint clean install toolchain screenshot

toolchain:
	@echo "swift: $(SWIFT)"
	@$(SWIFT) --version | head -1

build:
	$(SWIFT) build -c $(CONFIG)

test:
	$(SWIFT) test

lint:
	@command -v swiftlint >/dev/null 2>&1 || { \
		echo "swiftlint is not installed: brew install swiftlint"; \
		echo "(this used to skip silently, which is how 80 violations reached CI)"; \
		exit 1; \
	}
	DYLD_FRAMEWORK_PATH="$(SOURCEKIT)" swiftlint lint --quiet --strict

app: build
	rm -rf $(APP_DIR)
	mkdir -p $(APP_DIR)/Contents/MacOS $(APP_DIR)/Contents/Resources
	cp $(BUILD_DIR)/$(APP) $(APP_DIR)/Contents/MacOS/$(APP)
	sed -e 's/__VERSION__/$(VERSION)/' -e 's/__BUILD__/$(BUILD)/' \
		Resources/Info.plist > $(APP_DIR)/Contents/Info.plist
	# `swift build` leaves the target's resource bundle next to the binary; if it exists it has
	# to travel inside the app bundle or `Bundle.module` will not find it at run time.
	@if [ -d "$(BUILD_DIR)/$(APP)_$(APP).bundle" ]; then \
		cp -R "$(BUILD_DIR)/$(APP)_$(APP).bundle" $(APP_DIR)/Contents/Resources/; \
	fi
	cp -R Resources/*.lproj $(APP_DIR)/Contents/Resources/
	cp Resources/Centinela.icns $(APP_DIR)/Contents/Resources/
	# Sparkle's licence travels with Sparkle. It is MIT, and MIT asks that the notice be included
	# in "all copies or substantial portions of the Software" — shipping the framework inside this
	# bundle without it is the one condition that licence sets, unmet. Resolved from the artifact
	# rather than vendored, so a version bump cannot leave a stale notice behind.
	@sparkle_license=$$(find .build/artifacts -maxdepth 4 -iname 'LICENSE*' -path '*[Ss]parkle*' | head -1); \
	if [ -n "$$sparkle_license" ]; then \
		cp "$$sparkle_license" $(APP_DIR)/Contents/Resources/Sparkle-LICENSE.txt; \
	else \
		echo "error: Sparkle's licence was not found; the bundle would ship it without one" >&2; \
		exit 1; \
	fi
	# Sparkle travels inside the bundle. It arrives ad-hoc signed from its own project, which is
	# consistent with how this app is signed.
	mkdir -p $(APP_DIR)/Contents/Frameworks
	@test -n "$(SPARKLE)" || { echo "Sparkle.framework not found under .build/artifacts. Run 'swift package resolve'."; exit 1; }
	cp -R "$(SPARKLE)" $(APP_DIR)/Contents/Frameworks/
	# `swift build` writes an rpath pointing at the build directory, which does not exist on
	# anyone else's machine. Without this the app launches to a dyld error about Sparkle.
	install_name_tool -add_rpath @executable_path/../Frameworks $(APP_DIR)/Contents/MacOS/$(APP) 2>/dev/null || true
	# Signed from the inside out. `--deep` is discouraged by Apple and gets the nested XPC
	# services wrong; each piece is signed in order instead.
	codesign --force --options runtime --sign "$(IDENTITY)" \
		$(APP_DIR)/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/*.xpc
	codesign --force --options runtime --sign "$(IDENTITY)" \
		$(APP_DIR)/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app
	codesign --force --options runtime --sign "$(IDENTITY)" \
		$(APP_DIR)/Contents/Frameworks/Sparkle.framework
	codesign --force --options runtime --entitlements Centinela.entitlements \
		--sign "$(IDENTITY)" $(APP_DIR)
	@echo "Done: $(APP_DIR) (version $(VERSION), build $(BUILD), signature '$(IDENTITY)')"

run: app
	open $(APP_DIR)

install: app
	rm -rf /Applications/$(APP).app
	cp -R $(APP_DIR) /Applications/
	@echo "Installed at /Applications/$(APP).app"

# Regenerates the README image. Compiles `Tools/screenshot.swift` against the app's own sources
# rather than duplicating the panel, so an image that stops matching the UI is a compile error
# rather than a picture that quietly lies.
#
# `CentinelaApp.swift` is excluded because the tool brings its own `@main`, and `CentinelaCore` is
# linked from its object files: SwiftPM builds no static library for a library target.
screenshot: build
	@SDK="$$(xcrun --show-sdk-path)"; \
	OBJS="$$(ls Sources/CentinelaCore/*.swift | sed 's|Sources/CentinelaCore/|$(BUILD_DIR)/CentinelaCore.build/|;s|$$|.o|')"; \
	APPSRC="$$(ls Sources/Centinela/*.swift | grep -v CentinelaApp.swift)"; \
	$(TOOLCHAIN)/usr/bin/swiftc -O -sdk "$$SDK" -target arm64-apple-macos14.0 \
	  -I $(BUILD_DIR)/Modules -L $(BUILD_DIR) -F $(BUILD_DIR) -framework Sparkle \
	  -Xlinker -rpath -Xlinker "$(PWD)/$(BUILD_DIR)" \
	  $$APPSRC Tools/screenshot.swift $$OBJS -o $(BUILD_DIR)/screenshot
	$(BUILD_DIR)/screenshot docs/panel.png

clean:
	rm -rf .build build
