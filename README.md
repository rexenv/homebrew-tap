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
run arbitrary code on your machine (this one's `postflight` removes the quarantine
attribute — see the security note below). `brew trust --cask rexenv/tap/rexenv` trusts
just this cask instead of the whole tap.

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
4. This repo's **Update cask** workflow (polls every 15 min; or run it by hand from the
   Actions tab) sees the new published release, downloads the asset, computes its
   sha256, and pushes the `version` + `sha256` bump here. No token or secret involved —
   it pushes to its own repo with the built-in `GITHUB_TOKEN`.
5. Users: `brew update && brew upgrade --cask rexenv`.

When [`rexenv/rexenv`](https://github.com/rexenv/rexenv) goes public, steps 1–3 go back
to being CI's job (tag → draft release with the dmg → publish), and `SOURCE_REPO` in
`update-cask.yml` plus the cask's `url`/`verified:` move back to the app repo — those
three must change in one commit.

Only edit `Casks/rexenv.rb` by hand if the automation is broken — and then still hash
the **downloaded release asset**, never a local build.
