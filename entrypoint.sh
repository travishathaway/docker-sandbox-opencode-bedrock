#!/bin/bash
set -e

# sbx (Docker Sandboxes) mounts host directories at their original host path
# inside the sandbox VM — e.g. /Users/alice/.aws — rather than at the
# container user's $HOME (/home/agent). This means the AWS CLI and OpenCode
# cannot find credentials or config in the expected locations.
#
# This entrypoint detects those mounts and symlinks them into $HOME before
# handing off to the agent command.
#
# Detection strategies (tried in order):
#   1. Parse /proc/mounts for virtiofs entries  — works in sbx sandboxes
#   2. Filesystem scan fallback                 — works with plain Docker volumes

AGENT_HOME="/home/agent"
AWS_MOUNT=""
OPENCODE_CONFIG_MOUNT=""

# Strategy 1: virtiofs mounts (sbx sandbox environment)
if grep -q virtiofs /proc/mounts 2>/dev/null; then
    while read -r _ mountpoint _ _; do
        case "$mountpoint" in
            */.aws)             AWS_MOUNT="$mountpoint" ;;
            */.config/opencode) OPENCODE_CONFIG_MOUNT="$mountpoint" ;;
        esac
    done < <(grep virtiofs /proc/mounts)
fi

# Strategy 2: filesystem scan (plain Docker volume mounts / CI)
if [[ -z "$AWS_MOUNT" ]]; then
    AWS_MOUNT=$(find / -maxdepth 4 -mindepth 3 -name ".aws" -type d \
        ! -path "${AGENT_HOME}/*" 2>/dev/null | head -1)
fi

if [[ -z "$OPENCODE_CONFIG_MOUNT" ]]; then
    OPENCODE_CONFIG_MOUNT=$(find / -maxdepth 5 -mindepth 4 -type d \
        -name "opencode" -path "*/.config/opencode" \
        ! -path "${AGENT_HOME}/*" 2>/dev/null | head -1)
fi

# Symlink ~/.aws
if [[ -n "$AWS_MOUNT" ]]; then
    rm -rf "${AGENT_HOME}/.aws"
    ln -s "$AWS_MOUNT" "${AGENT_HOME}/.aws"
fi

# Symlink ~/.config/opencode
if [[ -n "$OPENCODE_CONFIG_MOUNT" ]]; then
    rm -rf "${AGENT_HOME}/.config/opencode"
    mkdir -p "${AGENT_HOME}/.config"
    ln -s "$OPENCODE_CONFIG_MOUNT" "${AGENT_HOME}/.config/opencode"
fi

exec "$@"
