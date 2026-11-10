#!/usr/bin/env bash
# Install the atc CLI for the atc action. It downloads the atc installer
# from the install-url input. The installer verifies the signed release
# index and installs into <temp root>/atc-bin. The platform adapter then
# puts the bin directory on PATH for the later steps, or the caller does.
#
# Usage: install-atc.sh
#
# Required env (set by the runner, action.yml or run.sh):
#   ATC_ACTION_PLATFORM   the platform adapter to load (see platform.sh)
#   ATC_ACTION_TEMP       the temp root
#   ATC_ACTION_TRACK      stable or nightly
#   ATC_ACTION_INSTALL_URL  the installer URL, the install-url input. It has
#                           no default: `atc ci <platform>` prints it. It
#                           must be https, and curl follows no redirect to
#                           another scheme.
#   and the runner variables that the adapter names
set -euo pipefail

case "${BASH_SOURCE[0]}" in
  */*) script_dir="${BASH_SOURCE[0]%/*}" ;;
  *) script_dir=. ;;
esac
# shellcheck source=platform.sh disable=SC1091
. "$script_dir/platform.sh"
if ! platform_adapter "${ATC_ACTION_PLATFORM:-}"; then
  printf "error: ATC_ACTION_PLATFORM must be %s, not '%s'\n" \
    "$(platform_list fail ', ' ' or ')" "${ATC_ACTION_PLATFORM:-}" >&2
  exit 1
fi
# shellcheck source=/dev/null disable=SC2154 # platform_adapter sets adapter
. "$adapter"

temp="${ATC_ACTION_TEMP:-}"
[ -n "$temp" ] || fail temp "set ATC_ACTION_TEMP to a private temp directory"
require_path_env
track="${ATC_ACTION_TRACK:-stable}"
url="${ATC_ACTION_INSTALL_URL:-}"
[ -n "$url" ] ||
  fail install-url "$(input_name install-url) is empty. Set it to the installer URL that atc ci $ATC_ACTION_PLATFORM prints."
case "$url" in
  https://*) ;;
  *) fail install-url "$(input_name install-url) must be an https:// URL, not $url" ;;
esac

case "$track" in
  stable | nightly) ;;
  *) fail atc-track "$(input_name atc-track bare) must be stable or nightly, not $track" ;;
esac

bin_dir="$temp/atc-bin"
installer="$temp/atc-install.sh"
mkdir -p "$bin_dir"

curl -q -fsSL --proto =https --proto-redir =https --retry 5 --retry-delay 2 -o "$installer" "$url"
ATC_TRACK="$track" ATC_BIN_DIR="$bin_dir" ATC_INSTALL_SKILL=0 sh "$installer"
rm -f "$installer"

add_to_path "$bin_dir"
"$bin_dir/atc" --version
