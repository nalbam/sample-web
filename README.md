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

The `build` workflow (`.github/workflows/push.yaml`) builds the image and checks that `index.html` and `favicon.ico` return HTTP 200 on pull requests and on pushes to `main`. Version bump, GitHub release, GitOps dispatch and image push run only on pushes to `main`. The image is published to GHCR (`ghcr.io/nalbam/sample-web`) with `GITHUB_TOKEN`.
