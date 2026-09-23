cask "rexenv" do
  version "0.8.6"
  # version + sha256 are bumped AUTOMATICALLY by this repo's update-cask workflow
  # when a Release is published; the hash is computed from the DOWNLOADED release
  # asset, never a local build. Don't edit them by hand unless the automation is
  # broken.
  sha256 "4ba6bf428f5d82e73ff31ec1616a670a2093167dfdc1746a63a5b4d7d5a1403b"

  # INTERIM HOST — the dmg is released HERE, not on rexenv/rexenv, because the app
  # repo is still private and `brew` fetches this URL anonymously: a private repo's
  # release asset answers 404 to an unauthenticated GET, so a cask pointing at it
  # cannot install for anyone. The SOURCE stays private; only the artefact is public.
  # When rexenv/rexenv goes public, flip this url back to github.com/rexenv/rexenv
  # and the SOURCE_REPO env in update-cask.yml with it. No `verified:` here: brew
  # 6.0.22 deprecated that parameter in favour of its default URL verification
  # (warned 5 Sep 2026), and the url's host is the check now.
  url "https://github.com/rexenv/homebrew-tap/releases/download/v#{version}/rexenv_#{version}_universal.dmg"
  name "rexenv"
  desc "Native no-Docker local WordPress and web development environment"
  homepage "https://rexenv.rex.bd/"

  livecheck do
    url :url
    strategy :github_latest
  end

  # rexenv updates ITSELF from 0.6.0 on: it checks a signed descriptor in
  # rexenv/runtimes and, when the user accepts, replaces /Applications/rexenv.app
  # with the bundle that release published. Declaring that here is not a
  # preference, it is the truth — and it changes three things:
  #
  #   1. A plain `brew upgrade` SKIPS rexenv. Homebrew leaves auto-updating casks
  #      alone, which is what stops brew and the app from both installing over
  #      each other.
  #   2. `brew upgrade --cask rexenv` still ACTS — naming a cask means the user
  #      asked for it, and auto_updates does not override an explicit request.
  #      So do `--greedy` and `reinstall`. All three install whatever the user's
  #      LOCAL tap checkout says, so any of them can DOWNGRADE an app that
  #      updated itself past it. Measured 7 Sep 2026: the named form put 0.6.0
  #      back over a self-updated 0.6.1 on a Mac whose tap was one release
  #      behind, silently. Nothing breaks — the app re-offers at its next check —
  #      but this line said "with or without a cask named" until that happened,
  #      which is how a comment nobody tested becomes the thing that misleads.
  #   3. Homebrew stops treating its own receipt as the installed version and
  #      reads `CFBundleShortVersionString` out of the installed app instead
  #      (brew's auto_updates handling, since 5 Apr 2026). `brew info --cask
  #      rexenv` therefore reports what is actually in /Applications, which is
  #      the whole point: after an in-app update it no longer lies.
  #
  # Removing this line without removing the in-app updater brings back exactly
  # the collision it exists to prevent: brew reinstalling an older bundle under
  # a running app that just replaced itself.
  auto_updates true
  # This build is AD-HOC signed, NOT notarized (no paid Apple Developer ID).
  # macOS Gatekeeper quarantines the download and refuses to launch a
  # non-notarized app while quarantined. The app IS validly code-signed (ad-hoc),
  # which satisfies the Apple Silicon "arm64 must be signed" kernel requirement —
  # so once the quarantine attribute is removed it launches normally on both
  # Apple Silicon and Intel. The postflight below removes that attribute.
  #
  # This DELIBERATELY BYPASSES Gatekeeper's notarization check. Install only if
  # you trust this source. See the tap README for the full security trade-off.

  # The app's floor is set by the BINARIES the default stack needs, not by the
  # app's own code: nginx 1.30.3 and cloudflared 2026.6.1 are both built with a
  # 15.0 deployment target (`docs/PORTS.md` in the app repo). Below 15 the app
  # installs and launches and then its web server cannot start — which is the
  # worst shape of failure, because it looks like a bug in rexenv rather than an
  # unmet requirement.
  #
  # A bare symbol here means ">= that version": `DependsOn#macos=` parses with
  # `comparator: ">="` and `MacOSRequirement.parse` keeps that default for a
  # Symbol. Checked in Homebrew's source, not assumed. So this refuses macOS
  # 11–14 at INSTALL time, which is where a requirement belongs.
  #
  # **Do not "clarify" this to `">= :sequoia"`.** The string comparison form is
  # DEPRECATED — `MacOSRequirement.parse` matches it, calls `odeprecated`, and
  # names this exact bare-symbol line as the replacement. The explicit-looking
  # version is the one that breaks.
  #
  # This said `:big_sur` from 0.1.0 through 0.3.0, four releases after the app's
  # `minimumSystemVersion` moved to 15.0 — and the trailing comment restating
  # "11.0" is why nobody noticed: it pinned a NUMBER the app repo was free to
  # change without telling this file. It is not restated here on purpose. The
  # app repo now carries the tripwire (`the_macos_floor_matches_the_shipped_cask`),
  # which fails ITS build naming this line and the symbol to use.
  depends_on macos: :ventura

  app "rexenv.app"
  # Put the `rex` CLI on PATH automatically (the app also offers this via
  # Settings → Command-line tool; with the cask it's already done).
  binary "#{appdir}/rexenv.app/Contents/MacOS/rex"

  # Declarative steps, not a Ruby `postflight` block: Homebrew deprecated the
  # flight blocks (brew 6, `Cask/InstallSteps`) and `brew fetch` warned on the
  # 0.5.0 bump, 5 Sep 2026. Steps are serialised to the JSON API, so `{{appdir}}`
  # is an install-time token, not Ruby interpolation. `run` aborts the install
  # on a non-zero exit; `xattr -r -d` exits 0 even where the attribute is absent
  # (checked on a mixed tree), so an already-clean app does not fail the step.
  postflight_steps do
    # Remove the quarantine attribute so the ad-hoc-signed app launches. Runs on
    # the freshly-copied, user-owned app in /Applications, so no sudo is needed;
    # if your setup makes /Applications root-owned, run the manual step from the
    # README instead.
    run "/usr/bin/xattr",
        args: ["-r", "-d", "com.apple.quarantine", "{{appdir}}/rexenv.app"]
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
