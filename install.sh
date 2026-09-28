#!/usr/bin/env bash
# rexenv installer for macOS and Linux.
#
#   curl -fsSL https://rexenv.rex.bd/install.sh | bash
#
# Installs the latest published rexenv release from this repository's GitHub Releases:
#
#   macOS  rexenv.app into /Applications, from the universal .app.tar.gz
#   Linux  the .deb through apt (Ubuntu 22.04 or newer); without apt, the AppImage into
#          ~/Applications (untested outside Ubuntu)
#
# Every download is checked against the release's own .sha256 before anything is installed.
# That proves the file arrived intact; that it is rexenv's rests on HTTPS to github.com, as
# it does for a browser download of the same file.
#
# A rexenv that is already installed is never touched. rexenv updates itself (Settings ->
# About -> Check now), so the script says where the installed copy is and stops.
#
# Why macOS shows no Gatekeeper dialog: Gatekeeper assesses a file carrying the
# com.apple.quarantine attribute, and the DOWNLOADING app sets it. A browser does; curl does
# not. The script still clears the attribute, as the Homebrew cask's postflight does, so both
# install paths end in the same state. rexenv is ad-hoc signed and not notarized: running
# this script is your decision to trust this source. Linux has no such gate; the one prompt
# there is sudo, because a .deb is a system package.
#
#   REXENV_NO_LAUNCH=1   install, but do not start rexenv (CI, or a machine reached over SSH)
#
# The script is a set of functions and one call on its LAST line: a download cut short runs
# nothing, and nothing it starts can read the rest of the script from the pipe.
#
# These promises are row #738 of docs/CLAIM-LEDGER.md in the app repo; the design and its
# measurements are docs/PLAN-install-scripts.md there.

set -euo pipefail

REPO="rexenv/homebrew-tap"
RELEASES="https://github.com/${REPO}/releases"
MACOS_FLOOR=13
BUNDLE_ID="dev.rexenv.rexenv"
APPIMAGE_DIR="${HOME}/Applications"
APPIMAGE_PATH="${APPIMAGE_DIR}/rexenv.AppImage"

VERSION=""
TMP=""

say() { printf 'rexenv: %s\n' "$*"; }
die() {
  printf 'rexenv: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [ -n "$TMP" ]; then rm -rf "$TMP"; fi
}

make_tmp() {
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/rexenv-install.XXXXXX")
  trap cleanup EXIT
}

curl_https() {
  curl --proto '=https' --tlsv1.2 --fail --location --retry 3 --retry-delay 2 "$@"
}

