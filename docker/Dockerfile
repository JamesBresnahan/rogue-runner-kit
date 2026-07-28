FROM node:22-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates curl jq \
    && rm -rf /var/lib/apt/lists/*

RUN ARCH="$(dpkg --print-architecture)" \
    && GH_VERSION="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | grep -m1 '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')" \
    && curl -fsSL -o /tmp/gh.tar.gz "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" \
    && tar -xzf /tmp/gh.tar.gz -C /tmp \
    && mv "/tmp/gh_${GH_VERSION}_linux_${ARCH}/bin/gh" /usr/local/bin/gh \
    && rm -rf /tmp/gh*

# uv (provides uvx) — needed to run the garmin MCP server (Taxuspt/garmin_mcp)
# and the garmin-mcp-auth login command.
ENV UV_INSTALL_DIR=/usr/local/bin
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

RUN npm install -g @anthropic-ai/claude-code

RUN useradd --create-home --shell /bin/bash agent
USER agent
ENV HOME=/home/agent
WORKDIR /workspace

COPY --chown=agent:agent entrypoint.sh /entrypoint.sh
USER root
RUN chmod +x /entrypoint.sh
USER agent

ENTRYPOINT ["/entrypoint.sh"]
CMD ["claude", "--chrome"]
