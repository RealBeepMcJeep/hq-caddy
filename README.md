# hq-caddy

A standalone [Caddy](https://caddyserver.com) proxy image: the **official `caddy`
image** plus two modules, built the way the official image documents
(`caddy:<version>-builder` + `xcaddy`):

| Module | For |
|---|---|
| [`caddy-dns/cloudflare`](https://github.com/caddy-dns/cloudflare) | DNS-01 challenges, so wildcard certificates work for LAN-only names |
| [`mholt/caddy-l4`](https://github.com/mholt/caddy-l4) | Raw TCP forwards (for example SSH for a Git server) |

It also carries `python3` and `git` for its config generator, which is being
built in stages: sync site files from a Git repository, validate before every
reload, report results as commit statuses, and serve a status page.

Images: `ghcr.io/realbeepmcjeep/hq-caddy` for `linux/amd64` and `linux/arm64`,
rebuilt by GitHub Actions only when an upstream version changes (see
`scripts/probe-versions.sh`). Tags: `latest`, dated `YYYYMMDD-HHMMSS`
(roll back with these) and `sha-<commit>`.

## Status

Stage 2: the generator. `hq-caddy run` (the default command) pulls site files
from a Git repository (`HQ_CONFIG_REPO`, or a mounted `HQ_CONFIG_DIR`), validates
every new commit before reloading Caddy, reports the result as a commit status,
and serves `https://sites.<domain>` with status checks. `hq-caddy --help` lists
every setting and command; full documentation follows. Certificates and state
live in `/data`, so mount a volume there.
