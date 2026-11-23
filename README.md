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
brew install --cask lid-blur
```

Homebrew clears the quarantine flag for you, so the app opens straight away. Update with
`brew upgrade --cask --greedy lid-blur`.

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
| Style | **Unfold** clears from the bottom up, **Uniform** fades evenly |
| Intensity | Subtle, Normal or Strong |
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
- The blur is a borderless, click-through `NSVisualEffectView` window above everything on
  the built-in display. Its opacity, darkening and (for the Unfold style) a bottom-to-top
  gradient mask follow the lid angle through a smoothstep curve and a critically damped
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
It runs the tests, builds a universal, ad-hoc signed app, and publishes `LidBlur.zip` and
`LidBlur.dmg` to a GitHub release. The Homebrew cask, the one-line installer and the download
link above always point at the latest release, so nothing else needs updating.
