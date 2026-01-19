# ============================================================================
# VTCS Cyber Range - Student Workspace Container
# ============================================================================
# Base image for Red and Blue team workspaces.
# Includes common security tools for both offensive and defensive work.
# ============================================================================

FROM ubuntu:24.04

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install base packages
RUN apt-get update && apt-get install -y \
    # Core utilities
    sudo \
    openssh-server \
    curl \
    wget \
    git \
    vim \
    nano \
    tmux \
    htop \
    net-tools \
    iputils-ping \
    dnsutils \
    tcpdump \
    netcat-openbsd \
    # Python for scripting
    python3 \
    python3-pip \
    python3-venv \
    # Network tools
    nmap \
    nikto \
    hydra \
    sqlmap \
    # Analysis tools
    wireshark-common \
    tshark \
    # Development
    build-essential \
    # Cleanup
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create student user with sudo access
RUN useradd -m -s /bin/bash -G sudo student \
    && echo "student:student" | chpasswd \
    && echo "student ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Configure SSH
RUN mkdir -p /var/run/sshd \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Create workspace directories
RUN mkdir -p /home/student/{tools,scripts,notes,evidence} \
    && chown -R student:student /home/student

# Add welcome message
COPY motd.sh /etc/profile.d/motd.sh
RUN chmod +x /etc/profile.d/motd.sh

# Add helpful aliases
RUN echo 'alias ll="ls -la"' >> /home/student/.bashrc \
    && echo 'alias ports="netstat -tulpn"' >> /home/student/.bashrc \
    && echo 'export PS1="\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ "' >> /home/student/.bashrc

# Set working directory
WORKDIR /home/student

# Expose SSH port
EXPOSE 22

# Start SSH daemon
CMD ["/usr/sbin/sshd", "-D"]
