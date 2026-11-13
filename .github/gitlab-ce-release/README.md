# Publish the GitLab CE fork to GHCR

[Publish GitLab CE to GHCR](https://github.com/mlkmhd/gitlab/actions/workflows/gitlab-ce-release.yml) builds the tagged commit and frontend assets with Omnibus on Ubuntu 24.04. It installs the CE package with upstream Docker packaging, verifies the installed source revision, and publishes a Linux amd64 image.

## Runner and package access

GitHub Actions assigns a standard `ubuntu-24.04` runner by default. For builds that exceed its storage or compute capacity, set the optional `OMNIBUS_RUNNER` repository variable to the label of a larger Linux x64 runner with Docker and BuildKit. [GitHub runner specifications](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

If the GHCR package already exists with independent permissions, give this repository write access under the package's **Manage Actions access** settings. The workflow authenticates using GitHub's automatic `GITHUB_TOKEN`. [GitHub Packages access control](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility).

## Publish a version

Push a fresh release tag from the commit you want to build. The example uses the `github` remote.

```sh
git tag -a fork-v19.5.6 -m 'Release 19.5.6'
git push github refs/tags/fork-v19.5.6
```

After the workflow succeeds, pull the matching image. Authenticate to GHCR if the package is private.

```sh
docker pull ghcr.io/mlkmhd/gitlab:19.5.6
```

The tag sets the image version. GitLab's internal version comes from the tagged commit's `VERSION` file. When moving to a different GitLab release line, verify that the pinned Omnibus revision and builder image in `publish.sh` support its source and Ruby version.

Use the [GitLab Docker installation guide](https://docs.gitlab.com/install/docker/installation/) to configure the volumes and run the image.
