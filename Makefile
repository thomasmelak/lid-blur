.PHONY: build app dmg test run install uninstall clean

build:
	swift build

test:
	swift test

app:
	scripts/build-app.sh

dmg: app
	scripts/build-dmg.sh

run: app
	open "build/Lid Blur.app"

install: app
	pkill -x LidBlur 2>/dev/null || true
	rm -rf "/Applications/Lid Blur.app"
	ditto "build/Lid Blur.app" "/Applications/Lid Blur.app"
	open "/Applications/Lid Blur.app"

uninstall:
	./uninstall.sh

clean:
	rm -rf .build build
