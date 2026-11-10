# shellcheck shell=bash
# The Bitbucket Pipelines adapter of the atc action. The documented step runs
# `run.sh bitbucket`, and run.sh, install-atc.sh and publish.sh source this
# file. platform.sh lists the functions that an adapter defines. A user sets
# each input as a variable that the step exports, and the secrets as secured
# deployment variables. So every name in an error is the variable to set.

# shellcheck source=dotenv-adapter.sh disable=SC1091
. "${BASH_SOURCE[0]%/*}/dotenv-adapter.sh"

# The secured variable: ATC_TOKEN or ATC_SIGNING_KEY.
secret_label() {
  case "$1" in
    token) printf 'ATC_TOKEN' ;;
    *) printf 'ATC_SIGNING_KEY' ;;
  esac
}

# The variable that the step exports: channel is ATC_ACTION_CHANNEL. The
# atc-track input is ATC_ACTION_TRACK.
input_name() {
  case "$1" in
    atc-track) printf 'ATC_ACTION_TRACK' ;;
    *) printf 'ATC_ACTION_%s' "$(printf '%s' "$1" | tr 'a-z-' 'A-Z_')" ;;
  esac
}

token_hint() {
  printf '%s' "Set the ATC_TOKEN secured variable to an operator API key, on the deployment environment that the step's deployment: names."
}

# The version is the tag, else the branch. The workspace is the clone
# directory, because Bitbucket collects artifacts only from there, and a
# later step can `source` the dotenv file. The step UUID names the temp dir,
# so that the after-script can remove it after a KILL. The UUID has braces,
# which run.sh drops.
# shellcheck disable=SC2034 # run.sh reads the three variables
run_defaults() {
  default_version="${BITBUCKET_TAG:-${BITBUCKET_BRANCH:-}}"
  default_workspace="${BITBUCKET_CLONE_DIR:-}"
  run_id="${BITBUCKET_STEP_UUID:-}"
}
