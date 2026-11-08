# sample-web

[![ci](https://img.shields.io/github/actions/workflow/status/nalbam/sample-web/ci.yml?branch=main&label=ci&style=for-the-badge&logo=github)](https://github.com/nalbam/sample-web/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/nalbam/sample-web?style=for-the-badge&logo=github)](https://github.com/nalbam/sample-web/releases)

A static web page served by Nginx. It has no database or other dependencies.

## Run

```bash
docker run -d --name sample-web -p 8080:8080 ghcr.io/nalbam/sample-web
curl http://localhost:8080/health
docker rm -f sample-web
```

The image runs as the unprivileged `nginx` user (uid 101) and needs no Linux capabilities, so it works with `--cap-drop ALL`.

| Environment variable | Default | Description |
| --- | --- | --- |
| `PORT` | `8080` | Listen port. |
| `VERSION` | `v0.0.0-dev` | Version that `/health` reports. Release images set it to their tag; a local build sets it with `--build-arg VERSION=...`. |

| Path | Response |
| --- | --- |
| `/health` | `{"result":"ok","version":"<VERSION>"}` |
| `/`, `/index.html`, `/favicon.ico` | Files from `src/`. |
| Any other path | HTTP 404. |

Every response, including `/health` and a 404, has these security headers
(`nginx/templates/default.conf.template`):

| Header | Value |
| --- | --- |
| `X-Content-Type-Options` | `nosniff` |
| `Referrer-Policy` | `no-referrer` |
| `X-Frame-Options` | `DENY` |
| `Content-Security-Policy` | Allows the page's own origin (`'self'`) and only the external hosts below. No inline scripts or styles and no `eval`. |

| CSP directive | Allowed sources |
| --- | --- |
| `default-src` | `'self'` |
| `script-src` | `'self'`, `https://code.jquery.com`, `https://nalbam.com` |
| `style-src` | `'self'`, `https://cdn.jsdelivr.net`, `https://use.fontawesome.com` |
| `font-src` | `https://use.fontawesome.com` |
| `img-src` | `'self'`, `https://nalbam.com`, `data:` (Bootstrap CSS images) |
| `connect-src` | `'self'`, `https://nalbam.com` |
| `object-src`, `base-uri`, `form-action`, `frame-ancestors` | `'none'` |

When you add or change a CDN, external script or image in `src/index.html`, change the
`Content-Security-Policy` in the template in the same change. Otherwise the browser blocks the new host.

## Develop

Prerequisites: Docker with Buildx, and `jq`.

```bash
docker buildx build --load -t sample-web:dev .   # runs the tests in the build stage
scripts/smoke.sh sample-web:dev
```

The `build` stage runs two tests:

- `test/runtime.sh` renders `nginx/templates` with the image entrypoint script and a non-default `PORT`,
  starts Nginx as the `nginx` user, and checks `/health`, the files from `src/` and a 404. It also checks the
  four security headers on `/`, `/health` and `/does-not-exist`, and compares the CSP with the template.
  It needs no network.
- `test/content.sh` checks the markup of `src/index.html`, and checks that every CDN stylesheet and script has
  `integrity` and `crossorigin="anonymous"` and matches its hash. It downloads the CDN files.

| Component | Version | Source |
| --- | --- | --- |
| Nginx base image | `nginx:1.31-alpine` | `Dockerfile` |
| Bootstrap CSS | 5.3.8 | jsDelivr, `src/index.html` |
| Font Awesome Free CSS | 7.3.1 | `use.fontawesome.com`, `src/index.html` |
| jQuery | 4.0.0 | `code.jquery.com`, `src/index.html` |

`scripts/smoke.sh IMAGE [VERSION]` starts the image with `--cap-drop ALL` and checks `/health`, the page title,
`/favicon.ico`, a 404 and the non-root user. It checks the four security headers on `/`, `/health` and
`/does-not-exist`, with the CSP compared to the template, and then checks `/health` and the headers of `/` again on
another `PORT`. It needs Docker and `jq`.

`test/evidence/csp/probe.js` is a manual check, not part of CI. It serves `src/` with the headers from the template
and opens the page in headless Chromium with Playwright. The output in that folder records no CSP violations.

To change a CDN version, change the URL and its `integrity` hash together. To change a CDN host, also change the CSP.

External constraints:

- `https://nalbam.com/static/sample/counter.js` returns HTTP 404, so the counters stay at `0`.
  This repository does not contain the script. `test/content.sh` reports its status but does not fail on it.
- The logo and the CSS and JavaScript files load from external hosts.

## CI/CD

Pull requests and pushes to `main` run CI. A `v*` tag releases the image `ghcr.io/nalbam/sample-web:<tag>`
and a GitHub Release with the site archive. Jenkins can run the same pipeline with Nexus and Harbor or ECR.
See [docs/pipeline.md](docs/pipeline.md).
