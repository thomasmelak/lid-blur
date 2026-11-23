cask "lid-blur" do
  version :latest
  sha256 :no_check

  url "https://github.com/thomasmelak/lid-blur/releases/latest/download/LidBlur.zip"
  name "Lid Blur"
  desc "Blurs the screen as the MacBook lid opens and closes"
  homepage "https://github.com/thomasmelak/lid-blur"

  depends_on macos: ">= :ventura"

  app "Lid Blur.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Lid Blur.app"]
    system_command "/usr/bin/open", args: ["#{appdir}/Lid Blur.app"]
  end

  uninstall quit:      "com.thomasmelak.LidBlur",
            launchctl: "com.thomasmelak.lidblur"

  zap trash: [
    "~/Library/LaunchAgents/com.thomasmelak.lidblur.plist",
    "~/Library/Preferences/com.thomasmelak.LidBlur.plist",
  ]
end
