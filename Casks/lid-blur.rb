cask "lid-blur" do
  version "0.2.0"
  sha256 "bda5205bee433e65dafefc1697753eac74e3ca632cfdb87a2efa82d54d01046f"

  url "https://github.com/thomasmelak/lid-blur/releases/download/0.2.0/LidBlur.zip"
  name "Lid Blur"
  desc "Blurs the screen as the MacBook lid opens and closes"
  homepage "https://github.com/thomasmelak/lid-blur"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "Lid Blur.app"

  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", "{{appdir}}/Lid Blur.app"],
        must_succeed: false
    run "/usr/bin/open",
        args:         ["{{appdir}}/Lid Blur.app"],
        must_succeed: false
  end

  caveats <<~EOS
    Lid Blur lives in the menu bar (the laptop icon) and starts at login.
    Turn either off from its menu.
  EOS

  uninstall quit:      "com.thomasmelak.LidBlur",
            launchctl: "com.thomasmelak.lidblur"

  zap trash: [
    "~/Library/LaunchAgents/com.thomasmelak.lidblur.plist",
    "~/Library/Preferences/com.thomasmelak.LidBlur.plist",
  ]
end
