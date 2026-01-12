.SUFFIXES:

PWD= $(dir $(abspath $(firstword $(MAKEFILE_LIST))))
.DEFAULT_GOAL := 3dsx

#---------------------------------------------------------------------------------
# Environment Setup
#---------------------------------------------------------------------------------
ifeq ($(strip $(DEVKITPRO)),)
$(error "Please set DEVKITPRO in your environment. export DEVKITPRO=<path to>devkitPRO")
endif

ifeq ($(strip $(DEVKITARM)),)
$(error "Please set DEVKITARM in your environment. export DEVKITARM=<path to>devkitARM")
endif

include $(DEVKITARM)/3ds_rules

# ip address of 3ds for hblauncher/fbi target.
IP3DS := 172.20.10.2

#---------------------------------------------------------------------------------
# Directory Setup
#---------------------------------------------------------------------------------
BUILD := build
OUTPUT := output
SOURCES := source
DATA := data
INCLUDES := $(SOURCES) include
ROMFS := romfs
RESOURCES := resources
SDL := SDL

$(SDL)/build/libSDL2.a:
	@cd $(TOPDIR)/$(SDL) && \
	cmake -S. -Bbuild -DCMAKE_TOOLCHAIN_FILE="$(DEVKITPRO)/cmake/3DS.cmake" -DCMAKE_BUILD_TYPE=Release && \
	cmake --build build -j

#---------------------------------------------------------------------------------
# Resource Setup
#---------------------------------------------------------------------------------
APP_INFO := $(RESOURCES)/AppInfo
BANNER_AUDIO := $(RESOURCES)/audio/audio
BANNER_IMAGE := $(RESOURCES)/banner
ICON := $(RESOURCES)/icon.png
RSF := $(TOPDIR)/$(RESOURCES)/template.rsf

#---------------------------------------------------------------------------------
# Build Setup (code generation)
#---------------------------------------------------------------------------------
ARCH := -march=armv6k -mtune=mpcore -mfloat-abi=hard

COMMON_FLAGS := -g -Wall -Wno-strict-aliasing -Wno-unused-value -Wno-unused-but-set-variable -O3 -mword-relocations -fomit-frame-pointer \
	-ffast-math $(ARCH) $(INCLUDE) -D__3DS__ $(BUILD_FLAGS)
CFLAGS := $(COMMON_FLAGS) -std=gnu99 $(shell sdl2-config --cflags) -DSYSTEM_VOLUME_MIXER_AVAILABLE=0 -I. -Wno-typedef-redefinition
CXXFLAGS := $(COMMON_FLAGS) -std=gnu++17
# CXXFLAGS += -fno-rtti -fno-exceptions

ASFLAGS := -g $(ARCH)
LDFLAGS = -specs=3dsx.specs -g $(ARCH) -Wl,-Map,$(notdir $*.map)

LIBS := $(TOPDIR)/$(SDL)/build/libSDL2main.a $(TOPDIR)/$(SDL)/build/libSDL2.a -lcitro2d -lcitro3d -lctru -lm
LIBDIRS := $(PORTLIBS) $(CTRULIB) ./lib

