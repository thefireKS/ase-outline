ASEPRITE ?= /Applications/Aseprite.app/Contents/MacOS/aseprite

EXT      ?= ase-outline
EXT_DIR  ?= $(HOME)/Library/Application Support/Aseprite/extensions/$(EXT)
BUNDLE   ?= dist/$(EXT).aseprite-extension

.PHONY: all test extension install uninstall clean

all: test

## Both suites write their renders to out/ for eyeballing.
test:
	@$(ASEPRITE) -b --script tests/outline_test.lua
	@$(ASEPRITE) -b --script tests/modes_test.lua

## A .aseprite-extension is a zip; Aseprite installs it on double-click.
extension:
	@mkdir -p dist
	@rm -f $(BUNDLE)
	@zip -q -r $(BUNDLE) package.json main.lua src
	@echo "$(BUNDLE)"

## Straight into the extensions folder, skipping the installer. Aseprite reads
## extensions once at startup, so restart it after this.
install:
	@mkdir -p "$(EXT_DIR)"
	@cp package.json main.lua "$(EXT_DIR)/"
	@rm -rf "$(EXT_DIR)/src" && cp -R src "$(EXT_DIR)/src"
	@echo "installed to $(EXT_DIR) -- restart Aseprite"

uninstall:
	@rm -rf "$(EXT_DIR)"
	@echo "removed $(EXT_DIR)"

clean:
	@rm -rf out dist
