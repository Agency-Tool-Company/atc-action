#!/usr/bin/env bash
# The entry point of the atc action on a CI platform that runs it as a
# script. Its argument names the platform adapter, platform-<name>.sh, beside
# this script. Only an adapter with run_defaults can be named (see
# platform.sh).
#
# This script does the work that every such platform needs:
#   1. It moves ATC_TOKEN and ATC_SIGNING_KEY into ATC_ACTION_TOKEN and
#      ATC_ACTION_SIGNING_KEY, unless those are set, and unsets the pair.
#      So the installer and atc never inherit a secret.
#   2. It defaults ATC_ACTION_VERSION and ATC_ACTION_WORKSPACE to the values
#      that the adapter's run_defaults gives: the tag or branch name, and the
#      checkout directory.
#   3. It makes sure curl, jq and CA certificates are present. When one is
#      missing and the job runs as root with apt-get or apk, it installs it.
#      Otherwise it fails and names what is missing.
#   4. It makes a private 0700 temp dir, $TMPDIR/atc-action-<run id>. An
#      EXIT trap removes it, also after TERM or INT.
#   5. It runs install-atc.sh, then publish.sh with the new atc on PATH. The
#      exit status of publish.sh is the exit status of this script.
#
# Usage: run.sh <platform>   (inputs arrive as env; see publish.sh)
# Optional env:
#   SSL_CERT_FILE   the CA bundle to check (default: the usual system paths)
set -euo pipefail

# Shell-only path splitting: an external dirname would run before the secrets
# leave the environment, and inherit them.
self="${BASH_SOURCE[0]}"
case "$self" in
  */*) here="$(cd "${self%/*}" && pwd)" ;;
  *) here="$PWD" ;;
esac

fail() {
  printf 'error: %s: %s\n' "$1" "$2" >&2
  exit 1
}

# shellcheck source=platform.sh disable=SC1091
. "$here/platform.sh"
platform="${1:-}"
# shellcheck disable=SC2154 # platform_adapter sets adapter
if ! platform_adapter "$platform" || ! platform_defines "$adapter" run_defaults; then
  fail usage "run.sh <$(platform_list run_defaults '|' '|')>, not '$platform'"
fi
# shellcheck source=/dev/null # platform_adapter sets adapter
. "$adapter"
run_defaults

# ── 1. Secrets ────────────────────────────────────────────────────────────────

[ -n "${ATC_ACTION_TOKEN:-}" ] || ATC_ACTION_TOKEN="${ATC_TOKEN:-}"
[ -n "${ATC_ACTION_SIGNING_KEY:-}" ] || ATC_ACTION_SIGNING_KEY="${ATC_SIGNING_KEY:-}"
unset ATC_TOKEN ATC_SIGNING_KEY
# Shell variables only, not exported: no child (id, mkdir, the package
# manager, the installer) has them in its environment. The publish call alone
# gets them, as a prefix assignment. A pair the job set in the environment
# loses its export too.
export -n ATC_ACTION_TOKEN ATC_ACTION_SIGNING_KEY

# without_secrets <command...>: run a command with the secrets unset, as
# defense in depth on top of the missing export.
without_secrets() (
  unset ATC_ACTION_TOKEN ATC_ACTION_SIGNING_KEY
  "$@"
)

# ── 2. Defaults ───────────────────────────────────────────────────────────────

export ATC_ACTION_PLATFORM="$platform"
export ATC_ACTION_VERSION="${ATC_ACTION_VERSION:-$default_version}"
export ATC_ACTION_WORKSPACE="${ATC_ACTION_WORKSPACE:-$default_workspace}"
# The dotenv file goes to the workspace root, not to the cwd of the job: the
# platform collects it from there.
if [ -z "${ATC_ACTION_OUTPUT_FILE:-}" ] && [ -n "$ATC_ACTION_WORKSPACE" ]; then
  export ATC_ACTION_OUTPUT_FILE="$ATC_ACTION_WORKSPACE/atc-publish.env"
fi

# ── 3. Tools ──────────────────────────────────────────────────────────────────

have_ca() {
  if [ -n "${SSL_CERT_FILE:-}" ]; then
    [ -s "$SSL_CERT_FILE" ]
    return
  fi
  local f
  for f in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/cert.pem; do
    [ -s "$f" ] && return 0
  done
  return 1
}

# Sets missing to the packages that are not present. The package names are
# the same on apt-get and apk.
find_missing() {
  missing=()
  command -v curl > /dev/null || missing+=(curl)
  command -v jq > /dev/null || missing+=(jq)
  have_ca || missing+=(ca-certificates)
}

find_missing
if [ "${#missing[@]}" -gt 0 ]; then
  # A failed install is not fatal here: the check below names what is still
  # missing.
  if [ "$(id -u)" = 0 ] && command -v apt-get > /dev/null; then
    printf 'run.sh: installing %s with apt-get\n' "${missing[*]}" >&2
    { without_secrets apt-get update -qq > /dev/null &&
      without_secrets env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing[@]}" > /dev/null; } || true
  elif [ "$(id -u)" = 0 ] && command -v apk > /dev/null; then
    printf 'run.sh: installing %s with apk\n' "${missing[*]}" >&2
    without_secrets apk add --no-cache -q "${missing[@]}" > /dev/null || true
  fi
  find_missing
  if [ "${#missing[@]}" -gt 0 ]; then
    fail tools "missing ${missing[*]}. Use an image that has them, or run the job as root on an image with apt-get or apk."
  fi
fi

# ── 4. Temp dir ───────────────────────────────────────────────────────────────

# A path the job can name again: atc-action-<run id>. So a cleanup step that
# runs in another shell after a KILL can remove it.
# The id is reduced to safe characters. Without an id, a random directory.
run_id="${run_id//[!A-Za-z0-9_-]/}"
if [ -n "$run_id" ]; then
  ATC_ACTION_TEMP="${TMPDIR:-/tmp}/atc-action-$run_id"
  rm -rf -- "$ATC_ACTION_TEMP"
  mkdir -m 700 -- "$ATC_ACTION_TEMP"
else
  ATC_ACTION_TEMP="$(mktemp -d)"
  chmod 700 "$ATC_ACTION_TEMP"
fi
trap 'rm -rf -- "$ATC_ACTION_TEMP"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
export ATC_ACTION_TEMP

# ── 5. Install and publish ────────────────────────────────────────────────────

# The installer is downloaded code: it gets no secret.
without_secrets bash "$here/install-atc.sh"
PATH="$ATC_ACTION_TEMP/atc-bin:$PATH"
ATC_ACTION_TOKEN="$ATC_ACTION_TOKEN" ATC_ACTION_SIGNING_KEY="$ATC_ACTION_SIGNING_KEY" \
  bash "$here/publish.sh"
