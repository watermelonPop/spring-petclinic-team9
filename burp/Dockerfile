FROM dorowu/ubuntu-desktop-lxde-vnc:focal

USER root

RUN rm -f /etc/apt/sources.list.d/google-chrome.list \
    /etc/apt/sources.list.d/google.list \
    /etc/apt/sources.list.d/chrome.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        openjdk-17-jre \
        wget \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG BURP_URL="https://portswigger-cdn.net/burp/releases/download?product=community&type=Jar"

RUN mkdir -p /opt/burp /burp/reports \
    && wget -O /opt/burp/burpsuite_community.jar "${BURP_URL}"

COPY start-burp.sh /usr/local/bin/start-burp.sh
RUN chmod +x /usr/local/bin/start-burp.sh

ENV BURP_PROJECT_FILE=/burp/burp-project.burp

CMD ["/usr/local/bin/start-burp.sh"]
