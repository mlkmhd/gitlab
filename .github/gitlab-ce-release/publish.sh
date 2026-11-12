#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_REF_NAME:?A release tag is required}"
: "${GITHUB_RUN_ID:?Run this script in the GitHub Actions release job}"
: "${GHCR_USERNAME:?GitHub Actions must supply the registry username}"
: "${GHCR_TOKEN:?GitHub Actions must supply the registry token}"

if [[ ${GITHUB_REF_TYPE:-} != tag ||
      ! $GITHUB_REF_NAME =~ ^fork-v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]]; then
  echo 'Publication requires a fork-vMAJOR.MINOR.PATCH Git tag.' >&2
  exit 1
fi

if [[ $(uname -s) != Linux || $(uname -m) != x86_64 ]]; then
  echo 'Use a Linux amd64 runner with a local Docker engine.' >&2
  exit 1
fi

version=${GITHUB_REF_NAME#fork-v}
if (( ${#version} > 128 )); then
  echo 'The Docker tag must be at most 128 characters.' >&2
  exit 1
fi

# Keep the builder and Docker packaging files paired with this Omnibus revision.
omnibus_ref=9469cb7c820814fad12974d01cb3474962050b68
builder_image=registry.gitlab.com/gitlab-org/gitlab-omnibus-builder/ubuntu_24.04:5.73.0
image="ghcr.io/mlkmhd/gitlab:$version"

workdir=$(mktemp -d)
trap 'rm -rf -- "$workdir"' EXIT
source_repo="$workdir/source.git"
omnibus="$workdir/omnibus"
context="$workdir/image"

revision_sha=$(git rev-parse HEAD)

# Pass only the tagged source, without the checkout's remote configuration.
git init --bare --initial-branch=build "$source_repo"
git --git-dir="$source_repo" fetch --depth=1 "$PWD" "$revision_sha:refs/heads/build"

git clone --no-checkout https://github.com/gitlabhq/omnibus-gitlab.git "$omnibus"
git -C "$omnibus" checkout --detach "$omnibus_ref"

mkdir "$context"
docker run --rm --platform linux/amd64 --user 0 --entrypoint bash \
  --mount "type=bind,src=$source_repo,dst=/source.git,readonly" \
  --mount "type=bind,src=$omnibus,dst=/omnibus-source,readonly" \
  --mount "type=bind,src=$context,dst=/output" \
  --env CI_PIPELINE_ID="$GITHUB_RUN_ID" --env GITLAB_VERSION="$revision_sha" \
  --env GITLAB_ALTERNATIVE_REPO=file:///source.git \
  --env ALTERNATIVE_SOURCES=true --env COMPILE_ASSETS=true \
  --env GIT_CONFIG_COUNT=1 \
  --env GIT_CONFIG_KEY_0=safe.directory --env GIT_CONFIG_VALUE_0=/source.git \
  "$builder_image" -euo pipefail -c '
    cp -R /omnibus-source /omnibus-gitlab
    cd /omnibus-gitlab

    for component in GITLAB_SHELL_VERSION GITLAB_PAGES_VERSION GITALY_SERVER_VERSION GITLAB_KAS_VERSION; do
      value=$(git --git-dir=/source.git show "HEAD:$component")
      export "$component=$value"
    done

    bundle install -j "$(nproc)"
    bundle binstubs --all

    RUBY_VERSION=$(git --git-dir=/source.git show HEAD:.ruby-version)
    export RUBY_VERSION USE_SPECIFIED_RUBY_VERSION=true
    bundle exec rake build:project

    shopt -s nullglob
    packages=(pkg/ubuntu-noble/gitlab-ce_*_amd64.deb)
    if (( ${#packages[@]} != 1 )); then
      echo "Expected one GitLab CE amd64 Debian package." >&2
      exit 1
    fi
    install -m 0644 "${packages[0]}" /output/gitlab.deb
  '

cp -a "$omnibus/docker/." "$context/"
printf 'RELEASE_PACKAGE=gitlab-ce\nRELEASE_VERSION=%s\n' "$version" > "$context/RELEASE"

# Mount the package during installation so it does not occupy an image layer.
sed -i 's|^RUN chmod -R og-w /assets RELEASE ;|RUN --mount=type=bind,source=gitlab.deb,target=/tmp/source.deb chmod -R og-w /assets RELEASE \&\&|' "$context/Dockerfile"
grep -q '^RUN --mount=type=bind,source=gitlab.deb,' "$context/Dockerfile"
cat > "$context/assets/download-package" <<'DOWNLOADER'
#!/bin/sh
exec cp /tmp/source.deb /tmp/gitlab.deb
DOWNLOADER
chmod +x "$context/assets/download-package"

DOCKER_BUILDKIT=1 docker build --pull --platform linux/amd64 \
  --label org.opencontainers.image.source=https://github.com/mlkmhd/gitlab \
  --label "org.opencontainers.image.revision=$revision_sha" \
  --label "org.opencontainers.image.version=$version" \
  --iidfile "$workdir/image-id" "$context"

image_id=$(cat "$workdir/image-id")
revision=$(docker run --rm --platform linux/amd64 --entrypoint cat "$image_id" \
  /opt/gitlab/embedded/service/gitlab-rails/REVISION)
if [[ ! $revision =~ ^[0-9a-f]{11,40}$ || $revision_sha != "$revision"* ]]; then
  echo "The installed GitLab revision ($revision) does not match $revision_sha." >&2
  exit 1
fi

mkdir "$workdir/docker-config"
printf '{"auths":{"ghcr.io":{}}}\n' > "$workdir/docker-config/config.json"
printf '%s' "$GHCR_TOKEN" | docker --config "$workdir/docker-config" login ghcr.io \
  --username "$GHCR_USERNAME" --password-stdin
docker tag "$image_id" "$image"
docker --config "$workdir/docker-config" push "$image"
