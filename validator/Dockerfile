FROM eclipse-temurin:25

ENV VALIDATOR_VERSION=latest

WORKDIR /src

ADD "https://github.com/validator/validator/releases/download/$VALIDATOR_VERSION/vnu.jar" /src/vnu.jar

EXPOSE 8888
RUN adduser -S validator
USER validator
WORKDIR /home/validator
ENTRYPOINT ["java", "-jar", "/src/vnu.jar" ]
CMD ["--help"]
