# shellcheck shell=bash
# The GitLab CI adapter of the atc action. The atc-publish job of
# gitlab/atc-publish.yml runs `run.sh gitlab`, and run.sh, install-atc.sh and
# publish.sh source this file. platform.sh lists the functions that an
# adapter defines. A user sets the inputs as include inputs and the secrets
# as CI/CD variables.

# shellcheck source=dotenv-adapter.sh disable=SC1091
. "${BASH_SOURCE[0]%/*}/dotenv-adapter.sh"

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
  printf '%s' "Set the ATC_TOKEN variable to an operator API key. A protected variable reaches only a protected tag or branch, and an environment-scoped one only a job of that environment."
}

# The version is the tag or branch name, and the workspace is the project
# directory: the include names the dotenv report relative to it. The job id
# names the temp dir, so that after_script can remove it after a KILL.
# shellcheck disable=SC2034 # run.sh reads the three variables
run_defaults() {
  default_version="${CI_COMMIT_REF_NAME:-}"
  default_workspace="${CI_PROJECT_DIR:-}"
  run_id="${CI_JOB_ID:-}"
}
