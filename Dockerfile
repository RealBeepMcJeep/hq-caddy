# hq-caddy: the official caddy image plus two modules, built the way the
# official image documents (caddy:<version>-builder + xcaddy):
#   - github.com/caddy-dns/cloudflare  (DNS-01 for wildcard certificates)
#   - github.com/mholt/caddy-l4        (raw TCP forwards)
# plus python3 and git for the config generator (hq-caddy).
#
# Build arguments come from scripts/probe-versions.sh (exact versions and image
# digests); the defaults only make a plain `docker build` work.
ARG CADDY_BUILDER_IMAGE=public.ecr.aws/docker/library/caddy:2-builder
ARG CADDY_IMAGE=public.ecr.aws/docker/library/caddy:2-alpine

# The builder runs on the build machine and cross-compiles for each target.
FROM --platform=$BUILDPLATFORM ${CADDY_BUILDER_IMAGE} AS builder
ARG CADDY_CLOUDFLARE_VERSION=v0.2.4
ARG CADDY_L4_VERSION=v0.1.2
ARG TARGETOS
ARG TARGETARCH
RUN GOOS="$TARGETOS" GOARCH="$TARGETARCH" CGO_ENABLED=0 xcaddy build \
      --with "github.com/caddy-dns/cloudflare@${CADDY_CLOUDFLARE_VERSION}" \
      --with "github.com/mholt/caddy-l4@${CADDY_L4_VERSION}" \
      --output /caddy

FROM ${CADDY_IMAGE}
# Changes weekly so Alpine package updates are picked up (see the probe).
ARG ALPINE_REFRESH=unset
RUN echo "alpine refresh: ${ALPINE_REFRESH}" > /dev/null \
    && apk add --no-cache python3 git tini
COPY --from=builder /caddy /usr/bin/caddy
COPY rootfs/ /
RUN chmod 755 /usr/local/bin/hq-caddy \
    && caddy list-modules --skip-standard | grep -qx 'dns.providers.cloudflare' \
    && caddy list-modules --skip-standard | grep -qx 'layer4' \
    && hq-caddy --version

ARG BUILD_INPUTS=""
RUN printf '%s\n' ${BUILD_INPUTS} > /etc/hq-caddy-build-inputs.txt

ENV XDG_DATA_HOME=/data XDG_CONFIG_HOME=/config
EXPOSE 80 443
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/hq-caddy"]
CMD ["run"]
