#!/usr/bin/env bash
# Print the exact upstream inputs an image build would use, one KEY=VALUE per
# line (also valid as Docker build args). CI hashes this output together with
# the build files: an unchanged hash means there is nothing to rebuild.
#
# Needs: curl, jq, git. GitHub API calls use GH_TOKEN when it is set.
set -euo pipefail

emit() {
  # Fail loudly on an empty value rather than building with a blank version.
  [ -n "$2" ] || { echo "probe: no value for $1" >&2; exit 1; }
  printf '%s=%s\n' "$1" "$2"
}
latest_git_tag() {
  # Highest semver tag of a Go module repository (modules publish git tags, not releases).
  git ls-remote --tags --refs "$1" | awk -F/ '{ print $3 }' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1
}

# Official caddy images, read from the AWS public mirror of Docker Hub's library
# (no Docker Hub pull limits). Use the newest release that has both variants.
repository=docker/library/caddy
token=$(curl -fsSL "https://public.ecr.aws/token/?scope=repository:$repository:pull" | jq -er .token)
tags=$(curl -fsSL -H "Authorization: Bearer $token" "https://public.ecr.aws/v2/$repository/tags/list" | jq -er '.tags[]')
caddy_version=$(grep -E '^[0-9]+\.[0-9]+\.[0-9]+-builder$' <<< "$tags" | sed 's/-builder$//' | sort -V |
  while read -r version; do grep -qx "$version-alpine" <<< "$tags" && echo "$version"; done | tail -n 1)
digest() {
  curl -fsSI -H "Authorization: Bearer $token" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
    "https://public.ecr.aws/v2/$repository/manifests/$1" | tr -d '\r' |
    awk 'tolower($1) == "docker-content-digest:" { print $2 }'
}

emit CADDY_VERSION "$caddy_version"
emit CADDY_BUILDER_IMAGE "public.ecr.aws/$repository:$caddy_version-builder@$(digest "$caddy_version-builder")"
emit CADDY_IMAGE "public.ecr.aws/$repository:$caddy_version-alpine@$(digest "$caddy_version-alpine")"
emit CADDY_CLOUDFLARE_VERSION "$(latest_git_tag https://github.com/caddy-dns/cloudflare.git)"
emit CADDY_L4_VERSION "$(latest_git_tag https://github.com/mholt/caddy-l4.git)"
# Alpine packages (python3, git) refresh at least weekly.
emit ALPINE_REFRESH "$(date -u +%G-W%V)"
