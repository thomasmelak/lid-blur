# Lid Blur

A tiny macOS menu bar app that blurs your screen as you open and close your MacBook's lid,
inspired by the soft unfold animation of foldable phones.

- **Triggered by the hinge.** On MacBooks with a lid angle sensor, opening the lid past a set
  angle starts a smooth, eased animation from blurred to sharp, rising from the hinge upwards.
  Open the lid fast or slow, the screen always eases into sharpness. Closing it eases back
  into the blur.
- **Works everywhere else too.** Without the sensor, Lid Blur falls back to lid open/close and
  wake events and plays the unfold animation each time the screen comes back.
- **Stays out of the way.** The overlay is click-through, only covers the built-in display,
  and the app polls the sensor slowly whenever the lid is not moving.

## Install

**Homebrew**

```sh
brew tap thomasmelak/lid-blur https://github.com/thomasmelak/lid-blur
brew install --cask lid-blur
```

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
| Clear When Lid Passes | The lid angle that triggers the clear animation (sensor Macs only) |
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
  gradient mask are animated with ease-out timing. The lid angle only triggers the animation,
  with a little hysteresis so it doesn't flicker when the lid rests near the trigger angle.
  Like a folding phone, the darkness lifts first and the blur resolves last.
- Without the sensor, the app listens for sleep/wake notifications and polls
  `AppleClamshellState`.
- Launch at login is a LaunchAgent in `~/Library/LaunchAgents/com.thomasmelak.lidblur.plist`.

## Uninstall

```sh
brew uninstall --cask lid-blur
# or
curl -fsSL https://raw.githubusercontent.com/thomasmelak/lid-blur/main/uninstall.sh | bash
```

## Releasing

Push a tag like `v0.1.0`. The release workflow builds a universal, ad-hoc signed app and
attaches `LidBlur.zip` to a GitHub release, which both the cask and the installer download.
