FROM docker/sandbox-templates:opencode

# Install AWS CLI
# The installer detects the architecture (aarch64 or x86_64) at build time,
# making this Dockerfile work for both linux/arm64 and linux/amd64.
USER root
RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends unzip curl \
    && ARCH=$(uname -m) \
    && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip \
    && apt-get purge -y --auto-remove unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# The entrypoint detects host-mounted ~/.aws and ~/.config/opencode directories
# and symlinks them into $HOME so they are found in the expected locations.
# This is necessary because sbx mounts directories at their original host path
# (e.g. /Users/alice/.aws) rather than at the container user's $HOME.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER agent

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["opencode"]