# SM game sources
SM_DIR := sm
SM_SRCS := $(wildcard $(SM_DIR)/src/*.c) $(wildcard $(SM_DIR)/src/snes/*.c) $(SM_DIR)/third_party/gl_core/gl_core_3_1.c
SM_SRCS := $(filter-out $(SM_DIR)/src/main.c, $(SM_SRCS))
SM_CFILES := $(notdir $(SM_SRCS))

#---------------------------------------------------------------------------------
ifneq ($(BUILD),$(notdir $(CURDIR)))
#---------------------------------------------------------------------------------

#---------------------------------------------------------------------------------
# Version File
#---------------------------------------------------------------------------------

include resources/AppInfo

VERSION_H = $(SOURCES)/version.h

$(VERSION_H): resources/AppInfo
	echo "#pragma once" > $(VERSION_H)
	echo "#define APP_TITLE \"$(APP_TITLE)\"" >> $(VERSION_H)
	echo "#define APP_AUTHOR \"$(APP_AUTHOR)\"" >> $(VERSION_H)
	echo "#define APP_VERSION \"$(APP_VER_MAJOR).$(APP_VER_MINOR).$(APP_VER_MICRO)\"" >> $(VERSION_H)

#---------------------------------------------------------------------------------
# Build Variable Setup
#---------------------------------------------------------------------------------
recurse = $(shell find $2 -type $1 -name '$3' 2> /dev/null)

CFILES := $(foreach dir,$(SOURCES),$(notdir $(call recurse,f,$(dir),*.c))) $(SM_CFILES)
ALL_CPP := $(foreach dir,$(SOURCES),$(call recurse,f,$(dir),*.cpp))
CPPFILES := $(foreach dir,$(SOURCES),$(notdir $(call recurse,f,$(dir),*.cpp)))

SFILES := $(foreach dir,$(SOURCES),$(notdir $(call recurse,f,$(dir),*.s)))
PICAFILES := $(foreach dir,$(SOURCES),$(notdir $(call recurse,f,$(dir),*.pica)))
SHLISTFILES	:=	$(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.shlist)))
BINFILES	:=	$(foreach dir,$(DATA),$(notdir $(wildcard $(dir)/*.*)))

export OFILES	:=	$(addsuffix .o,$(BINFILES)) \
	$(PICAFILES:.v.pica=.shbin.o) \
	$(SHLISTFILES:.shlist=.shbin.o) \
	$(CPPFILES:.cpp=.o) \
	$(CFILES:.c=.o) \
	$(SFILES:.s=.o)

export INCLUDE := $(foreach dir,$(INCLUDES),-I$(CURDIR)/$(dir)) \
	$(foreach dir,$(LIBDIRS),-I$(dir)/include) -I$(CURDIR)/$(BUILD) \
	-I$(CURDIR)/$(SDL)/build/include -I$(CURDIR)/$(SDL)/include \
	-I$(CURDIR)/$(SM_DIR) -I$(CURDIR)/$(SM_DIR)/src

export LIBPATHS := $(foreach dir,$(LIBDIRS),-L$(dir)/lib) \
				   -L$(SDL)/build

ifeq ($(strip $(CPPFILES)),)
	export LD := $(CC)
else
	export LD := $(CXX)
endif

export DEPSDIR := $(CURDIR)/$(BUILD)
export VPATH := $(foreach dir,$(SOURCES),$(CURDIR)/$(dir) $(call recurse,d,$(CURDIR)/$(dir),*)) \
                $(foreach dir,$(DATA),$(CURDIR)/$(dir) $(call recurse,d,$(CURDIR)/$(dir),*)) \
                $(CURDIR)/$(SM_DIR)/src $(CURDIR)/$(SM_DIR)/src/snes $(CURDIR)/$(SM_DIR)/third_party/gl_core

export TOPDIR := $(CURDIR)
OUTPUT_DIR := $(TOPDIR)/$(OUTPUT)

.PHONY: $(BUILD) clean all format

#---------------------------------------------------------------------------------
# Initial Targets
#---------------------------------------------------------------------------------
all: $(BUILD) $(OUTPUT_DIR)
	@make --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile

3dsx: $(VERSION_H) $(BUILD) $(OUTPUT_DIR)
# 	@echo $(CFILES)
	@make --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile $@

cia: $(BUILD) $(OUTPUT_DIR)
	@echo $(BANNER_IMAGE_FILE)
	@make --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile $@

3ds: $(BUILD) $(OUTPUT_DIR)
	@make --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile $@

elf: $(BUILD) $(OUTPUT_DIR)
	@make --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile $@

azahar: $(BUILD) $(OUTPUT_DIR)
	@make --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile $@

hblauncher: $(BUILD) $(OUTPUT_DIR)
	@make --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile $@

fbi: $(BUILD) $(OUTPUT_DIR)
	@make --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile $@

$(BUILD):
	@[ -d $@ ] || mkdir -p $@

$(OUTPUT_DIR):
	@[ -d $@ ] || mkdir -p $@

fmt:
	find . -regex '.*\.\(c\|cc\|cpp\|cxx\|h\|hh\|hpp\)' -exec clang-format -i {} +

clean:
	@echo clean ...
	@rm -fr $(BUILD) $(OUTPUT) $(DEVEL_OBJECTS) $(PARSER_OUT)

#---------------------------------------------------------------------------------
else
#---------------------------------------------------------------------------------

#---------------------------------------------------------------------------------
# Build Information Setup
#---------------------------------------------------------------------------------
DEPENDS := $(OFILES:.o=.d)

include $(TOPDIR)/$(APP_INFO)
APP_TITLE := $(shell echo "$(APP_TITLE)" | cut -c1-128)
APP_DESCRIPTION := $(shell echo "$(APP_DESCRIPTION)" | cut -c1-256)
APP_AUTHOR := $(shell echo "$(APP_AUTHOR)" | cut -c1-128)
APP_PRODUCT_CODE := $(shell echo $(APP_PRODUCT_CODE) | cut -c1-16)
APP_UNIQUE_ID := $(shell echo $(APP_UNIQUE_ID) | cut -c1-7)
APP_VER_MAJOR := $(shell echo $(APP_VER_MAJOR) | cut -c1-3)
APP_VER_MINOR := $(shell echo $(APP_VER_MINOR) | cut -c1-3)
APP_VER_MICRO := $(shell echo $(APP_VER_MICRO) | cut -c1-3)
ifneq ("$(wildcard $(TOPDIR)/$(BANNER_IMAGE).cgfx)","")
	BANNER_IMAGE_FILE := $(TOPDIR)/$(BANNER_IMAGE).cgfx
	BANNER_IMAGE_ARG := -ci $(BANNER_IMAGE_FILE)
else
	BANNER_IMAGE_FILE := $(TOPDIR)/$(BANNER_IMAGE).png
	BANNER_IMAGE_ARG := -i $(BANNER_IMAGE_FILE)
endif

ifneq ("$(wildcard $(TOPDIR)/$(BANNER_AUDIO).cwav)","")
	BANNER_AUDIO_FILE := $(TOPDIR)/$(BANNER_AUDIO).cwav
	BANNER_AUDIO_ARG := -ca $(BANNER_AUDIO_FILE)
else
	BANNER_AUDIO_FILE := $(TOPDIR)/$(BANNER_AUDIO).wav
	BANNER_AUDIO_ARG := -a $(BANNER_AUDIO_FILE)
endif

EMPTY :=
SPACE := $(EMPTY) $(EMPTY)
OUTPUT_NAME := $(subst $(SPACE),,$(APP_TITLE))
OUTPUT_DIR := $(TOPDIR)/$(OUTPUT)
OUTPUT_FILE := $(OUTPUT_DIR)/$(OUTPUT_NAME)

APP_ICON := $(TOPDIR)/$(ICON)
APP_ROMFS := $(TOPDIR)/$(ROMFS)

COMMON_MAKEROM_PARAMS := -rsf $(RSF) -target t -exefslogo -elf $(OUTPUT_FILE).elf -icon icon.icn -banner banner.bnr \
	-DAPP_TITLE="$(APP_TITLE)" -DAPP_PRODUCT_CODE="$(APP_PRODUCT_CODE)" -DAPP_UNIQUE_ID="$(APP_UNIQUE_ID)" \
	-DAPP_ROMFS="$(APP_ROMFS)" -DAPP_SYSTEM_MODE="64MB" -DAPP_SYSTEM_MODE_EXT="Legacy" -major "$(APP_VER_MAJOR)" \
	-minor "$(APP_VER_MINOR)" -micro "$(APP_VER_MICRO)"

ifeq ($(OS),Windows_NT)
	MAKEROM = makerom.exe
	BANNERTOOL = bannertool.exe
else
	MAKEROM = makerom
	BANNERTOOL = bannertool
endif

_3DSXFLAGS += --smdh=$(OUTPUT_FILE).smdh
ifneq ($(ROMFS),)
	export _3DSXFLAGS += --romfs=$(APP_ROMFS)
endif

#---------------------------------------------------------------------------------
# Main Targets
#---------------------------------------------------------------------------------
.PHONY: all 3dsx cia elf 3ds azahar fbi hblauncher sdl-build banner
all: $(OUTPUT_FILE).zip $(OUTPUT_FILE).3ds $(OUTPUT_FILE).cia

banner.bnr: $(BANNER_IMAGE_FILE) $(BANNER_AUDIO_FILE)
	@echo $(BANNER_IMAGE_FILE)
	@$(BANNERTOOL) makebanner $(BANNER_IMAGE_ARG) $(BANNER_AUDIO_ARG) -o banner.bnr > /dev/null

icon.icn: $(TOPDIR)/$(ICON)
	@$(BANNERTOOL) makesmdh -s "$(APP_TITLE)" -l "$(APP_TITLE)" -p "$(APP_AUTHOR)" -i $(TOPDIR)/$(ICON) -o icon.icn > /dev/null

$(OUTPUT_FILE).elf: $(OFILES) $(SDL)/build/libSDL2.a

$(OUTPUT_FILE).3dsx: $(OUTPUT_FILE).elf $(OUTPUT_FILE).smdh

$(OUTPUT_FILE).3ds: $(OUTPUT_FILE).elf banner.bnr icon.icn
	@$(MAKEROM) -f cci -o $(OUTPUT_FILE).3ds -DAPP_ENCRYPTED=true $(COMMON_MAKEROM_PARAMS)
	@echo "built ... $(notdir $@)"

$(OUTPUT_FILE).cia: $(OUTPUT_FILE).elf banner.bnr icon.icn
	@$(MAKEROM) -f cia -o $(OUTPUT_FILE).cia -DAPP_ENCRYPTED=false $(COMMON_MAKEROM_PARAMS)
	@echo "built ... $(notdir $@)"

$(OUTPUT_FILE).zip: $(OUTPUT_FILE).smdh $(OUTPUT_FILE).3dsx
	@cd $(OUTPUT_DIR); \
	mkdir -p 3ds/$(OUTPUT_NAME); \
	cp $(OUTPUT_FILE).3dsx 3ds/$(OUTPUT_NAME); \
	cp $(OUTPUT_FILE).smdh 3ds/$(OUTPUT_NAME); \
	zip -r $(OUTPUT_FILE).zip 3ds > /dev/null; \
	rm -r 3ds
	@echo "built ... $(notdir $@)"

3dsx : $(OUTPUT_FILE).3dsx

cia : $(OUTPUT_FILE).cia

3ds : $(OUTPUT_FILE).3ds

elf : $(OUTPUT_FILE).elf

AZAHAR=flatpak run org.azahar_emu.Azahar
azahar : $(OUTPUT_FILE).3dsx
	$(AZAHAR) $(OUTPUT_FILE).3dsx

fbi : $(OUTPUT_FILE).cia
	python ../buildtools/servefiles.py $(IP3DS) $(OUTPUT_FILE).cia

hblauncher : $(OUTPUT_FILE).3dsx
	3dslink -a $(IP3DS) $(OUTPUT_FILE).3dsx


#---------------------------------------------------------------------------------
# you need a rule like this for each extension you use as binary data
#---------------------------------------------------------------------------------
%.bin.o	:	%.bin
#---------------------------------------------------------------------------------
	@echo $(notdir $<)
	@$(bin2o)

#---------------------------------------------------------------------------------
# rules for assembling GPU shaders
#---------------------------------------------------------------------------------
define shader-as
	$(eval CURBIN := $(patsubst %.shbin.o,%.shbin,$(notdir $@)))
	picasso -o $(CURBIN) $1
	bin2s $(CURBIN) | $(AS) -o $@
	echo "extern const u8" `(echo $(CURBIN) | sed -e 's/^\([0-9]\)/_\1/' | tr . _)`"_end[];" > `(echo $(CURBIN) | tr . _)`.h
	echo "extern const u8" `(echo $(CURBIN) | sed -e 's/^\([0-9]\)/_\1/' | tr . _)`"[];" >> `(echo $(CURBIN) | tr . _)`.h
	echo "extern const u32" `(echo $(CURBIN) | sed -e 's/^\([0-9]\)/_\1/' | tr . _)`_size";" >> `(echo $(CURBIN) | tr . _)`.h
endef

%.shbin.o : %.v.pica %.g.pica
	@echo $(notdir $^)
	@$(call shader-as,$^)

%.shbin.o : %.v.pica
	@echo $(notdir $<)
	@$(call shader-as,$<)

%.shbin.o : %.shlist
	@echo $(notdir $<)
	@$(call shader-as,$(foreach file,$(shell cat $<),$(dir $<)/$(file)))

-include $(DEPENDS)

#---------------------------------------------------------------------------------------
endif
#---------------------------------------------------------------------------------------

$(info $(BANNER_IMAGE_FILE))
