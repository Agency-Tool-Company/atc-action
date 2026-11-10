#!/usr/bin/env bash
# The publish step of the atc action. It lints the atc.kdl or atc.toml, runs
# `atc ota publish`, and reports the result as outputs and a summary. With
# deliver=true it signs the release with the org key and fails unless the
# release is signed.
#
# ATC_ACTION_PLATFORM names the platform adapter, platform-<name>.sh, beside
# this script. The adapter holds all the code that differs per platform:
# platform.sh lists its functions.
#
# The org key reaches atc the way it does on a laptop: as
# $ATC_CONFIG_HOME/org-keys/<org>.key. ATC_CONFIG_HOME is a fresh 0700
# directory under the temp root, so no login or key from an earlier job on a
# self-hosted runner is read. An EXIT trap deletes it.
#
# The key never appears in argv, in a process environment of atc, or in the
# log: it is written with the printf builtin and only the file path is ever
# printed.
#
# Usage: publish.sh   (inputs arrive as env; see action.yml and run.sh)
#
# Required env:
#   ATC_ACTION_PLATFORM   the platform adapter to load
#   ATC_ACTION_TEMP       the temp root
#   ATC_ACTION_TOKEN, ATC_ACTION_CHANNEL, ATC_ACTION_VERSION
#   and the runner variables that the adapter names
# Optional env:
#   ATC_ACTION_DELIVER, ATC_ACTION_SIGNING_KEY, ATC_ACTION_ORG,
#   ATC_ACTION_SERVER, ATC_ACTION_CONSOLE_URL, ATC_ACTION_CONFIG,
#   ATC_ACTION_ONLY, ATC_ACTION_WAIT
#   ATC_ACTION_WORKSPACE     trimmed from lint file paths
#   ATC_ACTION_ATC   the atc binary (default: atc on PATH; tests set a stub)
#   and the optional env of the adapter
set -euo pipefail

# Shell-only path splitting: an external dirname would inherit the secrets,
# which are still in the environment here.
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

# output_value <name> <value>: refuse a value that the outputs cannot carry.
# A line break would add a line to the output file. The adapter adds the
# rules of its own output file.
output_value() {
  if [[ "$2" == *[$'\r\n']* ]]; then
    fail outputs "$1 holds a line break, which a step output cannot carry"
  fi
  output_rules "$1" "$2"
}

# ── Environment ───────────────────────────────────────────────────────────────

temp="${ATC_ACTION_TEMP:-}"
[ -n "$temp" ] || fail temp "set ATC_ACTION_TEMP to a private temp directory"
require_platform_env

atc_bin="${ATC_ACTION_ATC:-atc}"
# Trimmed, as the key is below: a platform masks only the exact secret string,
# so the mask must get the string that atc uses.
token_raw="${ATC_ACTION_TOKEN:-}"
# Trimmed in the shell: a `tr` child would inherit the secrets, which are still
# in the environment here.
token="${token_raw//[[:space:]]/}"
signing_key_raw="${ATC_ACTION_SIGNING_KEY:-}"
channel="${ATC_ACTION_CHANNEL:-}"
version="${ATC_ACTION_VERSION:-}"
deliver="${ATC_ACTION_DELIVER:-false}"
org="${ATC_ACTION_ORG:-}"
server="${ATC_ACTION_SERVER:-}"
console_url="${ATC_ACTION_CONSOLE_URL:-$server}"
config="${ATC_ACTION_CONFIG:-}"
only="${ATC_ACTION_ONLY:-}"
wait_flag="${ATC_ACTION_WAIT:-false}"
workspace="${ATC_ACTION_WORKSPACE:-}"
# The secrets now live only in shell variables. Remove them from the
# environment so no child process (lint, publish, jq) inherits them. The token
# goes back into the environment for the publish call only.
unset ATC_ACTION_TOKEN ATC_ACTION_SIGNING_KEY
# After the unset: rm is the first child process, and it gets no secret.
clear_outputs

# Not in a command substitution: fail's error line must reach the log.
require_bool() {
  case "$2" in
    true | false) ;;
    *) fail "$1" "$(input_name "$1" bare) must be true or false, not '$2'" ;;
  esac
}

# ── Inputs ────────────────────────────────────────────────────────────────────

require_bool deliver "$deliver"
require_bool wait "$wait_flag"
[ -n "$token" ] || fail token "the token is empty. $(token_hint)"
[ -n "$channel" ] || fail channel "$(input_name channel) is empty"
[ -n "$version" ] || fail version "$(input_name version) is empty"
# Check the outputs that come from inputs now, so a bad value fails before
# anything is published. The console link is checked in the form it takes.
output_value version "$version"
[ -z "$console_url" ] || output_value console-url "${console_url%/}/channels/deliveries/x"
secret_as_stored token "$token_raw" "$token"
mask "$token"

