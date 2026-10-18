# AGENTS.md: hq-caddy

- **Default work mode: solo** (admin decision, 2026-10-18): a short-lived
  `<role>/<issue#>-<short>` branch, then a PR you merge yourself after CI is green.
  PRs say `Mode: solo`.
- **Public repository:** no personal or deployment values (domains, addresses,
  hostnames, tokens). Examples use `example.com`, `192.0.2.0/24` and
  `git.example.com`. Real values live only in the deployment's private stack.
- **Checks before a PR:**
  - `python3 -m py_compile rootfs/usr/local/bin/hq-caddy` and `uvx pyflakes rootfs/usr/local/bin/hq-caddy`
  - `shellcheck scripts/probe-versions.sh`, and the self-test step extracted from `.github/workflows/build.yml`
  - for generator changes, run it locally against a `file://` repository with
    `HQ_TLS=internal`, `HQ_STATE_DIR`, `HQ_ADMIN` and high ports, as the CI self-test does
- **CI** (GitHub, through the Gitea push mirror) is the gate: amd64 build and
  self-test, then amd64+arm64. Publishing happens from `main` only.
- **Compatibility:** site files use the snippets `proxy`, `site` and `forward`;
  keep their names and meaning, since existing config repositories depend on them.
