APP := chicago
BUILD_DIR := build
ZELDA_ENGINE_ROOT ?= ../zelda-engine
ZELDA_ENGINE_COLLECTION := -collection:zelda_engine=$(abspath $(ZELDA_ENGINE_ROOT))/packages
TEXTSHAPE_LIBS := $(shell pkg-config --libs harfbuzz freetype2 2>/dev/null)
ifeq ($(shell uname -s),Darwin)
LINKER_WARNING_FLAGS := -Wl,-no_warn_duplicate_libraries -framework Cocoa
EDITOR_MENU_LIB := third_party/libchicago_editor_menu.a
endif
TOMLC17_DIR := third_party/tomlc17
TOMLC17_LIB := $(TOMLC17_DIR)/libtomlc17.a
STB_VORBIS_LIB := third_party/libstb_vorbis.a
WALL_GEOM_LIB := third_party/libwall_geom.a
TEXTSHAPE_LIB := third_party/libtextshape.a
ENGINE_TEXTSHAPE_LIB := $(abspath $(ZELDA_ENGINE_ROOT))/third_party/textshape/libtextshape.a
CLIPPER2_DIR := third_party/clipper2/CPP/Clipper2Lib
ODINFMT ?= odinfmt
ODIN_SOURCE_DIRS := src tools/gltf-viewer

.PHONY: run build macos-app check check-3d check-blender-y-up check-mystery-prop-scale format format-check test story-core-test story-validate story-export story-inspect story-install expansion-export expansion-inspect expansion-install expansion-enable expansion-disable expansion-uninstall scenario-test conversion-test vehicle-test package-test agent-tools-test clean gltf-viewer shaders catalog-thumbnails theme-knoll-screenshot campaign-export campaign-import campaign-inspect

PYTHON ?= python3
OUT ?= build/the-torn-appointment-1.0.0.zip
STORY_OUT ?= build/the-lantern-visit-1.0.0.zip

SLANGC ?= $(shell command -v slangc 2>/dev/null)
SHADER_DIR := build/shaders
PRECOMPILED_SHADER_DIR := assets/shaders/precompiled
GLTF_SHADER := assets/shaders/gltf_pbr.slang
GLTF_VERT_SPV := $(SHADER_DIR)/gltf_pbr.vert.spv
GLTF_FRAG_SPV := $(SHADER_DIR)/gltf_pbr.frag.spv
UI_SHADER := assets/shaders/ui.slang
UI_VERT_SPV := $(SHADER_DIR)/ui.vert.spv
UI_FRAG_SPV := $(SHADER_DIR)/ui.frag.spv
UI_COLOR_SHADER := assets/shaders/ui_color.slang
UI_COLOR_VERT_SPV := $(SHADER_DIR)/ui_color.vert.spv
UI_COLOR_FRAG_SPV := $(SHADER_DIR)/ui_color.frag.spv
WORLD_SHADER := assets/shaders/world.slang
WORLD_VERT_SPV := $(SHADER_DIR)/world.vert.spv
WORLD_FRAG_SPV := $(SHADER_DIR)/world.frag.spv
SHADOW_SHADER := assets/shaders/shadow.slang
SHADOW_VERT_SPV := $(SHADER_DIR)/shadow.vert.spv
FXAA_VERT_SPV := $(SHADER_DIR)/fxaa.vert.spv
FXAA_FRAG_SPV := $(SHADER_DIR)/fxaa.frag.spv

run: build
	$(BUILD_DIR)/$(APP)

build: shaders $(TOMLC17_LIB) $(STB_VORBIS_LIB) $(WALL_GEOM_LIB) $(TEXTSHAPE_LIB) $(EDITOR_MENU_LIB)
	mkdir -p $(BUILD_DIR)
	odin build src $(ZELDA_ENGINE_COLLECTION) -out:$(BUILD_DIR)/$(APP) -extra-linker-flags:"$(TEXTSHAPE_LIBS) -lc++ $(LINKER_WARNING_FLAGS)"

macos-app: build
	SKIP_BUILD=1 BUILD_DIR="$(abspath $(BUILD_DIR))" tools/package_macos.sh

check: $(TOMLC17_LIB) $(WALL_GEOM_LIB) $(EDITOR_MENU_LIB)
	$(PYTHON) tools/check_authoring_boundary.py
	$(PYTHON) tools/check_capture_fixtures.py
	odin check src $(ZELDA_ENGINE_COLLECTION)

third_party/libchicago_editor_menu.a: third_party/chicago_editor_menu.m
	clang -fobjc-arc -c $< -o third_party/chicago_editor_menu.o
	ar rcs $@ third_party/chicago_editor_menu.o

check-3d:
	odin check tools/gltf-viewer $(ZELDA_ENGINE_COLLECTION)

check-blender-y-up:
	$(PYTHON) tools/check_blender_y_up.py

