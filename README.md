# hq-caddy

A standalone [Caddy](https://caddyserver.com) proxy that takes its sites from a
Git repository. Push a site file, and within one poll it's live on
`https://<name>.<your-domain>`, with a trusted wildcard certificate, even for
LAN-only names.

- **Image:** the official `caddy` image plus two modules, built the way the
  official image documents (`caddy:<version>-builder` + `xcaddy`):
  [`caddy-dns/cloudflare`](https://github.com/caddy-dns/cloudflare) (DNS-01, so
  wildcard certificates work for names that only resolve on your LAN) and
  [`mholt/caddy-l4`](https://github.com/mholt/caddy-l4) (raw TCP forwards, e.g.
  SSH for a Git server).
- **Safe changes:** every new commit is built and validated before Caddy reloads.
  A broken commit is never applied: the running config stays, the commit gets a
  failed status naming the broken file, and the sites page shows a banner.
- **A status page** at `https://sites.<domain>`: every site with a health dot,
  TCP forwards, and the DNS records that point at your LAN.

Images: `ghcr.io/realbeepmcjeep/hq-caddy` for `linux/amd64` and `linux/arm64`,
rebuilt by GitHub Actions only when an upstream version changes. Tags: `latest`,
dated `YYYYMMDD-HHMMSS` (pin or roll back with these) and `sha-<commit>`.

## How a change goes live

1. Edit a file in your config repository (layout below).
2. Optional: validate it first with `hq-caddy check <checkout>` (see Commands).
3. Push to the branch hq-caddy follows.
4. Within `HQ_POLL_SECONDS` hq-caddy fetches it, builds, **validates**, reloads,
   and sets a commit status: ✓ applied, or ✗ rejected with the reason.

Roll back with `git revert`. On restart, hq-caddy serves the last good
configuration at once, even if the Git server is down.

## Config repository

```
sites/<name>.caddy   one site: https://<name>.<domain>
tcp/<name>.caddy     one raw TCP forward
```

A site is usually one line:

```caddy
import proxy myapp 192.0.2.10:8080
```

Anything Caddy supports works with `import site`:

```caddy
import site api {
	reverse_proxy 192.0.2.10:8080 {
		header_up Host {upstream_hostport}
	}
}
```

- **Names:** `a-z`, `0-9` and `-`, with dots for `<service>.<host>`
  (e.g. `dockge.nas`). Each host gets one wildcard certificate,
  `*.<host>.<domain>`, so new services on it need no new certificate.
- **TCP:** `import forward 2222 192.0.2.20:22` listens on port 2222 on every
  `PROXY_BIND` address. TCP has no hostname, so each port goes to exactly one
  destination.
- **Reserved:** `sites` is the status page. Unknown names get a 404 page linking
  to it.

### Services that listen only on loopback elsewhere (`relay`)

A service on another box that listens only on `127.0.0.1` is reached through a small
**relay** on that box. The relay accepts connections only from this proxy's address
and forwards to the loopback port named in the `X-Hq-Relay-Port` header. Set
`HQ_RELAY=<relay host>:<port>`, then say it explicitly in the site file:

```caddy
import relay myapp 8788                 # https://myapp.<domain> -> relay -> 127.0.0.1:8788
import relay_files docs                 # the relay's static folder "docs" (chosen by Host)
import site api {
	respond /internal/* 404
	import relay_upstream 9000          # inside a custom block
}
```

`relay_files` removes any `X-Hq-Relay-Port` a client sent. Without `HQ_RELAY`, these
sites answer 502 "relay not configured". The relay itself (trust only this proxy's
IP, keep its `X-Forwarded-*`) runs on the other box.

### Status checks

One `# check:` line in a site or tcp file gives it a dot on the status page:

| Line | Up when |
|---|---|
| `# check: /path` | The path answers 200–399 through the proxy (DNS, certificate, proxy and app together) |
| `# check: /path 200,401` | The status is one of these (`2xx` and `200-299` work too) |
| `# check: https://host/path` | That URL answers 200–399 |
| `# check: tcp` | The file's upstream accepts TCP connections (or `tcp host:port`) |
| `# check: run <command>` | The command (`sh -c`) exits 0. Exit 1 is down, anything else unsure; the first output line is the note |

Red: no answer, a 5xx, or exit 1. Yellow: another status, a certificate
problem, or no result yet. Each entry is checked at most every
`PROXY_CHECK_INTERVAL` seconds.

## Settings

| Variable | Meaning |
|---|---|
| `PROXY_DOMAIN` | **Required.** Sites are `https://<name>.<domain>` |
| `CLOUDFLARE_API_TOKEN` or `CLOUDFLARE_API_TOKEN_FILE` | Cloudflare token with DNS edit on the zone (DNS-01 certificates, DNS helpers) |
| `HQ_CONFIG_REPO` | Git URL of the config repository (`https://…` or `file://…`) |
| `HQ_CONFIG_BRANCH` | Branch to follow (default `main`) |
| `HQ_CONFIG_USER` / `HQ_CONFIG_TOKEN_FILE` | Credentials for HTTPS fetches; the token also posts commit statuses (Gitea API). Passed to git through its environment, never on the command line |
| `HQ_CONFIG_DIR` | Instead of a repository: a mounted folder, re-read when it changes |
| `HQ_POLL_SECONDS` | Seconds between fetches (default 30, minimum 5) |
| `HQ_STATUS_CONTEXT` | Name of the commit status (default `hq-caddy`); give test instances their own |
| `PROXY_BIND` | Addresses to listen on, comma- or space-separated (default: all) |
| `PROXY_HTTP_PORT` / `PROXY_HTTPS_PORT` | Listener ports (default 80/443) |
| `PROXY_MANAGE_DNS` | `true`: create a missing `*.<host>.<domain>` A record for each `<service>.<host>` site (create-only, never edits or deletes) |
| `PROXY_DNS_TARGET` | Address for those records (default: the first IPv4 `PROXY_BIND`) |
| `PROXY_CHECK_INTERVAL` | Seconds between status checks of one entry (default 300, minimum 60) |
| `HQ_RELAY` | `host:port` of a relay for loopback-only services on another box (`relay`, `relay_upstream`, `relay_files`) |
| `HQ_TLS` | `internal`: certificates from Caddy's local CA instead of Let's Encrypt (testing) |

Point a DNS-only wildcard `*.<domain>` at the proxy's address. A host that has
its own record (e.g. `nas.<domain>`) also needs `*.nas.<domain>` for
`<service>.nas` names; `PROXY_MANAGE_DNS` creates those. Any `*.<host>` record
pointing at the proxy gets the 404 page and a certificate, even with no sites.

## Deploying

See [`examples/compose.yaml`](examples/compose.yaml). Mount a volume at `/data`:
it holds the ACME account, the certificates, the config checkout and the last
good configuration. To move an existing Caddy, copy its data directory
(`caddy/` with `certificates/` and `acme/`) into `/data/caddy` first, so nothing
is re-issued.

For commit statuses, give the proxy its own Git account with write access to the
config repository only, and mount its token as a file.

## Commands

Run them with `docker exec <container> hq-caddy <command>`.

| Command | What it does |
|---|---|
| `run` | The default: Caddy, the sync loop and the status checks |
| `status` | The applied commit, a rejected commit and why, fetch errors, Caddy's state |
| `show` | Print the active Caddy configuration (no secrets) |
| `checks` | List every status check result |
| `sync` | Fetch and apply now instead of at the next poll (also retries a rejected commit) |
| `check DIR` | Build and validate a checkout without applying it; names broken files |
| `--version` | hq-caddy and Caddy versions |

## Development

`scripts/probe-versions.sh` pins the exact inputs (Caddy release and image digests,
module versions). CI builds amd64 and runs the self-test in the built image (a
local Git repository, a rejected commit, the fix, status checks, a clean stop),
then builds amd64 and arm64, and publishes from `main` only. See `AGENTS.md`.
