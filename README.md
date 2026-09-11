# homebrew-tap — Homebrew tap for rexenv

Homebrew **cask** tap for [rexenv](https://rexenv.rex.bd) — a native, no-Docker local
WordPress & web development environment for macOS.

## Install

```sh
brew tap rexenv/tap
brew trust rexenv/tap        # current Homebrew refuses to load a third-party tap
brew install --cask rexenv   # until you trust it — this is that opt-in
```

If you skip the middle line, `brew install` stops with *"Refusing to load cask
rexenv/tap/rexenv from untrusted tap"*. Trusting a tap means you accept that its casks
run arbitrary code on your machine (this one's `postflight_steps` removes the quarantine
attribute — see the security note below). `brew trust --cask rexenv/tap/rexenv` trusts
just this cask instead of the whole tap.

`rex` (the CLI) is put on your PATH automatically by the cask.

## Update

**rexenv updates itself.** From 0.6.0 on, the app checks for a new release, tells you
one is there, and installs it when you say so — Settings → About → Updates, or the
menu-bar icon. Nothing to run, and it works the same whether you installed with brew or by
dragging the dmg.

The cask declares `auto_updates true` to match, so **a plain `brew upgrade` leaves rexenv
alone** — that is what stops brew and the app from installing over each other.
`brew info --cask rexenv` reads the version out of the installed app, so it still tells
you the truth after an in-app update.

**Naming the cask overrides that**, and this is the part that surprises people:

```sh
brew upgrade              # skips rexenv — the app is its own updater
brew upgrade --cask rexenv   # ACTS. Naming a cask means you asked for it.
```

If you would rather have brew do it, or the in-app update failed, run `brew update` first
so your tap checkout knows about the newest release, then upgrade or reinstall.

Notes:

- **Naming the cask, `--greedy` and `reinstall` can all move you BACKWARDS.** Each
  installs the version *your local tap checkout* names, and the app may have updated
  itself past it. Measured 7 Sep 2026: `brew upgrade --cask rexenv` on a machine whose
  tap was a release behind replaced a self-updated 0.6.1 with 0.6.0, without a word about
  going backwards. Nothing breaks — the app notices at its next check and offers the
  newer build again — but `brew update` first, and prefer letting the app update itself.
- **Quit rexenv first** if you are using brew. Homebrew quits the app
  (`dev.rexenv.rexenv`) for you, but a running site stack is cleaner stopped from the
  app. An in-app update handles this itself: it quits, swaps, and relaunches.
- **Turning it off:** Settings → About → Updates → untick *“Check for new releases
  automatically”*. rexenv then contacts nothing on its own; *Check now* still works,
  and `brew upgrade --cask rexenv --greedy` becomes your updater.
- The quarantine-removing `postflight_steps` re-runs on every upgrade, so the new build
  launches the same way the first install did — no extra `xattr` step.
- Your data survives an upgrade: `~/rexenv/Sites` and `~/Library/Application
  Support/dev.rexenv.rexenv` are untouched (only `--zap` on *uninstall* touches the
  latter).
- The **privileged system bits** (root edge daemon on :443, `/etc/resolver/*`, local
  CA) are not touched by brew — they stay installed across an upgrade. Anything a new
  release needs there is handled by the app itself, not by the cask.

Check what you have vs. what's published:

```sh
brew info --cask rexenv      # installed version + the tap's current version
```

## ⚠️ Security: unsigned / un-notarized (ad-hoc), and what that means

This build is **ad-hoc code-signed** (Tauri `signingIdentity: "-"`), **not notarized**
by Apple — there is no paid Apple Developer ID behind it. Consequences:

- The app **is** validly code-signed (ad-hoc), which satisfies the Apple Silicon
  requirement that arm64 code carry a signature — so it **runs** on both Apple
  Silicon and Intel.
- But macOS **Gatekeeper** quarantines any download and refuses to launch a
  non-notarized app *while it is quarantined*. To make it launch, the cask's
  `postflight_steps` **removes the quarantine attribute** (`xattr -dr
  com.apple.quarantine`). **This deliberately bypasses Gatekeeper's notarization
  check.**

Install this **only if you trust this source** — you are choosing to run an
un-notarized build. If the postflight can't remove the attribute on your setup,
run it yourself once:

```sh
sudo xattr -rd com.apple.quarantine /Applications/rexenv.app
```

A future signed + notarized build (with a Developer ID) removes the need for any of
this — see `docs/SIGNING.md` in the app repo.

## Verifying what you downloaded

```sh
brew fetch --cask rexenv     # fails loudly if the dmg doesn't match the cask's sha256
```

The cask pins the sha256 of the exact dmg published on
[this repo's releases page](https://github.com/rexenv/homebrew-tap/releases).

**Why the dmg is released here and not on the app repo:** rexenv's source repo is
private for now, and Homebrew downloads a cask's url with no authentication — a
private repo's release asset would answer 404 to every user. So the *artefact* is
published in this public tap while the *source* stays private. It is the same dmg
the app's release pipeline builds, and its hash is still taken from the downloaded
asset, never a local build. When the app repo goes public the url moves back to it.

## Uninstall — do the in-app step FIRST

rexenv installs **privileged, system-level** things that Homebrew **cannot** remove:
a **root LaunchDaemon** running the edge proxy on **:443**, `/etc/resolver/*` files,
and a **local-CA trust** in your login keychain. Before uninstalling:

1. In the app: **Settings → "Remove system changes"** (removes the root edge daemon,
   DNS resolver files, and CA trust — one admin prompt).
2. Then:
   ```sh
   brew uninstall --cask rexenv          # removes the app + the `rex` symlink
   brew uninstall --zap --cask rexenv    # also trashes ~/Library app-data + LaunchAgents
   ```

`--zap` intentionally leaves your **`~/rexenv/Sites`** folder alone (that's your work).

## Releasing a new version (maintainers)

The cask is updated **automatically** — see `docs/RELEASING.md` in the app repo. While
the app repo is private, the dmg is built on a maintainer's Mac and released **here**:

1. In the app repo: `./scripts/verify.sh`, then `pnpm release:mac` → the universal dmg.
2. A human runs `docs/PUBLISH-TESTING.md` §A0 + §A (artefact integrity, then the
   Apple-Silicon launch gate) on that exact dmg.
3. `gh release create v<version> --repo rexenv/homebrew-tap <dmg> <dmg>.sha256` — draft
   it if §A hasn't been run yet; **publishing is the sign-off**.
4. This repo's **Update cask** workflow runs on that publish (`release: published` — it
   used to poll a `*/15` cron, which GitHub ran hours apart; run it by hand from the
   Actions tab if it did not fire), downloads the asset, computes its sha256, and pushes
   the `version` + `sha256` bump here. No token or secret involved — it pushes to its
   own repo with the built-in `GITHUB_TOKEN`.
5. In [`rexenv/runtimes`](https://github.com/rexenv/runtimes): **Actions → “Publish
   app update manifest”** (dry run first). **This is the click that is easy to forget.**
   Until it runs, every installed rexenv keeps reporting it is already current — no
   error, no log, nothing. The cask bump above does not tell a single running app
   anything. Verify with `scripts/check-app-manifest.sh` in the app repo.
6. Users: nothing. Their app offers the update at its next check.

When [`rexenv/rexenv`](https://github.com/rexenv/rexenv) goes public, steps 1–3 go back
to being CI's job (tag → draft release with the dmg → publish), and `SOURCE_REPO` in
`update-cask.yml` plus the cask's `url` move back to the app repo — those three must
change in one commit. **That commit must also give `update-cask.yml` a trigger again**:
it fires on THIS repo's release event, and a release published in the app repo never
sends one here. (There is no `verified:` any more: brew 6.0.22 deprecated it in
favour of its default URL verification.) The app's `ALLOWED_RELEASE_PREFIXES` already
accepts both hosts, so update descriptors keep verifying across that move.

Only edit `Casks/rexenv.rb` by hand if the automation is broken — and then still hash
the **downloaded release asset**, never a local build.