# releases/latest answers 302 to .../releases/tag/v<X.Y.Z>. Reading that Location costs one
# request and no API call (so no rate limit), and "latest" never names a draft or a
# prerelease: the same release the cask's livecheck and the website's /download resolve.
resolve_version() {
  local loc tag
  loc=$(curl --proto '=https' --tlsv1.2 --fail --silent --show-error --retry 3 \
    --output /dev/null --write-out '%{redirect_url}' "${RELEASES}/latest") ||
    die "could not reach GitHub (${RELEASES}/latest)."
  tag=${loc##*/}
  [[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "could not read the latest release from '${loc}'."
  VERSION=${tag#v}
  say "latest release: ${VERSION}"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Downloads release asset $1 into $TMP and refuses it unless it matches the release's
# "<hash>  <name>" .sha256.
download_verified() {
  local asset=$1 url want got
  local progress
  progress=(--silent --show-error)
  url="${RELEASES}/download/v${VERSION}/${asset}"
  if [ -t 2 ]; then progress=(--progress-bar); fi
  say "downloading ${asset}"
  curl_https "${progress[@]}" --output "${TMP}/${asset}" "$url" || die "download failed: ${url}"
  curl_https --silent --show-error --output "${TMP}/${asset}.sha256" "${url}.sha256" ||
    die "download failed: ${url}.sha256"
  want=$(awk 'NR == 1 {print tolower($1)}' "${TMP}/${asset}.sha256")
  [[ $want =~ ^[0-9a-f]{64}$ ]] || die "${asset}.sha256 does not hold a SHA-256. Nothing was installed."
  got=$(sha256_of "${TMP}/${asset}")
  [ "$want" = "$got" ] ||
    die "checksum mismatch for ${asset} (release says ${want}, the download is ${got}). Nothing was installed."
  say "checksum ok"
}

already_installed() {
  say "rexenv${2:+ $2} is already installed: $1"
  say "it updates itself: Settings -> About -> Check now. Nothing was changed."
}

# ---------------------------------------------------------------------------------- macOS

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null
}

installed_macos_app() {
  local p
  for p in /Applications/rexenv.app "${HOME}/Applications/rexenv.app"; do
    if [ -d "$p" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  return 1
}

install_macos() {
  local os_version app asset dest=/Applications
  os_version=$(sw_vers -productVersion)
  [ "${os_version%%.*}" -ge "$MACOS_FLOOR" ] ||
    die "rexenv needs macOS ${MACOS_FLOOR} (Ventura) or newer; this Mac runs ${os_version}."

  if app=$(installed_macos_app); then
    already_installed "$app" "$(plist_value "$app" CFBundleShortVersionString || true)"
    return 0
  fi

  resolve_version
  make_tmp
  asset="rexenv_${VERSION}_universal.app.tar.gz"
  download_verified "$asset"
  mkdir "${TMP}/x"
  tar -xzf "${TMP}/${asset}" -C "${TMP}/x"
  [ -d "${TMP}/x/rexenv.app" ] || die "${asset} holds no rexenv.app. Nothing was installed."
  [ "$(plist_value "${TMP}/x/rexenv.app" CFBundleIdentifier)" = "$BUNDLE_ID" ] ||
    die "${asset} holds an app that is not rexenv (${BUNDLE_ID}). Nothing was installed."

  if [ -w "$dest" ]; then
    mv "${TMP}/x/rexenv.app" "${dest}/"
  else
    say "${dest} is not writable by $(id -un); sudo will ask for your password"
    sudo mv "${TMP}/x/rexenv.app" "${dest}/"
  fi
  # A no-op for a curl download (it carries no quarantine); kept so this path and the cask's
  # postflight leave the same bundle behind.
  xattr -dr com.apple.quarantine "${dest}/rexenv.app" 2>/dev/null || true
  say "installed rexenv ${VERSION}: ${dest}/rexenv.app"

  if [ "${REXENV_NO_LAUNCH:-}" = 1 ]; then
    say "not starting it (REXENV_NO_LAUNCH=1). Open rexenv from Applications."
  elif open "${dest}/rexenv.app" 2>/dev/null; then
    say "started. rexenv lives in the menu bar (the crowned-R icon)."
  else
    say "open rexenv from Applications to finish setup."
  fi
}

# ---------------------------------------------------------------------------------- Linux

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

has_libfuse2() {
  local ldconfig
  ldconfig=$(command -v ldconfig || echo /sbin/ldconfig)
  "$ldconfig" -p 2>/dev/null | grep -q 'libfuse\.so\.2'
}

launch_linux() {
  if [ "${REXENV_NO_LAUNCH:-}" = 1 ]; then
    say "not starting it (REXENV_NO_LAUNCH=1)."
  elif [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    say "no desktop session here: start rexenv from your desktop's app menu."
  else
    if command -v setsid >/dev/null 2>&1; then
      setsid "$1" >/dev/null 2>&1 </dev/null &
    else
      nohup "$1" >/dev/null 2>&1 </dev/null &
    fi
    say "started. rexenv lives in the system tray."
  fi
}

install_linux() {
  local machine deb_arch appimage_arch os_id="" os_version="" os_name="" status asset
  machine=$(uname -m)
  case "$machine" in
    x86_64 | amd64) deb_arch=amd64 appimage_arch=amd64 ;;
    aarch64 | arm64) deb_arch=arm64 appimage_arch=aarch64 ;;
    *) die "rexenv is built for x86_64 and arm64 Linux; this machine is ${machine}." ;;
  esac
  if [ -r /etc/os-release ]; then
    # shellcheck source=/dev/null
    {
      os_id=$(. /etc/os-release && printf '%s' "${ID:-}")
      os_version=$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")
      os_name=$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-}")
    }
  fi

  if command -v dpkg-query >/dev/null 2>&1 &&
    status=$(dpkg-query -W -f='${Status}|${Version}' rexenv 2>/dev/null) &&
    [ "${status%%|*}" = "install ok installed" ]; then
    already_installed "/usr/bin/rexenv (the rexenv package)" "${status#*|}"
    return 0
  fi
  if [ -e "$APPIMAGE_PATH" ]; then
    already_installed "$APPIMAGE_PATH" ""
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1 && command -v dpkg >/dev/null 2>&1; then
    if [ "$os_id" = ubuntu ]; then
      [ "${os_version%%.*}" -ge 22 ] 2>/dev/null ||
        die "rexenv needs Ubuntu 22.04 or newer (its webview is libwebkit2gtk-4.1); this is ${os_name:-Ubuntu ${os_version}}."
    else
      say "note: rexenv is tested on Ubuntu 22.04 and newer; ${os_name:-this distribution} is not tested."
    fi
    if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
      die "installing a .deb needs root: run this as root, or install sudo."
    fi

    resolve_version
    make_tmp
    # apt drops to its _apt user to read a local package; mktemp's 0700 would make it warn.
    chmod 755 "$TMP"
    asset="rexenv_${VERSION}_${deb_arch}.deb"
    download_verified "$asset"
    chmod 644 "${TMP}/${asset}"

    if [ "$(id -u)" -eq 0 ]; then
      say "installing ${asset} with apt"
    else
      say "installing ${asset} with apt; sudo will ask for your password"
    fi
    if ! as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${TMP}/${asset}" </dev/null; then
      say "apt could not install it with its current package lists; refreshing them once and retrying"
      as_root env DEBIAN_FRONTEND=noninteractive apt-get update </dev/null
      as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${TMP}/${asset}" </dev/null ||
        die "apt could not install ${asset}; its message above names the missing piece."
    fi
    say "installed rexenv ${VERSION} (the rexenv package, /usr/bin/rexenv)"
    launch_linux /usr/bin/rexenv
  else
    say "note: no apt here, so this installs the AppImage. rexenv is tested on Ubuntu 22.04 and newer; ${os_name:-this distribution} is not tested."
    resolve_version
    make_tmp
    asset="rexenv_${VERSION}_${appimage_arch}.AppImage"
    download_verified "$asset"
    mkdir -p "$APPIMAGE_DIR"
    mv "${TMP}/${asset}" "$APPIMAGE_PATH"
    chmod 755 "$APPIMAGE_PATH"
    say "installed rexenv ${VERSION}: ${APPIMAGE_PATH}"
    say "keep it in this folder: rexenv updates the file in place."
    if ! has_libfuse2; then
      say "libfuse2 is not installed, and an AppImage needs it to mount. Install it (Fedora: fuse-libs, Arch: fuse2), or run it as APPIMAGE_EXTRACT_AND_RUN=1 ${APPIMAGE_PATH}"
    fi
    launch_linux "$APPIMAGE_PATH"
  fi
}

# ----------------------------------------------------------------------------------- main

main() {
  command -v curl >/dev/null 2>&1 || die "this installer needs curl."
  case "$(uname -s)" in
    Darwin) install_macos ;;
    Linux) install_linux ;;
    *) die "this script installs rexenv on macOS and Linux. On Windows, in PowerShell: irm https://rexenv.rex.bd/install.ps1 | iex" ;;
  esac
}

main "$@"