check-mystery-prop-scale:
	$(PYTHON) tools/check_mystery_prop_scale.py

format:
	@command -v $(ODINFMT) >/dev/null || { echo "odinfmt is required; see README.md" >&2; exit 1; }
	@$(PYTHON) tools/format_odin.py --formatter $(ODINFMT) --config odinfmt.json $(ODIN_SOURCE_DIRS)

format-check:
	@command -v $(ODINFMT) >/dev/null || { echo "odinfmt is required; see README.md" >&2; exit 1; }
	@$(PYTHON) tools/format_odin.py --check --formatter $(ODINFMT) --config odinfmt.json $(ODIN_SOURCE_DIRS)

test: build
	$(BUILD_DIR)/$(APP) --self-test
	$(PYTHON) -m unittest tests/test_campaign_package.py tests/test_interactive_story_package.py tests/test_expansion_package.py tests/test_mystery_conversion.py

story-core-test: build
	$(BUILD_DIR)/$(APP) --story-core-test

story-validate: build
	$(BUILD_DIR)/$(APP) --validate-story "$(STORY)"

story-export: build
	$(PYTHON) tools/interactive_story_package.py export "$(STORY_OUT)"

story-inspect:
	$(PYTHON) tools/interactive_story_package.py inspect "$(PACKAGE)"

story-install:
	$(PYTHON) tools/interactive_story_package.py install "$(PACKAGE)"

scenario-test: build
	$(BUILD_DIR)/$(APP) --scenario-test assets/scenarios/the_torn_appointment.toml
	$(BUILD_DIR)/$(APP) --campaign-scenario-test

conversion-test:
	$(PYTHON) -m unittest tests/test_mystery_conversion.py

vehicle-test: build
	$(BUILD_DIR)/$(APP) --vehicle-self-test

package-test:
	$(PYTHON) -m unittest tests/test_campaign_package.py tests/test_interactive_story_package.py tests/test_expansion_package.py

expansion-export:
	$(PYTHON) tools/expansion_package.py export "$(OUT)"

expansion-inspect:
	$(PYTHON) tools/expansion_package.py inspect "$(PACKAGE)"

expansion-install:
	$(PYTHON) tools/expansion_package.py install "$(PACKAGE)"

expansion-enable:
	$(PYTHON) tools/expansion_package.py enable "$(EXPANSION)"

expansion-disable:
	$(PYTHON) tools/expansion_package.py disable "$(EXPANSION)"

expansion-uninstall:
	$(PYTHON) tools/expansion_package.py uninstall "$(EXPANSION)"

agent-tools-test:
	$(PYTHON) -m unittest tests/test_interior_agent.py

campaign-export:
	$(PYTHON) tools/campaign_package.py export "$(OUT)"

campaign-import:
	@test -n "$(PACKAGE)" || (echo "usage: make campaign-import PACKAGE=path/to/campaign.mysterycampaign" >&2; exit 2)
	$(PYTHON) tools/campaign_package.py import "$(PACKAGE)"

campaign-inspect:
	@test -n "$(PACKAGE)" || (echo "usage: make campaign-inspect PACKAGE=path/to/campaign.mysterycampaign" >&2; exit 2)
	$(PYTHON) tools/campaign_package.py inspect "$(PACKAGE)"

catalog-thumbnails: build
	./tools/bake_catalog_thumbnails.sh

theme-knoll-screenshot: build
	./tools/capture_theme_knoll.sh build/chicago build/theme-knoll-full.png

gltf-viewer: shaders $(TOMLC17_LIB)
	mkdir -p $(BUILD_DIR)
	odin build tools/gltf-viewer $(ZELDA_ENGINE_COLLECTION) -out:$(BUILD_DIR)/gltf-viewer -extra-linker-flags:"$(TEXTSHAPE_LIBS) $(LINKER_WARNING_FLAGS)"

shaders: $(GLTF_VERT_SPV) $(GLTF_FRAG_SPV) $(UI_VERT_SPV) $(UI_FRAG_SPV) $(UI_COLOR_VERT_SPV) $(UI_COLOR_FRAG_SPV) $(WORLD_VERT_SPV) $(WORLD_FRAG_SPV) $(SHADOW_VERT_SPV) $(FXAA_VERT_SPV) $(FXAA_FRAG_SPV)

define compile-slang
	@if [ -n "$(SLANGC)" ]; then \
		"$(SLANGC)" $< -target spirv -profile spirv_1_5 -stage $(1) -entry $(2) -o $@; \
	else \
		shader_fallback="$(PRECOMPILED_SHADER_DIR)/$(notdir $@).b64"; \
		if [ ! -f "$$shader_fallback" ]; then \
			echo "missing precompiled shader fallback: $$shader_fallback" >&2; \
			exit 1; \
		elif [ "$<" -nt "$$shader_fallback" ]; then \
			echo "shader source is newer than $$shader_fallback; install slangc or regenerate the fallback" >&2; \
			exit 1; \
		fi; \
		openssl base64 -d -A -in "$$shader_fallback" -out $@; \
	fi
