FROM eclipse-temurin:21-jre-jammy

RUN apt-get update && apt-get install -y --no-install-recommends \
	ca-certificates \
	curl \
	xvfb \
	libxrender1 \
	libxtst6 \
	libxi6 \
	libxext6 \
	libxrandr2 \
	libxfixes3 \
	libxinerama1 \
	libxcursor1 \
	libfontconfig1 \
	libfreetype6 \
	fonts-dejavu-core \
	&& rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/burp/projects /opt/burp/reports

RUN curl -fsSL "https://portswigger.net/burp/releases/startdownload?product=community&type=Jar" \
	-o /opt/burp/burpsuite_community.jar

CMD ["sh", "-c", "xvfb-run -a java -jar /opt/burp/burpsuite_community.jar"]
