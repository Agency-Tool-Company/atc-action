# atc publish

Publish your build's artifacts to atc-server from CI, and sign them into a
release when you want one.

On a release tag, the action checks your `atc.kdl` or `atc.toml` with
`atc config lint`, uploads the artifacts it declares with `atc ota publish`,
and writes a summary of what it published. With `deliver: true`, it also signs
a release into the channel you name.

It runs on GitHub Actions, [GitLab CI](#gitlab-ci) and
[Bitbucket Pipelines](#bitbucket-pipelines). All three run the same scripts
and follow the same signing rules.

Publishing never moves a device. A release reaches devices only when an
assignment, a pin or a deployment targets it, and that step stays yours.

## Getting started

You need these before you start:

- An org on an atc-server.
- An org signing key, registered with `atc org key register`.
- The `atc` CLI on your computer, logged in to that server with
  `atc auth login`.

Then do these steps:

1. Run the command for your platform. It prints your server, org and role,
   checks the signing key, and prints the commands and the pipeline file with
   your values filled in:

   ```bash
   atc ci github --channel <name>
   ```

   On GitLab CI, run `atc ci gitlab`. On Bitbucket Pipelines, run
   `atc ci bitbucket`. Without `--channel`, the command names the channels of
   your org.

2. Store the two secrets: `ATC_TOKEN`, an operator API key for CI, and
   `ATC_SIGNING_KEY`, the contents of the org key file. Store them in an
   environment that only release tags can use. See
   [Set up the secrets](#set-up-the-secrets) for GitHub, and the
   [GitLab CI](#gitlab-ci) or [Bitbucket Pipelines](#bitbucket-pipelines)
   section for those platforms.

3. Add the pipeline file from your platform's section:
   [GitHub Actions](#usage-on-github-actions), [GitLab CI](#gitlab-ci) or
   [Bitbucket Pipelines](#bitbucket-pipelines). Pin this repository by its
   full 40-character commit SHA. Replace `<install-url>` with the URL of the
   atc installer. The pipeline file that `atc ci` prints holds it, and so
   does the CLI setup page of the console.

4. Push a release tag that starts with `v`:

   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

5. Read the result. The summary lists each artifact and the release, with a
   console link when a console URL is known. On GitHub, the summary is the job
   summary, and the step outputs give the release id. On GitLab and
   Bitbucket, the summary is in the job log, and `atc-publish.env` gives the
   outputs.

No device has moved yet. To roll the release out, target it with an
assignment, a pin or a deployment.

## Usage on GitHub Actions

```yaml
# .github/workflows/release.yml
on:
  push:
    tags: ["v*"]

permissions:
  contents: read

jobs:
  publish:
    runs-on: ubuntu-latest
    environment: release
    steps:
      - uses: actions/checkout@v6
      - uses: Agency-Tool-Company/atc-action@<commit-sha>
        with:
          token: ${{ secrets.ATC_TOKEN }}
          signing-key: ${{ secrets.ATC_SIGNING_KEY }}
          org: <org-id>
          channel: stable
          deliver: true
          install-url: <install-url>
```

## Inputs

| Input | Required | Description |
|---|---|---|
| `token` | yes | Operator API key for the org. |
| `channel` | yes | Server channel, for example `stable`. |
| `install-url` | yes | https URL of the atc installer. `atc ci github` prints it, and so does the CLI setup page of the console. |
| `version` | no | Version label. The default is the tag or branch name. |
| `deliver` | no | `true` signs a release into `channel`. The default is `false`. |
| `signing-key` | with `deliver` | The org signing key: the hex contents of `<org>.key`. |
| `org` | with `deliver` | Org id. Otherwise the config's `server` block supplies it. |
| `server` | no | atc-server URL. Otherwise the config's `server` block supplies it. |
| `console-url` | no | Console base URL for the summary link. The default is `server`. |
| `config` | no | Path to `atc.kdl` or `atc.toml`. The default is upward discovery. |
| `only` | no | Publish only these artifacts. Cannot be used with `deliver`. |
| `wait` | no | `true` waits until each version is available. |
| `atc-track` | no | `stable` (default) or `nightly`. |

## Outputs

| Output | Description |
|---|---|
| `delivery-id` | The release that the run created or reused. |
| `version` | The published version label. |
| `signed` | `true` when this run signed the release. Empty without `deliver`. |
| `console-url` | Console link to the release, when a console URL is known. |

## Set up the secrets

To get every value below in one place, run `atc ci github --channel <name>`.
It prints the server and the org of your login, your role, and the path of
the org key file. It also prints the key id of that file, and whether
the server lists the key. Without `--channel`, it names the org's channels.

Then it prints the commands for steps 1 to 3 and the workflow file, with the
values filled in. It mints no key, runs no `gh` command, and prints no
secret. Add `--json` for a script.

1. Mint an operator key for CI. Use the role `org_operator`, or
   `org_hook_publisher` when the config declares hooks. Do not use
   `org_admin`. An org admin mints it in the console: open **Access**, choose **Create API key**,
   and pick the role. `atc operator create` does not use an `atc auth login`
   session. It reads an org-admin or platform-admin API key from
   `ATC_ADMIN_TOKEN`, `--admin-token-file` or `--admin-token-stdin`:

   ```bash
   atc operator create --admin-token-file <org-admin-key-file> --name ci --key-label github-actions --role org_operator --org <org-id>
   ```

   On your own server, add `--server <url>`.

2. Find the org signing key. It is the file that `atc org key generate` wrote:
   `~/.config/atc/org-keys/<org-id>.key`, or under `$ATC_CONFIG_HOME` or
   `$XDG_CONFIG_HOME/atc` when one is set. Register it with
   `atc org key register`. Devices trust only the keys that the org had when
   they enrolled, so use the key that the org already signs with.

3. In the repository, open Settings → Environments and create an environment
   such as `release`. Store the operator key as `ATC_TOKEN` and the contents of
   the key file as `ATC_SIGNING_KEY` in that environment, not as repository
   secrets.

4. Give the environment a deployment branch rule that allows only release tags,
   such as `v*`. For a production channel, also require a reviewer. Every
   signed release then needs one approval, and no other branch or pull request
   can read the signing key.

## Signing is required for a release

The action never publishes an unsigned release. With `deliver: true`:

- An empty `signing-key` or `org` stops the run before anything uploads.
- If the server does not know the key, the run fails and names
  `atc org key register`. Re-run the job after you register the key. The re-run
  adopts the release that the failed run created.
- If the result reports `signed: false`, the step fails.
- If an earlier publish already published the same content under the same
  version label, `atc` reuses that release and does not sign it again. The
  action cannot prove that the earlier release is signed, so the step fails.
  Publish under a new version label. On a channel that requires signed
  releases, the server never reuses an unsigned release.

## How the action keeps the secrets out of the log

- Every input reaches the scripts through `env:`. No `${{ }}` expression is
  inlined in a `run:` script, so debug logging cannot print a secret.
- The token reaches `atc` as `ATC_SERVER_TOKEN`. The key reaches `atc` as a
  file, `$RUNNER_TEMP/atc-action-home/org-keys/<org>.key`, mode 0600. Neither
  is ever on a command line.
- The action masks the token and the trimmed key, because GitHub masks only
  the exact secret string.
- `atc` runs with `ATC_CONFIG_HOME` set to that private directory. It does not
  read a login or a key that an earlier job left on a self-hosted runner.
- The action deletes the directory when the step exits, and a final
  `if: always()` step deletes it again.

Masking is not a security boundary. Anyone who can change a workflow that runs
in the environment can read its secrets. Protect `.github/workflows/` with
code-owner review, and pin this action by commit SHA.

## GitLab CI

`gitlab/atc-publish.yml` is a GitLab CI include. It holds every script it
runs, so one commit SHA pins all of it. GitLab fetches it without
authentication, so this repository must be public. While it is private,
commit the file to your project at a pinned commit and use `include: local:`
with the same `inputs`.

To get every value below in one place, run `atc ci gitlab --channel <name>`.

```yaml
# .gitlab-ci.yml
# `deploy` must be one of your stages. GitLab's default stages have it.

include:
  - remote: https://raw.githubusercontent.com/Agency-Tool-Company/atc-action/<commit-sha>/gitlab/atc-publish.yml
    inputs:
      stage: deploy
      channel: stable
      deliver: true
      org: <org-id>
      install-url: <install-url>
      server: <server-url>
```

`install-url` is the URL of the atc installer, as on GitHub. `server` is your
atc-server URL. Leave the line out when the config's `server` block names it.

Use the full 40-character SHA. The job is named `atc-publish`. It runs on a
tag that starts with `v`, in the `release` environment. `stage` must be one
of the stages of your project.

The inputs are the GitHub inputs without `token` and `signing-key`, plus:

| Input | Default | Description |
|---|---|---|
| `stage` | `deploy` | Stage of the job. It must be in your `stages`. |
| `environment` | `release` | Environment of the job. Scope the variables to it. |
| `image` | `debian:bookworm-slim` | Job image. It needs `bash`. As root on an image with `apt-get` or `apk`, the job installs `curl`, `jq` and CA certificates when they are missing. |

The token and the key are CI/CD variables, never inputs. GitLab writes inputs
into the expanded configuration, which the pipeline editor shows. In Settings
→ CI/CD → Variables, add `ATC_TOKEN` (the operator key) and `ATC_SIGNING_KEY`
(the contents of the key file). Select **Protect variable** and **Mask
variable**, and set the environment scope to `release`.

Store each value as one line with no spaces. The job refuses a value with
whitespace, because GitLab masks only the stored string. Protect your release
tags (Settings → Repository → Protected tags): a protected variable reaches
only jobs on a protected branch or tag.

GitLab has no tag-only rule for variables. A job on a protected branch, such
as the default branch, also gets the variables when its environment is
`release`. So give no other job that environment. On a Premium or Ultimate
plan, also protect it (Settings → CI/CD → Protected environments), with an
approval for a production channel.

To change `rules`, `needs` or `tags`, define a job named `atc-publish` in your
own file. GitLab merges it over the included job and replaces those lists.
Do not widen `rules` to a branch: the job would sign from that branch. Do not
set `script` or `after_script`. GitLab replaces them instead of appending.
`script` is the publish, and `after_script` removes the key directory of a
killed job.

A later job reads the result from the job's dotenv report:

| Variable | Value |
|---|---|
| `ATC_PUBLISH_DELIVERY_ID` | The release that the run created or reused. Empty without `deliver`. |
| `ATC_PUBLISH_VERSION` | The published version label. |
| `ATC_PUBLISH_SIGNED` | `true` when this run signed the release. Empty without `deliver`. |
| `ATC_PUBLISH_CONSOLE_URL` | Console link to the release, when a console URL is known. |

A job that sets `dependencies: []`, or `needs` with `artifacts: false`, does
not get them. The summary table is in the job log. An error is a line that
starts with `error:`.

On a shell executor, the key directory is `$TMPDIR/atc-action-<job id>`
(default `/tmp`), mode 0700. The job removes it when it exits, and
`after_script` removes it, and the job's script directory, after a job that
was killed.

## Bitbucket Pipelines

A Bitbucket step runs `scripts/run.sh bitbucket` from a copy of this
repository at one commit.

To get every value below in one place, run `atc ci bitbucket --channel <name>`.

```yaml
# bitbucket-pipelines.yml
pipelines:
  tags:
    "v*":
      - step:
          name: atc publish
          image: atlassian/default-image:4
          deployment: production
          script:
            - export ATC_ACTION_REF=<commit-sha>
            - rm -rf /tmp/atc-action && mkdir -p /tmp/atc-action
            - env -u ATC_TOKEN -u ATC_SIGNING_KEY curl -fsSL --retry 3 --retry-delay 2 "https://github.com/Agency-Tool-Company/atc-action/archive/$ATC_ACTION_REF.tar.gz" | env -u ATC_TOKEN -u ATC_SIGNING_KEY tar -xz --strip-components=1 -C /tmp/atc-action
            - export ATC_ACTION_CHANNEL=stable ATC_ACTION_DELIVER=true ATC_ACTION_ORG=<org-id> ATC_ACTION_INSTALL_URL=<install-url> ATC_ACTION_SERVER=<server-url>
            - bash /tmp/atc-action/scripts/run.sh bitbucket
          after-script:
            - rm -rf "${TMPDIR:-/tmp}/atc-action-$(printf '%s' "$BITBUCKET_STEP_UUID" | tr -cd 'A-Za-z0-9_-')"
          artifacts:
            - atc-publish.env
```

`ATC_ACTION_INSTALL_URL` is the URL of the atc installer, as on GitHub.
`ATC_ACTION_SERVER` is your atc-server URL. Leave it out when the config's
`server` block names it.

Use the full 40-character SHA. The step downloads the archive without
authentication, so the archive URL works only while this repository is
public. While it is private, GitHub returns 404. Then commit the `scripts/`
directory of this repository at a pinned commit to your project, for example
as `.atc-action/scripts/`. Remove the first three lines of `script`, and
replace its last line with this line, which downloads nothing:

```yaml
            - bash .atc-action/scripts/run.sh bitbucket
```

The image needs `bash`, `curl`, `tar` and CA certificates, because the
step's own lines use them. As root on an image with `apt-get` or `apk`, the
step installs `jq` when it is missing.

`env -u` keeps the secured variables out of `curl` and `tar`. The
`after-script` removes the key directory after a self-hosted runner kills the
step, because a kill skips the cleanup of `run.sh`. It keeps only letters,
digits, `_` and `-` of the step UUID, as `run.sh` does. The line that
removes `/tmp/atc-action` clears a tree that an earlier step left on a
persistent runner.

The inputs are the GitHub inputs without `token` and `signing-key`, as
variables that the step exports:

| Variable | Input |
|---|---|
| `ATC_ACTION_CHANNEL`, `ATC_ACTION_VERSION`, `ATC_ACTION_DELIVER`, `ATC_ACTION_ORG`, `ATC_ACTION_INSTALL_URL`, `ATC_ACTION_SERVER`, `ATC_ACTION_CONSOLE_URL`, `ATC_ACTION_CONFIG`, `ATC_ACTION_ONLY`, `ATC_ACTION_WAIT` | The GitHub input of the same name, in lower case with `-` for `_`. |
| `ATC_ACTION_TRACK` | `atc-track`. |

`ATC_ACTION_VERSION` defaults to `BITBUCKET_TAG`, else `BITBUCKET_BRANCH`.

The token and the key are secured deployment variables, never exported in
the step. In Repository settings → Pipelines → Deployments, open the
environment that `deployment:` names. Add `ATC_TOKEN` (the operator key) and
`ATC_SIGNING_KEY` (the contents of the key file), and select **Secured**.
Store each value as one line with no spaces. The step refuses a value with
whitespace, because Bitbucket masks only the stored string.

Outside a deployment stage, a pipeline can use each environment in one step
only, so give no other step this one. Bitbucket lets any pipeline deploy to an
environment until you set deployment permissions, which need a Premium plan.
A branch list that holds only `main` does not match this tag step, so the
step cannot deploy. If your plan accepts patterns in the list, allow `v*`. A
permission for users or groups can pause the automatic tag run until an
allowed user resumes it.

The step writes the four `ATC_PUBLISH_` variables of the GitLab table to
`atc-publish.env` in `BITBUCKET_CLONE_DIR`, because Bitbucket collects
artifacts only from there. A later step reads them with
`source atc-publish.env`. The summary table is in the step log. An error is
a line that starts with `error:`. An input error names the variable to
set.

On a self-hosted runner, the key directory is
`$TMPDIR/atc-action-<step uuid>` (default `/tmp`), mode 0700. The step
removes it when it exits, and the `after-script` removes it after a kill.

## Development

We build the action in our own source tree and publish each change here as
one commit. Each publish replaces the whole tree, so we can't merge pull
requests here. Found a bug or stuck on setup? Open an issue.

The scripts are:

- `scripts/install-atc.sh` installs the atc CLI.
- `scripts/publish.sh` lints and publishes.
- `scripts/run.sh <platform>` is the entry point on GitLab CI and Bitbucket
  Pipelines. It maps the platform's variables, checks for curl, jq and CA
  certificates, and runs the other two scripts. GitHub does not use it.
- `scripts/platform.sh` loads the platform adapter,
  `scripts/platform-<name>.sh`. The adapter holds all the code that differs
  per platform: how the scripts report errors, outputs and the summary, and
  the names of the inputs. `scripts/dotenv-adapter.sh` holds the part that
  the GitLab and Bitbucket adapters share.
- `gitlab/atc-publish.yml` is a generated file. It holds the job and a copy
  of each script that the job runs. Do not edit it.

## License

Copyright 2026 Agency Tool Company. Licensed under the Apache License, Version
2.0. See [LICENSE](LICENSE).
