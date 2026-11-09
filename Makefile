# Agentic: AI coding agent for legacy iOS (iOS 6.1 SDK, armv7).
# Build:  make package      (or: make package install)

TARGET := iphone:clang:6.1
ARCHS = armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Agentic

Agentic_FILES = $(wildcard Sources/*/*.m)

Agentic_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
Agentic_CFLAGS = -Wno-error \
	-ISources/App -ISources/API -ISources/Agent -ISources/Model \
	-ISources/Storage -ISources/UI -ISources/Support \
	-IVendor/curl/include
Agentic_LDFLAGS = \
	Vendor/curl/lib/libcurl.a \
	Vendor/curl/lib/libssl.a \
	Vendor/curl/lib/libcrypto.a \
	Vendor/curl/lib/libz.a
Agentic_INFOPLIST = Resources/Info.plist
Agentic_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/application.mk
