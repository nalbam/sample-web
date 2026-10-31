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

## Build and test

Requirements: Docker, `curl`, `openssl`, and network access to the CDNs below. Run the commands from the repository root.

```bash
docker build --pull -t sample-web .
docker run --rm --entrypoint nginx sample-web -v
docker run -d --name sample-web -p 8080:80 sample-web
test/smoke.sh http://localhost:8080
docker rm -f sample-web
```

`test/smoke.sh` is the test for this static site. It exits with a non-zero status and prints `FAIL:` lines if a check fails. It checks that:

- `/`, `/index.html`, and `/favicon.ico` return HTTP 200 with `text/html` or `image/x-icon` and the same bytes as the files in `src/`.
- `src/index.html` keeps its title, logo, `sample-web` heading, and thumbs-up/down buttons with Font Awesome 7 icons, and has no Bootstrap 4 `jumbotron` or Font Awesome 5 markup.
- Each CDN stylesheet and script has `integrity` and `crossorigin="anonymous"`, downloads with HTTP 200, and matches its hash.

The `build` workflow (`.github/workflows/push.yaml`) builds the image for `linux/amd64` and `linux/arm64` with `--pull`, checks that the image runs Nginx 1.30.x, starts the container, and runs `test/smoke.sh`. It always prints the container logs and removes the container. It runs on pull requests and pushes to `main` or `master`, and the release workflow calls it. It only reads the repository, uses no secrets, and publishes nothing.

To check the page in a browser, open `http://localhost:8080/` at desktop width and at a phone width such as 375 px. The logo, `sample-web` heading, and both buttons with their icons must show. The browser console shows only the `counter.js` error described below.

### Versions

| Component | Version | Source |
|---|---|---|
| Nginx base image | `nginx:1.30-alpine` (stable line, 1.30.6 on 2026-10-31) | `Dockerfile` |
| Bootstrap CSS | 5.3.8 | jsDelivr, `src/index.html` |
| Font Awesome Free CSS | 7.3.1 | `use.fontawesome.com`, `src/index.html` |
| jQuery | 4.0.0 | `code.jquery.com`, `src/index.html` |

The page uses no Bootstrap JavaScript components, so it does not load Bootstrap JavaScript. jQuery stays for `counter.js`: the same script in `nalbam/sample-spring` uses jQuery (`$.ajax`, `$(...)`, `.click`). To change a CDN version, update the URL and its `integrity` hash together, then run `test/smoke.sh`.

### External constraints

- `https://nalbam.com/static/sample/counter.js` returned HTTP 404 on 2026-10-31. The counters stay at `0` and the buttons do nothing. Browsers report a blocked or failed request for this script. This repository does not contain the script or a counter backend. `test/smoke.sh` prints its status but does not fail on it.
- The logo (`https://nalbam.com/static/logo/nginx.png`) and the CSS and JavaScript load from external hosts. The page needs network access to them.

## Release

Branch pushes only run CI. To release, choose a `main` commit whose `build` workflow succeeded, then push a `v*` SemVer tag such as `v0.10.0` or `v0.11.0-rc.1` on that commit:

```bash
gh run list --workflow push.yaml --branch main --status success --limit 5 --json headSha,displayTitle,url
git tag v0.10.0 <commit-sha>
git push origin v0.10.0
```

The tag must be `vMAJOR.MINOR.PATCH` with an optional prerelease suffix. Leading zeros, `+build` metadata, and tags longer than 128 characters fail the release. The Git tag is the only version source; the `VERSION` and `BUMP` files are not used or updated.

The [release workflow](.github/workflows/release.yml) runs the `build` workflow on the tagged commit, then:

1. Builds `src/` into the Nginx image for `linux/amd64` and `linux/arm64` and pushes `ghcr.io/nalbam/sample-web:<tag>`, for example `ghcr.io/nalbam/sample-web:v0.10.0`. Stable tags also update `latest`. Prerelease tags only publish their version tag.
2. After the image push succeeds, creates a GitHub Release with commit notes since the previous reachable version tag. Merge commits and `chore: release` commits are excluded. Tags with a prerelease suffix create GitHub prereleases. A rerun pushes the same image tag again and updates the existing GitHub Release.

Each stage runs only if the previous stage succeeds. Release runs are serialized across tags because they share `latest`. A running release is never cancelled by a new tag push. GitHub Actions keeps only one pending run per concurrency group, so a newer tag push cancels a release that is still waiting. For example, if `v1.0.0` is running and `v1.0.1` is waiting, pushing `v1.0.2` cancels the `v1.0.1` run, and that tag gets no image and no GitHub Release. To release a cancelled tag, open its run in the **Actions** tab and select **Re-run all jobs** after the running release finishes. Rerunning an older stable tag also moves `latest` back to that tag. Then rerun the newest stable tag to point `latest` at it again.

Release outputs are the GHCR image and the GitHub Release. The workflow does not send a GitOps dispatch or deploy: `opspresso/argocd-env-demo` has no chart or phase values for this project yet. Connecting GitOps needs a target chart, phases, and image address there first.

Requirements:

- No repository secrets. The workflow uses `GITHUB_TOKEN`: `packages: write` only in the image job and `contents: write` only in the GitHub Release job. Other jobs read only.
- **Settings > Actions > General** must allow the `actions/*` and `docker/*` actions used by the workflows.
- If the `sample-web` GHCR package already exists, its **Manage Actions access** must give this repository write access.

After the release workflow finishes, check its outputs:

```bash
tag=v0.10.0
run_id="$(gh run list --workflow release.yml --branch "$tag" --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run view "$run_id" --exit-status
gh release view "$tag"
docker buildx imagetools inspect "ghcr.io/nalbam/sample-web:$tag"
git switch --detach "$tag"
docker run -d --name sample-web-release -p 8080:80 "ghcr.io/nalbam/sample-web:$tag"
test/smoke.sh http://localhost:8080
docker rm -f sample-web-release
```

`gh run view --exit-status` exits with a non-zero status unless the run succeeded. `imagetools inspect` must list `linux/amd64` and `linux/arm64`. `test/smoke.sh` compares the image content with `src/` of the checked-out tag.

The legacy `.circleci/config.yml` keeps only its `build` and `publish` jobs; it no longer runs a release, Docker, or trigger job. It cannot run as written: it downloads `toast.sh/builder`, which returned HTTP 404 on 2026-10-31, and `publish` runs only on a `master` branch, which this repository does not have. No recent commit has a CircleCI status. The legacy `.gitlab-ci.yml` pins `docker:29.9.2` and `docker:29.9.2-dind` and pushes to the GitLab project registry; it is not run from this GitHub repository.