endef

$(GLTF_VERT_SPV): $(GLTF_SHADER)
	mkdir -p $(SHADER_DIR)
	$(call compile-slang,vertex,vertex_main)

$(GLTF_FRAG_SPV): $(GLTF_SHADER)
	mkdir -p $(SHADER_DIR)
	$(call compile-slang,fragment,fragment_main)

$(UI_VERT_SPV): $(UI_SHADER)
	mkdir -p $(SHADER_DIR)
	$(call compile-slang,vertex,vertex_main)

$(UI_FRAG_SPV): $(UI_SHADER)
	mkdir -p $(SHADER_DIR)
	$(call compile-slang,fragment,fragment_main)

$(UI_COLOR_VERT_SPV): $(UI_COLOR_SHADER)
	mkdir -p $(SHADER_DIR)
	$(call compile-slang,vertex,vertex_main)

$(UI_COLOR_FRAG_SPV): $(UI_COLOR_SHADER)
	mkdir -p $(SHADER_DIR)
	$(call compile-slang,fragment,fragment_main)

$(WORLD_VERT_SPV): $(WORLD_SHADER)
	mkdir -p $(SHADER_DIR)
	$(call compile-slang,vertex,vertex_main)

$(WORLD_FRAG_SPV): $(WORLD_SHADER)
	mkdir -p $(SHADER_DIR)
	$(call compile-slang,fragment,fragment_main)

$(SHADOW_VERT_SPV): $(SHADOW_SHADER)
	mkdir -p $(SHADER_DIR)
	$(call compile-slang,vertex,vertex_main)

$(FXAA_VERT_SPV): assets/shaders/fxaa.vert
	mkdir -p $(SHADER_DIR)
	@if command -v glslangValidator >/dev/null 2>&1; then glslangValidator -V $< -o $@; else openssl base64 -d -A -in $(PRECOMPILED_SHADER_DIR)/$(notdir $@).b64 -out $@; fi

$(FXAA_FRAG_SPV): assets/shaders/fxaa.frag
	mkdir -p $(SHADER_DIR)
	@if command -v glslangValidator >/dev/null 2>&1; then glslangValidator -V $< -o $@; else openssl base64 -d -A -in $(PRECOMPILED_SHADER_DIR)/$(notdir $@).b64 -out $@; fi

$(TOMLC17_LIB): $(TOMLC17_DIR)/tomlc17.c $(TOMLC17_DIR)/tomlc17.h
	$(CC) -O2 -c $(TOMLC17_DIR)/tomlc17.c -o $(TOMLC17_DIR)/tomlc17.o
	ar rcs $(TOMLC17_LIB) $(TOMLC17_DIR)/tomlc17.o

$(STB_VORBIS_LIB): third_party/stb_vorbis.c third_party/stb_vorbis_wrapper.c
	$(CC) -O2 -c third_party/stb_vorbis.c -o third_party/stb_vorbis.o
	$(CC) -O2 -c third_party/stb_vorbis_wrapper.c -o third_party/stb_vorbis_wrapper.o
	ar rcs $(STB_VORBIS_LIB) third_party/stb_vorbis.o third_party/stb_vorbis_wrapper.o

$(TEXTSHAPE_LIB): $(ENGINE_TEXTSHAPE_LIB)
	cp $< $@

$(WALL_GEOM_LIB): third_party/wall_geom.cpp third_party/wall_geom.h $(CLIPPER2_DIR)/src/clipper.engine.cpp $(CLIPPER2_DIR)/src/clipper.offset.cpp $(CLIPPER2_DIR)/src/clipper.rectclip.cpp
	$(CXX) -std=c++17 -O2 -I$(CLIPPER2_DIR)/include -c third_party/wall_geom.cpp -o third_party/wall_geom.o
	$(CXX) -std=c++17 -O2 -I$(CLIPPER2_DIR)/include -c $(CLIPPER2_DIR)/src/clipper.engine.cpp -o third_party/clipper.engine.o
	$(CXX) -std=c++17 -O2 -I$(CLIPPER2_DIR)/include -c $(CLIPPER2_DIR)/src/clipper.offset.cpp -o third_party/clipper.offset.o
	$(CXX) -std=c++17 -O2 -I$(CLIPPER2_DIR)/include -c $(CLIPPER2_DIR)/src/clipper.rectclip.cpp -o third_party/clipper.rectclip.o
	ar rcs $(WALL_GEOM_LIB) third_party/wall_geom.o third_party/clipper.engine.o third_party/clipper.offset.o third_party/clipper.rectclip.o

clean:
	rm -rf $(BUILD_DIR)
