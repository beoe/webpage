FROM node:alpine

# Install chromium and jq
RUN apk add --no-cache chromium jq

# Install lighthouse globally
RUN npm install -g lighthouse

# Create a non-root user
RUN addgroup -S lighthouse && \
    adduser -S lighthouse -G lighthouse

USER lighthouse
WORKDIR /home/lighthouse

ENTRYPOINT ["lighthouse"]
CMD ["--help"]
