.PHONY: build test verify install run capture docs clean

build:
	./native/scripts/build_app.sh

test:
	swift test --package-path native --disable-automatic-resolution

verify: build
	./native/scripts/verify_app.sh

install:
	./native/scripts/install_app.sh

run:
	./script/build_and_run.sh

capture:
	./script/capture_demo.sh

docs:
	python script/check_docs.py

clean:
	rm -rf native/.build native/dist
