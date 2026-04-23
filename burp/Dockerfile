FROM dorowu/ubuntu-desktop-lxde-vnc:focal
RUN rm -f /etc/apt/sources.list.d/google-chrome.list \
    /etc/apt/sources.list.d/google.list \
    /etc/apt/sources.list.d/chrome.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openjdk-17-jre curl wget ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /opt/burp /workspace/reports && curl -fsSL "https://portswigger.net/burp/releases/startdownload?product=community&type=Jar" -o /opt/burp/burpsuite_community.jar
RUN mkdir -p /root/.config/autostart && printf "[Desktop Entry]\nType=Application\nName=Burp Suite\nExec=java -jar /opt/burp/burpsuite_community.jar\nTerminal=false\n" > /root/.config/autostart/burp.desktop
