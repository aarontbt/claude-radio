.PHONY: generate build test run archive clean

PROJECT = ClaudeRadio.xcodeproj
SCHEME = ClaudeRadio
CONFIG = Debug

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath build CONFIGURATION_BUILD_DIR=build/$(CONFIG) build

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS' -derivedDataPath build test

run: build
	open build/$(CONFIG)/ClaudeRadio.app

archive: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release archive -archivePath build/ClaudeRadio.xcarchive

clean:
	rm -rf build DerivedData $(PROJECT)
