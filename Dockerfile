FROM debian:trixie AS build

ENV HUGO_VERSION=0.152.2

WORKDIR /tmp
RUN apt-get update && apt-get install -y wget && \
    wget https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz -O /tmp/hugo.tar.gz && \
    tar xf /tmp/hugo.tar.gz && \
    mv /tmp/hugo /usr/local/bin && \
    rm /tmp/hugo.tar.gz && \
    apt-get purge -y wget && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY dockerbuch.info/ /src/
RUN hugo

FROM nginxinc/nginx-unprivileged:1-alpine
COPY --from=build /src/public/ /usr/share/nginx/html/
VOLUME ["/usr/share/nginx/html/"]
