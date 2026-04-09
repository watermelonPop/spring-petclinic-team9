FROM jenkins/jenkins:lts-jdk21

USER root

RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    python3 \
    python3-pip \
    sshpass \
    openssh-client \
    ca-certificates \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y ansible && rm -rf /var/lib/apt/lists/*

RUN rm -f /usr/share/keyrings/docker.gpg && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y docker-ce-cli && \
    # Ensure the docker group exists with a specific GID (999 is standard for Docker)
    groupadd -f -g 999 docker && \
    usermod -aG docker jenkins && \
    rm -rf /var/lib/apt/lists/*

USER jenkins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt