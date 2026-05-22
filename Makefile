APP_NAME=HelperStatusBar
DESKTOP_APP_NAME=STATUS CTRL
APP_BUNDLE=$(APP_NAME).app
DESKTOP_APP=/Users/h-l/Desktop/$(DESKTOP_APP_NAME).app
CONTENTS_DIR=$(APP_BUNDLE)/Contents
MACOS_DIR=$(CONTENTS_DIR)/MacOS
RESOURCES_DIR=$(CONTENTS_DIR)/Resources
VERSION=1.4.0
DMG_NAME=$(DESKTOP_APP_NAME)-v$(VERSION).dmg
DMG_STAGING=dmg_staging

.PHONY: all clean run dmg universal

all: $(APP_BUNDLE)

# ── smchelper (Universal Binary) ──────────────────────────────────
smchelper: smchelper.swift SMCController.swift
	@echo "[Build] Compiling smchelper (Universal Binary: arm64 + x86_64)..."
	mkdir -p helper_src
	cp smchelper.swift helper_src/main.swift
	cp SMCController.swift helper_src/SMCController.swift
	swiftc helper_src/main.swift helper_src/SMCController.swift \
		-target arm64-apple-macos12.0 \
		-o smchelper_arm64
	swiftc helper_src/main.swift helper_src/SMCController.swift \
		-target x86_64-apple-macos12.0 \
		-o smchelper_x86_64
	lipo -create smchelper_arm64 smchelper_x86_64 -output smchelper
	rm -rf helper_src smchelper_arm64 smchelper_x86_64
	@echo "[Build] smchelper: $$(lipo -info smchelper)"

# ── Main App (Universal Binary) ───────────────────────────────────
$(APP_BUNDLE): smchelper KeyboardBacklightPrivate.o main.swift AppDelegate.swift SMCController.swift PowerMonitor.swift DashboardView.swift Bridging-Header.h
	@echo "[Build] Creating macOS App bundle..."
	mkdir -p $(MACOS_DIR)
	mkdir -p $(RESOURCES_DIR)
	cp alipay_qr.png $(RESOURCES_DIR)/alipay_qr.png
	cp wechat_qr.png $(RESOURCES_DIR)/wechat_qr.png
	cp AppIcon.icns $(RESOURCES_DIR)/AppIcon.icns

	@echo "[Build] Compiling arm64 slice..."
	swiftc \
		main.swift AppDelegate.swift SMCController.swift \
		PowerMonitor.swift DashboardView.swift \
		KeyboardBacklightPrivate.o \
		-import-objc-header Bridging-Header.h \
		-target arm64-apple-macos12.0 \
		-o $(MACOS_DIR)/$(APP_NAME)_arm64 \
		-framework Foundation -framework AppKit \
		-framework SwiftUI -framework IOKit \
		-framework ServiceManagement

	@echo "[Build] Compiling x86_64 slice..."
	swiftc \
		main.swift AppDelegate.swift SMCController.swift \
		PowerMonitor.swift DashboardView.swift \
		KeyboardBacklightPrivate.o \
		-import-objc-header Bridging-Header.h \
		-target x86_64-apple-macos12.0 \
		-o $(MACOS_DIR)/$(APP_NAME)_x86_64 \
		-framework Foundation -framework AppKit \
		-framework SwiftUI -framework IOKit \
		-framework ServiceManagement

	@echo "[Build] Creating Universal Binary..."
	lipo -create \
		$(MACOS_DIR)/$(APP_NAME)_arm64 \
		$(MACOS_DIR)/$(APP_NAME)_x86_64 \
		-output $(MACOS_DIR)/$(APP_NAME)
	rm -f $(MACOS_DIR)/$(APP_NAME)_arm64 $(MACOS_DIR)/$(APP_NAME)_x86_64

	@echo "[Build] Writing Info.plist..."
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > $(CONTENTS_DIR)/Info.plist
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> $(CONTENTS_DIR)/Info.plist
	@echo '<plist version="1.0">' >> $(CONTENTS_DIR)/Info.plist
	@echo '<dict>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundleExecutable</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <string>$(APP_NAME)</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundleIdentifier</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <string>com.hl.helperstatusbar</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundleName</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <string>STATUS CTRL</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundleShortVersionString</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <string>$(VERSION)</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundleVersion</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <string>$(VERSION)</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundlePackageType</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <string>APPL</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>LSMinimumSystemVersion</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <string>12.0</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>LSUIElement</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <true/>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>NSHumanReadableCopyright</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <string>© 2026 HL. All rights reserved.</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundleIconFile</key>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <string>AppIcon</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '</dict>' >> $(CONTENTS_DIR)/Info.plist
	@echo '</plist>' >> $(CONTENTS_DIR)/Info.plist
	@echo "[Build] ✅ $(APP_BUNDLE) compiled — $$(lipo -info $(MACOS_DIR)/$(APP_NAME))"
	@echo "[Build] Embedding smchelper into app bundle..."
	cp smchelper $(MACOS_DIR)/smchelper
	chmod +x $(MACOS_DIR)/smchelper
	@echo "[Deploy] Copying to Desktop as '$(DESKTOP_APP_NAME).app'..."
	rm -rf "$(DESKTOP_APP)"
	cp -r $(APP_BUNDLE) "$(DESKTOP_APP)"
	@echo "[Deploy] ✅ '$(DESKTOP_APP_NAME).app' is ready on your Desktop!"

# ── Objective-C Keyboard layer ────────────────────────────────────
KeyboardBacklightPrivate.o: KeyboardBacklightPrivate.m KeyboardBacklightPrivate.h
	@echo "[Build] Compiling ObjC keyboard layer (Universal: arm64 + x86_64)..."
	clang -c KeyboardBacklightPrivate.m -o KeyboardBacklightPrivate_arm64.o \
	      -fobjc-arc -target arm64-apple-macos12.0
	clang -c KeyboardBacklightPrivate.m -o KeyboardBacklightPrivate_x86_64.o \
	      -fobjc-arc -target x86_64-apple-macos12.0
	lipo -create KeyboardBacklightPrivate_arm64.o KeyboardBacklightPrivate_x86_64.o \
	     -output KeyboardBacklightPrivate.o
	rm -f KeyboardBacklightPrivate_arm64.o KeyboardBacklightPrivate_x86_64.o

# ── DMG packaging ─────────────────────────────────────────────────
# 产物放在桌面，DMG 内只含 App + Applications 快捷方式（标准 macOS 安装体验）
DESKTOP_DMG=/Users/h-l/Desktop/$(DMG_NAME)

dmg: all
	@echo "[DMG] Packaging $(DESKTOP_APP_NAME) v$(VERSION) → $(DESKTOP_DMG)"
	rm -rf "$(DMG_STAGING)" "$(DESKTOP_DMG)"
	mkdir -p "$(DMG_STAGING)"
	# 只放 App，smchelper 已内嵌在 App bundle 里
	cp -r "$(DESKTOP_APP)" "$(DMG_STAGING)/$(DESKTOP_APP_NAME).app"
	# 标准拖拽安装快捷方式
	ln -s /Applications "$(DMG_STAGING)/Applications"
	hdiutil create \
		-volname "$(DESKTOP_APP_NAME)" \
		-srcfolder "$(DMG_STAGING)" \
		-ov \
		-format UDZO \
		-fs HFS+ \
		"$(DESKTOP_DMG)"
	rm -rf "$(DMG_STAGING)"
	@echo "[DMG] ✅ 完成: $(DESKTOP_DMG) ($$(du -sh '$(DESKTOP_DMG)' | cut -f1))"

# ── Helpers ───────────────────────────────────────────────────────
run: all
	open $(APP_BUNDLE)

clean:
	@echo "[Clean] Removing build artifacts..."
	rm -rf $(APP_BUNDLE) KeyboardBacklightPrivate.o smchelper \
	       smchelper_arm64 smchelper_x86_64 $(DMG_STAGING) *.dmg \
	       KeyboardBacklightPrivate_arm64.o KeyboardBacklightPrivate_x86_64.o
	@echo "[Clean] Removing Desktop app..."
	rm -rf "$(DESKTOP_APP)"
