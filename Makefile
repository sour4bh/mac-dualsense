APP_NAME := CC Controller Native
BUILT_APP := native/dist/$(APP_NAME).app
INSTALLED_APP := /Applications/$(APP_NAME).app

.PHONY: build install run clean

## build: produce a .app bundle under native/dist/
build:
	./native/scripts/build_app.sh

## install: build and copy into /Applications (does not launch)
install: build
	rm -rf "$(INSTALLED_APP)"
	ditto "$(BUILT_APP)" "$(INSTALLED_APP)"
	@echo "Installed: $(INSTALLED_APP)"

## run: install and launch the app
run: install
	open "$(INSTALLED_APP)"

## clean: remove local build artifacts
clean:
	rm -rf native/.build native/dist
