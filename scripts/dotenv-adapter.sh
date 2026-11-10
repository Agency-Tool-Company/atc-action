# shellcheck shell=bash
# The shared part of the adapters for the platforms that run the atc action
# through run.sh. Their platform-<name>.sh sources this file and adds the
# names and the hints of its own platform. platform.sh lists the functions
# that an adapter defines.
#
# Errors and lint diagnostics are plain lines on stderr. The outputs go to a
# dotenv file, and the summary goes to stdout. The user stores the secrets as
# CI variables, ATC_TOKEN and ATC_SIGNING_KEY, which run.sh reads. The
# platform masks those variables itself, so mask does nothing.
#
# Optional env:
#   ATC_ACTION_OUTPUT_FILE   the dotenv file for the outputs
#                            (default: atc-publish.env in the cwd)

fail() {
  printf 'error: %s: %s\n' "$1" "$2" >&2
  exit 1
}

diag() {
  printf '%s: %s%s: %s: %s\n' "$1" "$2" "${3:+:$3}" "$4" "$5" >&2
}

mask() { :; }

# Only an allowlist passes. GitLab's dotenv report keeps quotes literally,
# cuts a value at `#`, and drops the whole report on a bad line without
# failing the job. A later step can `source` the file, so a shell character
# such as $, a backtick, ; or ( must not reach it.
dotenv_safe='^[A-Za-z0-9._:/@+%=~-]*$'
output_rules() {
  if ! [[ "$2" =~ $dotenv_safe ]]; then
    fail outputs "$1 holds a character other than letters, digits and ._:/@+%=~-, which the dotenv file does not carry"
  fi
  # A sourced file tilde-expands `~` at the start of a value and after `:`.
  if [[ "$2" == '~'* || "$2" == *':~'* ]]; then
    fail outputs "$1 starts with '~' or holds ':~', which a shell would expand when it sources the dotenv file"
  fi
}

write_outputs() {
  local file="${ATC_ACTION_OUTPUT_FILE:-atc-publish.env}"
  # The checkout can hold a symlink with this name. Writing through it would
  # overwrite the file it names.
  if [ -L "$file" ]; then
    fail outputs "$file is a symbolic link; refusing to write the outputs through it"
  fi
  {
    printf 'ATC_PUBLISH_DELIVERY_ID=%s\n' "$1"
    printf 'ATC_PUBLISH_VERSION=%s\n' "$2"
    printf 'ATC_PUBLISH_SIGNED=%s\n' "$3"
    printf 'ATC_PUBLISH_CONSOLE_URL=%s\n' "$4"
  } > "$file"
}

write_summary() {
  cat
}

# The file is written only after a successful publish. So a failed run would
# otherwise leave the earlier release id and `signed=true` for a later step.
clear_outputs() {
  rm -f -- "${ATC_ACTION_OUTPUT_FILE:-atc-publish.env}"
}

require_platform_env() { :; }

# The secrets are CI variables that run.sh reads.
secret_name() {
  if [ "$1" = token ]; then
    printf 'the ATC_TOKEN variable'
  else
    printf 'the ATC_SIGNING_KEY variable'
  fi
}

# The platform masks only the stored string. A stored secret with whitespace
# around or inside it is used trimmed, and the trimmed form is not masked. So
# it is refused. The value is not shown.
secret_as_stored() {
  if [ "$2" != "$3" ]; then
    fail "$1" "$(secret_label "$1") holds whitespace. Store it as one line with no spaces or line breaks: the trimmed value would not be masked."
  fi
}

require_path_env() { :; }

# run.sh puts the bin dir on PATH for publish.sh itself.
add_to_path() { :; }
