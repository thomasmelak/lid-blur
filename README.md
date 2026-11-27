# Lid Blur

A tiny macOS menu bar app that blurs your screen as you open and close your MacBook's lid,
inspired by the soft unfold animation of foldable phones.

- **Follows the hinge, smoothly.** On MacBooks with a lid angle sensor, the blur is tied to
  the angle of the lid: close it and the screen melts into a blur, open it and the picture
  sharpens from the hinge upwards. The screen follows the lid through an easing spring, so a
  slow lid is tracked closely and a lid opened quickly still glides into sharpness.
- **Works everywhere else too.** Without the sensor, Lid Blur falls back to lid open/close and
  wake events and plays the unfold animation each time the screen comes back.
- **Stays out of the way.** The overlay is click-through, only covers the built-in display,
  and the app polls the sensor slowly whenever the lid is not moving.

## Install

**Download**

Grab [LidBlur.dmg](https://github.com/thomasmelak/lid-blur/releases/latest/download/LidBlur.dmg),
open it and drag **Lid Blur** onto **Applications**. The app isn't notarized by Apple, so the
first time you open it macOS will refuse; go to System Settings > Privacy & Security and click
**Open Anyway** (or run `xattr -dr com.apple.quarantine "/Applications/Lid Blur.app"`).

**Homebrew**

```sh
brew tap thomasmelak/lid-blur https://github.com/thomasmelak/lid-blur
brew trust thomasmelak/lid-blur
brew install --cask lid-blur
```

Current Homebrew refuses casks from a tap you haven't trusted, hence `brew trust`; older
versions don't have the command and can skip that line.

Homebrew clears the quarantine flag for you, so the app opens straight away. Update with
`brew upgrade --cask lid-blur`.

**One-line installer**

```sh
curl -fsSL https://raw.githubusercontent.com/thomasmelak/lid-blur/main/install.sh | bash
```

The installer downloads the latest release into `/Applications` and starts it. If no release
has been published yet it builds the app from source, which needs the Xcode Command Line Tools
(`xcode-select --install`).

**From source**

```sh
git clone https://github.com/thomasmelak/lid-blur.git
cd lid-blur
make install
```

## Using it

Lid Blur lives in the menu bar (the laptop icon). From there you can:

| Option | What it does |
| --- | --- |
| Enabled | Turns the effect on or off |
| Preview Animation | Plays the blur so you can try settings without moving the lid |
| Style | **Gradient** blurs the whole screen, softer towards the hinge; **Uniform** blurs evenly |
| Intensity | Subtle, Normal or Strong |
| 3D Depth | The picture sits behind the glass, smaller and tilted back, and rises forward as the lid opens. Uses Screen Recording to redraw the screen; without it the blur still works, flat |
| Fully sharp from … | Slider for the lid angle at which the screen is fully sharp, 30° to 130° (sensor Macs only) |
| Use Current Lid Angle | Sets that angle to wherever your lid is right now |
| Launch at Login | Starts Lid Blur when you log in (on by default) |

## Which Macs have the lid angle sensor?

The hinge sensor is present on the 16-inch MacBook Pro (2019) and on most Apple silicon
MacBook Air and MacBook Pro models from 2021 onwards. The first line of the menu tells you
whether yours was found; if not, the app uses open/close events instead.

Note: if *Reduce transparency* is on in System Settings > Accessibility > Display, macOS
replaces blurs with a solid tint, so the effect becomes a fade.

## How it works

- The hinge angle is read from Apple's HID sensor device (usage page `0x20`, usage `0x8A`,
  feature report 1). No special permissions are needed.
- The blur is a borderless, click-through window above everything on the built-in display,
  hosting a Core Animation backdrop layer with a variable blur. The radius itself is the
  gradient: strongest at the top, softer towards the hinge, never zero while the lid is
  opening, so no part of the screen is left sharp. The radius and darkening follow the lid angle through a smoothstep curve and a critically damped
  spring, which eases every movement without overshooting. Like a folding phone, the
  darkness lifts first and the blur resolves last.
- Without the sensor, the app listens for sleep/wake notifications and polls
  `AppleClamshellState`.
- Launch at login is a LaunchAgent in `~/Library/LaunchAgents/com.thomasmelak.lidblur.plist`.

## Uninstall

Any of these removes the app, its login item and its settings:

- From the menu bar icon: **Uninstall Lid Blur…**
- Homebrew: `brew uninstall --cask --zap lid-blur`
- Script: `curl -fsSL https://raw.githubusercontent.com/thomasmelak/lid-blur/main/uninstall.sh | bash`
  (or `make uninstall` in a clone)

## Releasing

Push a tag like `v0.1.0`, or run the **Release** workflow from the Actions tab with a tag name.
It runs the tests, builds a universal app, and publishes `LidBlur.zip` and
`LidBlur.dmg` to a GitHub release. The one-line installer and the download link always point
at the latest release. The workflow also opens a pull request that bumps the version and
sha256 in `Casks/lid-blur.rb`; merge it and `brew upgrade` offers the new version.

### Signing

Builds are signed with a self-signed certificate when the `MACOS_SIGNING_CERT` and
`MACOS_SIGNING_CERT_PASSWORD` repository secrets are set, and ad hoc otherwise. A stable
certificate keeps the Screen Recording permission across updates; with ad hoc signing macOS asks
again after every build. `scripts/make-signing-cert.sh` creates the certificate and stores both
secrets with the GitHub CLI. For local builds, pass `SIGN_IDENTITY` to `scripts/build-app.sh`.
