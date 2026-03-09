FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    gradle \
    maven \
    openjdk-21-jdk-headless \
    python3 \
    ripgrep \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY . .

RUN chmod +x ./test-port-run.sh ./kvasir-run.sh ./tests/run.sh

ENTRYPOINT ["./test-port-run.sh"]
CMD ["--help"]
