# homebrew-tap — Homebrew tap for rexenv

Homebrew **cask** tap for [rexenv](https://rexenv.rex.bd) — a native, no-Docker local
WordPress & web development environment for macOS.

## Install

```sh
brew tap rexenv/tap
brew install --cask rexenv
```

`rex` (the CLI) is put on your PATH automatically by the cask.

## ⚠️ Security: unsigned / un-notarized (ad-hoc), and what that means

This build is **ad-hoc code-signed** (Tauri `signingIdentity: "-"`), **not notarized**
by Apple — there is no paid Apple Developer ID behind it. Consequences:

- The app **is** validly code-signed (ad-hoc), which satisfies the Apple Silicon
  requirement that arm64 code carry a signature — so it **runs** on both Apple
  Silicon and Intel.
- But macOS **Gatekeeper** quarantines any download and refuses to launch a
  non-notarized app *while it is quarantined*. To make it launch, the cask's
  `postflight` **removes the quarantine attribute** (`xattr -dr
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

The cask pins the sha256 of the exact dmg published on the
[rexenv releases page](https://github.com/rexenv/rexenv/releases).

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

The cask is updated **automatically** — see `docs/RELEASING.md` in the app repo:

1. Tag `v<version>` on [`rexenv/rexenv`](https://github.com/rexenv/rexenv) (or run the
   "Release" workflow from its Actions tab). CI builds the universal dmg, runs the
   artefact-integrity checks, and creates a **draft** release with the dmg attached.
2. A human runs the Apple-Silicon launch gate (`docs/PUBLISH-TESTING.md` §A) on the
   attached dmg, then clicks **Publish release**.
3. Publishing triggers the `update-tap` workflow, which downloads the published asset,
   computes its sha256, and pushes the `version` + `sha256` bump to this repo.
4. Users: `brew update && brew upgrade --cask rexenv`.

Only edit `Casks/rexenv.rb` by hand if the automation is broken — and then still hash
the **downloaded release asset**, never a local build.
