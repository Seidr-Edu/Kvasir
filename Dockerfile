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

RUN groupadd --gid 10001 kvasir \
  && useradd --uid 10001 --gid 10001 --create-home --shell /usr/sbin/nologin kvasir \
  && mkdir -p /run \
  && chown -R kvasir:kvasir /run

WORKDIR /app

COPY . .

RUN chmod +x ./test-port-run.sh ./kvasir-run.sh ./kvasir-service.sh ./tests/run.sh \
  && chown -R kvasir:kvasir /app

USER kvasir

ENV HOME=/home/kvasir

ENTRYPOINT ["./kvasir-service.sh"]