only_args=()
# Split on whitespace, but never expand a glob such as `app*` against the cwd.
set -f
for name in $only; do
  only_args+=(--only "$name")
done
set +f
if [ "$deliver" = true ] && [ "${#only_args[@]}" -gt 0 ]; then
  fail only "$(input_name only bare) cannot be used with $(input_name deliver bare): a release carries every artifact in the config"
fi

signing_key=""
if [ "$deliver" = true ]; then
  [ -n "$signing_key_raw" ] || fail signing-key "deliver is true and $(secret_name signing-key) is empty. The action never publishes an unsigned release. Pass the contents of the <org>.key file that 'atc org key generate' wrote."
  [ -n "$org" ] || fail org "deliver is true and $(input_name org) is empty. The signing key is filed under the org id."
  # The org names a file, so it must be one path component.
  case "$org" in
    '' | . | .. | */* | *[!A-Za-z0-9._-]*) fail org "$(input_name org bare) must be an org id (letters, digits, '.', '_', '-')" ;;
  esac
  signing_key="${signing_key_raw//[[:space:]]/}"
  secret_as_stored signing-key "$signing_key_raw" "$signing_key"
  # A platform masks only the exact secret string, so mask the trimmed form.
  mask "$signing_key"
  if ! [[ "$signing_key" =~ ^[0-9A-Fa-f]{64}$ ]]; then
    fail signing-key "$(secret_label signing-key bare) must be 64 hex characters (the <org>.key file). The value is not shown."
  fi
fi

# ── Isolated config home ──────────────────────────────────────────────────────

home="$temp/atc-action-home"
rm -rf -- "$home"
cleanup() { rm -rf -- "$home"; }
trap cleanup EXIT
# A cancelled job gets TERM (or INT). Exiting from the handler runs the EXIT
# trap, so the key directory goes. KILL runs nothing: the cleanup step of the
# caller covers it.
trap 'exit 143' TERM
trap 'exit 130' INT
(
  umask 077
  mkdir -p "$home/org-keys"
  if [ -n "$signing_key" ]; then
    printf '%s\n' "$signing_key" > "$home/org-keys/$org.key"
  fi
)

run_atc() {
  ATC_CONFIG_HOME="$home" "$atc_bin" --non-interactive "$@"
}

config_args=()
[ -n "$config" ] && config_args=(-c "$config")

# ── Lint ──────────────────────────────────────────────────────────────────────

lint_out="$temp/atc-action-lint.json"
set +e
run_atc --json "${config_args[@]+"${config_args[@]}"}" config lint > "$lint_out"
lint_status=$?
set -e

if [ -s "$lint_out" ] && jq -e 'type == "object" and (.diagnostics | type == "array")' "$lint_out" > /dev/null 2>&1; then
  lint_file="$(jq -r '.file' "$lint_out")"
  [ -n "$workspace" ] && lint_file="${lint_file#"$workspace"/}"
  while IFS= read -r diag; do
    sev="$(jq -r '.severity' <<< "$diag")"
    code="$(jq -r '.code' <<< "$diag")"
    msg="$(jq -r '.message' <<< "$diag")"
    line="$(jq -r '.line // empty' <<< "$diag")"
    case "$sev" in error) level=error ;; *) level=warning ;; esac
    diag "$level" "$lint_file" "$line" "$code" "$msg"
  done < <(jq -c '.diagnostics[]' "$lint_out")
  errors="$(jq -r '.errors' "$lint_out")"
  [ "$errors" = 0 ] || fail "atc config lint" "the config has $errors error(s); nothing was published"
elif [ "$lint_status" -ne 0 ]; then
  fail "atc config lint" "atc config lint failed (exit $lint_status) and wrote no report"
fi
rm -f "$lint_out"

# ── Publish ───────────────────────────────────────────────────────────────────

publish_args=(ota publish --channel "$channel" --version "$version")
publish_args+=("${only_args[@]+"${only_args[@]}"}")
[ -n "$server" ] && publish_args+=(--server "$server")
[ -n "$org" ] && publish_args+=(--org "$org")
[ "$deliver" = true ] && publish_args+=(--deliver)
[ "$wait_flag" = true ] && publish_args+=(--wait)

out_file="$temp/atc-action-publish.json"
err_file="$temp/atc-action-publish.err"
# stdout (the JSON report) goes to a file. stderr goes to the log live and to
# a file, so a failure can be explained. The token reaches atc only as env.
exec 3> "$out_file"
set +e
ATC_SERVER_TOKEN="$token" run_atc --json \
  "${config_args[@]+"${config_args[@]}"}" "${publish_args[@]}" 2>&1 1>&3 3>&- |
  tee "$err_file" >&2
statuses=("${PIPESTATUS[@]}")
set -e
exec 3>&-
publish_status="${statuses[0]}"

if [ "$publish_status" -ne 0 ]; then
  # Under --json, atc writes its error as one document on stdout
  # ({ok: false, code, message, fix_command, docs_url}), not as text on stderr.
  # Read it from there; stderr still carries any progress lines.
  err_code="" err_msg="" err_fix="" err_docs=""
  if [ -s "$out_file" ] && jq -e 'type == "object" and .ok == false' "$out_file" > /dev/null 2>&1; then
    err_code="$(jq -r '.code // empty' "$out_file")"
    err_msg="$(jq -r '.message // empty' "$out_file")"
    err_fix="$(jq -r '.fix_command // empty' "$out_file")"
    err_docs="$(jq -r '.docs_url // empty' "$out_file")"
  fi
  # Both the error document and stderr are searched for the known failures.
  haystack="$err_msg"$'\n'"$(cat "$err_file")"
  case "$haystack" in
    *'admin route not found'*)
      fail "atc ota publish" "the server refused the token. Check that $(secret_name token) holds a live operator API key for this org with role org_operator (or org_hook_publisher when the config declares hooks)."
      ;;
    *'does not verify against an active org key'*)
      fail "atc ota publish" "the server does not know this signing key. Register it with 'atc org key register --org $org' as an org admin, then re-run: the run adopts the release it created."
      ;;
  esac
  if [ -n "$err_msg" ]; then
    detail="${err_code:+$err_code: }$err_msg"
    [ -n "$err_fix" ] && detail="$detail"$'\n'"fix: $err_fix"
    [ -n "$err_docs" ] && detail="$detail"$'\n'"docs: $err_docs"
    fail "atc ota publish" "$detail"
  fi
  fail "atc ota publish" "atc ota publish failed (exit $publish_status) and wrote no error report; see the log above"
fi

if ! { [ -s "$out_file" ] && jq -e 'type == "object"' "$out_file" > /dev/null 2>&1; }; then
  fail "atc ota publish" "atc ota publish succeeded but wrote no JSON report"
fi

# ── Postflight and outputs ────────────────────────────────────────────────────

delivery_id="$(jq -r '.delivery_id // empty' "$out_file")"
signed="$(jq -r 'if has("signed") then (.signed | tostring) else "" end' "$out_file")"
published_version="$(jq -r '.version // empty' "$out_file")"

if [ "$deliver" = true ]; then
  # `null` is a release an earlier publish already published, which this run
  # reused without signing. That publish may have been unsigned on a channel
  # where signing is optional, and nothing here can read its signatures. So it
  # fails closed: the action promises a signed release.
  case "$signed" in
    true) ;;
    null) fail "atc ota publish" "this content was already published as release $delivery_id by an earlier publish, and the action cannot prove that release is signed. Publish under a new version label." ;;
    *) fail "atc ota publish" "release $delivery_id is not signed. Devices on a channel that requires signed releases will refuse it." ;;
  esac
fi

link=""
if [ -n "$console_url" ] && [ -n "$delivery_id" ]; then
  link="${console_url%/}/channels/deliveries/$delivery_id"
fi

# Check every value before the adapter opens the file: a refused value
# writes no output at all.
output_value delivery-id "$delivery_id"
output_value version "$published_version"
output_value signed "$signed"
output_value console-url "$link"
write_outputs "$delivery_id" "$published_version" "$signed" "$link"

# The backticks below are Markdown code spans, not command substitution.
# shellcheck disable=SC2016
{
  printf '### atc publish\n\n'
  printf '| Artifact | Kind | Version | State |\n|---|---|---|---|\n'
  jq -r '.artifacts[]? | "| `\(.name)` | \(.kind) | `\(.version)` | \(.state) |"' "$out_file"
  printf '\nChannel: `%s`\n' "$channel"
  if [ -n "$delivery_id" ]; then
    printf '\nRelease: `%s` (signed: %s)' "$delivery_id" "$signed"
    [ -n "$link" ] && printf ' [open in console](%s)' "$link"
    printf '\n\nNo device moves until an assignment, pin or deployment names the release.\n'
  fi
} | write_summary

rm -f "$out_file" "$err_file"
