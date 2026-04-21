# opencode-bedrock

A Docker image for running [OpenCode](https://opencode.ai) with [Amazon Bedrock](https://aws.amazon.com/bedrock/) inside a [Docker Sandbox](https://docs.docker.com/sandbox/) (`sbx`).

```
docker.io/thath/opencode-bedrock
```

## What this is

`docker/sandbox-templates:opencode` — the official base image used by `sbx` — does not include the AWS CLI or any AWS credential handling. This image adds:

- **AWS CLI v2** (multi-arch: `linux/amd64` and `linux/arm64`)
- **An entrypoint** that bridges a known `sbx` quirk: `sbx` mounts host directories at their original host path (e.g. `/Users/alice/.aws`) rather than at the container user's `$HOME` (`/home/agent`). The entrypoint detects those mounts and symlinks them into `$HOME` before OpenCode starts.

Everything else — OpenCode itself, Node.js, git — comes from the upstream `docker/sandbox-templates:opencode` base image.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (for building)
- [`sbx`](https://docs.docker.com/sandbox/) — Docker Sandboxes CLI
- An [AWS account](https://aws.amazon.com/) with [Amazon Bedrock model access](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html) enabled
- AWS credentials configured locally (SSO, IAM user, or any standard method)

## Quick start

### 1. Configure OpenCode for Bedrock

Create `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "amazon-bedrock": {
      "options": {
        "region": "us-east-1",
        "profile": "your-aws-profile"
      }
    }
  },
  "model": "amazon-bedrock/us.anthropic.claude-sonnet-4-6"
}
```

Replace `your-aws-profile` with the profile name from your `~/.aws/config`, and set `region` to the AWS region where you have Bedrock access.

See the [OpenCode provider docs](https://opencode.ai/docs/providers#amazon-bedrock) for all available Bedrock configuration options.

### 2. Run in a sandbox

```bash
cd ~/my-project
sbx run --template thath/opencode-bedrock opencode . ~/.aws:ro ~/.config/opencode:ro
```

`sbx` pulls the image from Docker Hub on first use. On subsequent runs for the same project, omit `--template` to reuse the existing sandbox:

```bash
sbx run opencode-my-project
```

## How credentials work

`sbx` mounts host directories at their literal host path inside the sandbox VM. For example, `~/.aws` on a Mac becomes `/Users/alice/.aws` inside the container — not `/home/agent/.aws`.

The entrypoint (`entrypoint.sh`) resolves this automatically:

1. It parses `/proc/mounts` for `virtiofs` entries (the filesystem type used by `sbx`) to find where `~/.aws` and `~/.config/opencode` were mounted.
2. It creates symlinks from `/home/agent/.aws` and `/home/agent/.config/opencode` to those mount points.
3. It then hands off to `opencode`.

This means you do not need to set `AWS_CONFIG_FILE` or any other environment variable — standard AWS credential resolution just works.

### Supported credential types

Any credential type supported by the AWS SDK credential chain works:

| Method | How to use |
|--------|-----------|
| AWS SSO | Configure a named profile in `~/.aws/config`, mount `~/.aws:ro` |
| IAM user access keys | `~/.aws/credentials` file, mount `~/.aws:ro` |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Not directly injectable via `sbx run`, but can be placed in `~/.aws/credentials` |
| ECS task role / EC2 instance profile | No mount needed; SDK resolves via instance metadata |

## Managing sandboxes

```bash
# List all sandboxes
sbx ls

# Stop a sandbox without removing it
sbx stop opencode-my-project

# Remove a sandbox
sbx rm opencode-my-project
```

## Building the image yourself

```bash
# Build locally (current architecture only)
./build.sh

# Build multi-arch and push to Docker Hub
./build.sh --push

# Build multi-arch, push, and also tag a specific version
./build.sh --push --tag 1.2.3
```

`--push` requires that you are logged in to Docker Hub (`docker login`) and that you update the `IMAGE` variable in `build.sh` to point to your own repository.

## Automated releases via GitHub Actions

The included `.github/workflows/release.yml` workflow builds and pushes a multi-arch image automatically:

- **On a git tag** (`v*`): pushes `latest` and a version tag derived from the tag name (e.g. `git tag v1.2.3` → `1.2.3` and `latest`).
- **On manual trigger** (`workflow_dispatch`): pushes `latest` and an optional additional tag.

### Setup

Add the following secrets to your GitHub repository (**Settings → Secrets and variables → Actions**):

| Secret | Value |
|--------|-------|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | A Docker Hub [access token](https://hub.docker.com/settings/security) with `Read & Write` scope |

Then update the `IMAGE` variable at the top of `.github/workflows/release.yml` to match your Docker Hub repository.

### Releasing a new version

```bash
git tag v1.2.3
git push origin v1.2.3
```

The workflow pushes `thath/opencode-bedrock:1.2.3` and `thath/opencode-bedrock:latest`.

## Repository structure

```
.
├── Dockerfile             # Extends docker/sandbox-templates:opencode with AWS CLI
├── entrypoint.sh          # Symlinks host-mounted dirs into $HOME at startup
├── build.sh               # Local build and Docker Hub push script
├── .dockerignore          # Keeps build context minimal
└── .github/
    └── workflows/
        └── release.yml    # Automated multi-arch build and push on git tags
```

## Related

- [opencode.ai](https://opencode.ai) — OpenCode documentation
- [opencode.ai/docs/providers#amazon-bedrock](https://opencode.ai/docs/providers#amazon-bedrock) — Bedrock provider configuration
- [docker/sandbox-templates](https://hub.docker.com/r/docker/sandbox-templates) — upstream base images
- [Docker Sandbox docs](https://docs.docker.com/sandbox/) — `sbx` CLI documentation
