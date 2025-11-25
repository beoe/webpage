FROM eclipse-temurin:25

ENV VALIDATOR_VERSION=latest

WORKDIR /src

RUN apt-get update \
 && apt-get install -y --no-install-recommends wget \
 && rm -rf /var/lib/apt/lists/*

RUN groupadd --system validator \
 && useradd --system --gid validator --home-dir /home/validator --shell /sbin/nologin validator

RUN wget -O /src/vnu.jar "https://github.com/validator/validator/releases/download/$VALIDATOR_VERSION/vnu.jar" \
 && chown validator:validator /src/vnu.jar

EXPOSE 8888
USER validator
WORKDIR /home/validator
ENTRYPOINT ["java", "-jar", "/src/vnu.jar" ]
CMD ["--help"]
