# ATX Container Test Runner
# Base image: Ubuntu 22.04 LTS
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set working directory
WORKDIR /workspace

# Create non-root user for security
RUN groupadd -r atxuser && \
    useradd -r -g atxuser -m -s /bin/bash atxuser && \
    chown -R atxuser:atxuser /workspace

# Install system dependencies including Node.js
RUN apt-get update && \
    apt-get install -y \
    curl \
    git \
    python3 \
    python3-pip \
    unzip \
    build-essential \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20.x (required by ATX CLI)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs

# Install ATX CLI (AWS Transform CLI)
# Download and install the real ATX CLI from AWS
RUN curl -fsSL https://desktop-release.transform.us-east-1.api.aws/install.sh | bash

# Make ATX accessible to all users and verify installation
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> /root/.bashrc && \
    export PATH="$HOME/.local/bin:$PATH" && \
    cp /root/.local/bin/atx /usr/local/bin/atx && \
    chmod +x /usr/local/bin/atx && \
    echo 'export PATH="/usr/local/bin:$PATH"' >> /home/atxuser/.bashrc && \
    chown atxuser:atxuser /home/atxuser/.bashrc

# Verify ATX installation (skip version check since it requires AWS credentials)
# ATX CLI is installed and will be verified during runtime when AWS credentials are available
RUN echo "ATX CLI installed successfully and accessible to all users"

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip

# Configure AWS CLI defaults
RUN aws --version

# Copy scripts into image
COPY scripts/s3-integration.sh /usr/local/bin/s3-integration.sh
COPY scripts/atx-orchestrator.sh /usr/local/bin/atx-orchestrator.sh
COPY scripts/smoke-test.sh /usr/local/bin/smoke-test.sh
COPY scripts/csv-parser.sh /usr/local/bin/csv-parser.sh
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/test-orchestrator.sh /usr/local/bin/test-orchestrator.sh

# Set executable permissions
RUN chmod +x /usr/local/bin/s3-integration.sh && \
    chmod +x /usr/local/bin/atx-orchestrator.sh && \
    chmod +x /usr/local/bin/smoke-test.sh && \
    chmod +x /usr/local/bin/csv-parser.sh && \
    chmod +x /usr/local/bin/entrypoint.sh && \
    chmod +x /usr/local/bin/test-orchestrator.sh

# Switch to non-root user
USER atxuser

# Set entrypoint and default command
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["--help"]
