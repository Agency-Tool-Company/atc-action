# shellcheck shell=bash
# The GitHub Actions adapter of the atc action. action.yml runs
# install-atc.sh and publish.sh with ATC_ACTION_PLATFORM=github, and both
# source this file. platform.sh lists the functions that an adapter defines.
#
# GitHub reads workflow commands (::error, ::add-mask::) from stdout. It
# reads step outputs, the summary and PATH additions from the files that the
# runner names in GITHUB_OUTPUT, GITHUB_STEP_SUMMARY and GITHUB_PATH. The
# user passes the secrets as action inputs.
#
# GitHub masks only the exact secret string. So publish.sh trims each secret
# and masks the trimmed form. A leading newline in the token would split the
# ::add-mask:: line and leave the token bare.
#
# Required env (set by the runner):
#   GITHUB_OUTPUT, GITHUB_STEP_SUMMARY   for publish.sh
#   GITHUB_PATH                          for install-atc.sh

# Escape a workflow-command message (%, CR, LF).
esc_data() {
  local s="$1"
  s="${s//'%'/%25}"
  s="${s//$'\r'/%0D}"
  s="${s//$'\n'/%0A}"
  printf '%s' "$s"
}

# Escape a workflow-command property value (the data set plus : and ,).
esc_prop() {
  local s
  s="$(esc_data "$1")"
  s="${s//:/%3A}"
  s="${s//,/%2C}"
  printf '%s' "$s"
}

# The message is escaped, because it can hold an input value.
fail() {
  printf '::error title=%s::%s\n' "$(esc_prop "$1")" "$(esc_data "$2")"
  exit 1
}

diag() {
  local level="$1" file="$2" line="$3" code="$4" msg="$5" props
  props="file=$(esc_prop "$file"),title=$(esc_prop "$code")"
  # Digits only: the line comes from the lint report, unescaped.
  [[ "$line" =~ ^[0-9]+$ ]] && props="$props,line=$line"
  printf '::%s %s::%s\n' "$level" "$props" "$(esc_data "$msg")"
}

# GitHub decodes %25, %0D and %0A in the value before it masks it. So the
# value is escaped, and a literal `%0A` in a secret cannot split it.
mask() {
  printf '::add-mask::%s\n' "$(esc_data "$1")"
}

# GITHUB_OUTPUT takes any value on one line.
output_rules() { :; }

write_outputs() {
  {
    printf 'delivery-id=%s\n' "$1"
    printf 'version=%s\n' "$2"
    printf 'signed=%s\n' "$3"
    printf 'console-url=%s\n' "$4"
  } >> "$GITHUB_OUTPUT"
}

write_summary() {
  cat >> "$GITHUB_STEP_SUMMARY"
}

# GitHub gives each step a fresh GITHUB_OUTPUT.
clear_outputs() { :; }

require_platform_env() {
  : "${GITHUB_OUTPUT:?set by the GitHub runner}"
  : "${GITHUB_STEP_SUMMARY:?set by the GitHub runner}"
}

# The secrets are action inputs.
secret_name() {
  printf 'the %s input' "$1"
}

# "the token", or "token" with bare.
secret_label() {
  if [ "${2:-}" = bare ]; then
    printf '%s' "$1"
  else
    printf 'the %s' "$1"
  fi
}

# "the channel input", or "channel" with bare.
input_name() {
  if [ "${2:-}" = bare ]; then
    printf '%s' "$1"
  else
    printf 'the %s input' "$1"
  fi
}

token_hint() {
  printf '%s' "Pass an operator API key, for example \${{ secrets.ATC_TOKEN }}."
}

# GitHub gets the mask of the trimmed form, so a secret with whitespace is
# used trimmed and stays masked.
secret_as_stored() { :; }

require_path_env() {
  : "${GITHUB_PATH:?set by the GitHub runner}"
}

add_to_path() {
  printf '%s\n' "$1" >> "$GITHUB_PATH"
}
