# sample-web

[![build](https://img.shields.io/github/actions/workflow/status/nalbam/sample-web/push.yaml?label=build&style=for-the-badge&logo=github)](https://github.com/nalbam/sample-web/actions/workflows/push.yaml)
[![release](https://img.shields.io/github/v/release/nalbam/sample-web?style=for-the-badge&logo=github)](https://github.com/nalbam/sample-web/releases)

<!-- [![CircleCI](https://circleci.com/gh/nalbam/sample-web.svg?style=svg)](https://circleci.com/gh/nalbam/sample-web) -->

## Docker

```bash
docker pull ghcr.io/nalbam/sample-web
docker run -d --name sample-web -p 8080:80 ghcr.io/nalbam/sample-web
curl -I http://localhost:8080/index.html
```

## Build

```bash
docker build -t sample-web .
docker run -d --name sample-web -p 8080:80 sample-web
curl -I http://localhost:8080/index.html
```

The `build` workflow (`.github/workflows/push.yaml`) builds the image, starts the container, and checks that `/index.html` and `/favicon.ico` return HTTP 200. It runs on pull requests and pushes to `main` or `master`, and the release workflow calls it. It only reads the repository, uses no secrets, and publishes nothing.

## Release

Branch pushes only run CI. To release, push a `v*` SemVer tag such as `v0.10.0` or `v0.11.0-rc.1`:

```bash
git tag v0.10.0
git push origin v0.10.0
```

The tag must be `vMAJOR.MINOR.PATCH` with an optional prerelease suffix. Leading zeros, `+build` metadata, and tags longer than 128 characters fail the release. The Git tag is the only version source; the `VERSION` and `BUMP` files are not used or updated.

The [release workflow](.github/workflows/release.yml) runs the `build` workflow on the tagged commit, then:

1. Builds `src/` into the Nginx image for `linux/amd64` and `linux/arm64` and pushes `ghcr.io/nalbam/sample-web:<tag>`, for example `ghcr.io/nalbam/sample-web:v0.10.0`. Stable tags also update `latest`. Prerelease tags only publish their version tag.
2. After the image push succeeds, creates a GitHub Release with commit notes since the previous reachable version tag. Merge commits and `chore: release` commits are excluded. Tags with a prerelease suffix create GitHub prereleases. A rerun pushes the same image tag again and updates the existing GitHub Release.

Each stage runs only if the previous stage succeeds. Release runs are serialized across tags because they share `latest`; a queued run waits and is not cancelled.

Release outputs are the GHCR image and the GitHub Release. The workflow does not send a GitOps dispatch or deploy: `opspresso/argocd-env-demo` has no chart or phase values for this project yet. Connecting GitOps needs a target chart, phases, and image address there first.

Requirements:

- No repository secrets. The workflow uses `GITHUB_TOKEN`: `packages: write` only in the image job and `contents: write` only in the GitHub Release job. Other jobs read only.
- **Settings > Actions > General** must allow the `actions/*` and `docker/*` actions used by the workflows.
- If the `sample-web` GHCR package already exists, its **Manage Actions access** must give this repository write access.

The legacy `.circleci/config.yml` keeps only its `build` and `publish` jobs; it no longer runs a release, Docker, or trigger job.
