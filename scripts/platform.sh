# shellcheck shell=bash
# The adapter loader of the atc action. install-atc.sh, publish.sh and run.sh
# source this file.
#
# Each platform has an adapter, platform-<name>.sh, in this directory. The
# adapter holds all the code that differs per platform. A copy of the action
# can hold only some of the adapters, so an error lists only the adapters
# that are present.
#
# An adapter defines these functions for publish.sh:
#   fail <title> <message>        report an error and exit 1
#   diag <level> <file> <line> <code> <message>   one lint diagnostic
#   mask <value>                  keep a secret out of the log
#   output_rules <name> <value>   refuse a value that the outputs cannot carry
#   write_outputs <delivery-id> <version> <signed> <console-url>
#   write_summary                 show the Markdown summary on stdin
#   clear_outputs                 remove outputs that an earlier run left
#   require_platform_env          check the runner variables it writes to
#   secret_name <token|signing-key>        what the user sets
#   secret_label <token|signing-key> [bare]   how a value check names it
#   input_name <input> [bare]     what the user sets for an input
#   token_hint                    how to supply the token
#   secret_as_stored <name> <raw> <trimmed>   refuse a secret that the
#                                 platform would not mask once trimmed
# For install-atc.sh:
#   require_path_env              check the runner variables for PATH
#   add_to_path <dir>             put <dir> on PATH for the later steps
# For run.sh, only on a platform that runs the action through run.sh:
#   run_defaults                  set default_version, default_workspace and
#                                 run_id from the platform's own variables
#
# The functions here use only shell builtins. The caller can still hold a
# secret in its environment, and an external command would inherit it.

case "${BASH_SOURCE[0]}" in
  */*) platform_dir="${BASH_SOURCE[0]%/*}" ;;
  *) platform_dir=. ;;
esac

# platform_adapter <name>: set adapter to the path of the adapter for <name>.
# Return 1 when <name> is not a lower-case word or has no adapter here.
platform_adapter() {
  adapter=""
  [[ "$1" =~ ^[a-z]+$ ]] || return 1
  [ -f "$platform_dir/platform-$1.sh" ] || return 1
  # shellcheck disable=SC2034 # the caller reads it
  adapter="$platform_dir/platform-$1.sh"
}

# platform_defines <adapter file> <function>: true when the adapter defines
# the function. The adapter is read in a subshell, so its functions do not
# replace those of the caller.
platform_defines() {
  # shellcheck source=/dev/null
  (. "$1" && declare -F "$2" > /dev/null)
}

# platform_list <function> <separator> <last separator>: the names of the
# adapters here that define the function, joined, for example "a, b or c".
platform_list() {
  local f name out="" n=0 i
  local -a names=()
  for f in "$platform_dir"/platform-*.sh; do
    [ -f "$f" ] || continue
    name="${f##*/platform-}"
    name="${name%.sh}"
    if platform_defines "$f" "$1"; then
      names+=("$name")
      n=$((n + 1))
    fi
  done
  for ((i = 0; i < n; i++)); do
    if [ "$i" -eq 0 ]; then
      out="${names[0]}"
    elif [ "$i" -eq $((n - 1)) ]; then
      out="$out$3${names[i]}"
    else
      out="$out$2${names[i]}"
    fi
  done
  printf '%s' "$out"
}
