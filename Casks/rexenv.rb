cask "rexenv" do
  version "0.1.0"
  # sha256 of the dmg built 2026-08-08 from commit 3ae658d (clean tree).
  # MUST be re-verified against the DOWNLOADED Release asset before announcing —
  # `brew fetch` compares this against what users actually get:
  #   shasum -a 256 rexenv_0.1.0_universal.dmg
  sha256 "aed8ad6a5db446c749e249082c3f5d68e9db71d06309285d4dc107afeba641a3"

  url "https://github.com/rexenv/rexenv/releases/download/v#{version}/rexenv_#{version}_universal.dmg",
      verified: "github.com/rexenv/rexenv/"
  name "rexenv"
  desc "Native no-Docker local WordPress and web development environment"
  homepage "https://rexenv.rex.bd/"

  livecheck do
    url :url
    strategy :github_latest
  end

  # This build is AD-HOC signed, NOT notarized (no paid Apple Developer ID).
  # macOS Gatekeeper quarantines the download and refuses to launch a
  # non-notarized app while quarantined. The app IS validly code-signed (ad-hoc),
  # which satisfies the Apple Silicon "arm64 must be signed" kernel requirement —
  # so once the quarantine attribute is removed it launches normally on both
  # Apple Silicon and Intel. The postflight below removes that attribute.
  #
  # This DELIBERATELY BYPASSES Gatekeeper's notarization check. Install only if
  # you trust this source. See the tap README for the full security trade-off.

  depends_on macos: :big_sur # minimumSystemVersion 11.0

  app "rexenv.app"
  # Put the `rex` CLI on PATH automatically (the app also offers this via
  # Settings → Command-line tool; with the cask it's already done).
  binary "#{appdir}/rexenv.app/Contents/MacOS/rex"

  postflight do
    # Remove the quarantine attribute so the ad-hoc-signed app launches. Runs on
    # the freshly-copied, user-owned app in /Applications, so no sudo is needed;
    # if your setup makes /Applications root-owned, run the manual step from the
    # README instead.
    system_command "/usr/bin/xattr",
                   args: ["-r", "-d", "com.apple.quarantine", "#{appdir}/rexenv.app"],
                   sudo: false
  end

  uninstall quit: "dev.rexenv.rexenv"

  # brew can only remove USER-level state. The PRIVILEGED bits — the root edge
  # LaunchDaemon on :443, the /etc/resolver/* files, and the local-CA trust —
  # must be removed by the app FIRST: Settings → "Remove system changes" (see the
  # README). `zap` cleans the rest; the user's Sites folder (~/rexenv/Sites) is
  # intentionally left alone (that's their work).
  zap trash: [
    "~/Library/Application Support/dev.rexenv.rexenv",
    "~/Library/LaunchAgents/dev.rexenv.rexenv.dns.plist",
    "~/Library/LaunchAgents/dev.rexenv.rexenv.plist",
  ]
end
