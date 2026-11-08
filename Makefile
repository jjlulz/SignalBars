export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SignalBars
SignalBars_FILES = Tweak.xm
SignalBars_CFLAGS = -fobjc-arc
SignalBars_FRAMEWORKS = UIKit QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
