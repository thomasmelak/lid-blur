.PHONY: build app test run install clean

build:
	swift build

test:
	swift test

app:
	scripts/build-app.sh

run: app
	open "build/Lid Blur.app"

install: app
	pkill -x LidBlur 2>/dev/null || true
	rm -rf "/Applications/Lid Blur.app"
	ditto "build/Lid Blur.app" "/Applications/Lid Blur.app"
	open "/Applications/Lid Blur.app"

clean:
	rm -rf .build build
