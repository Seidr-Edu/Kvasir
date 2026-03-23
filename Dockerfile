FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ARG TEMURIN_JDK8_RELEASE=jdk8u482-b08
ARG TEMURIN_JDK8_VERSION=8u482b08
ARG TEMURIN_JDK8_X64_SHA256=e74becad56b4cc01f1556a671e578d3788789f5257f9499f6fbed84e63a55ecf
ARG TEMURIN_JDK8_AARCH64_SHA256=ada72fbf191fb287b4c1e54be372b64c40c27c2ffbfa01f880c92af11f4e7c94
ARG TEMURIN_JDK25_RELEASE=jdk-25.0.2%2B10
ARG TEMURIN_JDK25_VERSION=25.0.2_10
ARG TEMURIN_JDK25_X64_SHA256=987387933b64b9833846dee373b640440d3e1fd48a04804ec01a6dbf718e8ab8
ARG TEMURIN_JDK25_AARCH64_SHA256=a9d73e711d967dc44896d4f430f73a68fd33590dabc29a7f2fb9f593425b854c
ARG TARGETARCH

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    gradle \
    maven \
    openjdk-11-jdk \
    openjdk-17-jdk \
    openjdk-21-jdk \
    python3 \
    rsync \
    ripgrep \
    tar \
  && rm -rf /var/lib/apt/lists/*

RUN case "${TARGETARCH:-amd64}" in \
      amd64) \
        temurin_arch="x64"; \
        jdk8_sha256="${TEMURIN_JDK8_X64_SHA256}"; \
        jdk25_sha256="${TEMURIN_JDK25_X64_SHA256}"; \
        ;; \
      arm64) \
        temurin_arch="aarch64"; \
        jdk8_sha256="${TEMURIN_JDK8_AARCH64_SHA256}"; \
        jdk25_sha256="${TEMURIN_JDK25_AARCH64_SHA256}"; \
        ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH:-unknown}" >&2; exit 1 ;; \
    esac \
  && mkdir -p /opt/java/jdk8 /opt/java/jdk25 \
  && curl -fsSL -o /tmp/jdk8.tar.gz \
    "https://github.com/adoptium/temurin8-binaries/releases/download/${TEMURIN_JDK8_RELEASE}/OpenJDK8U-jdk_${temurin_arch}_linux_hotspot_${TEMURIN_JDK8_VERSION}.tar.gz" \
  && echo "${jdk8_sha256}  /tmp/jdk8.tar.gz" | sha256sum -c - \
  && tar -xzf /tmp/jdk8.tar.gz -C /opt/java/jdk8 --strip-components=1 \
  && /opt/java/jdk8/bin/java -version >/dev/null 2>&1 \
  && curl -fsSL -o /tmp/jdk25.tar.gz \
    "https://github.com/adoptium/temurin25-binaries/releases/download/${TEMURIN_JDK25_RELEASE}/OpenJDK25U-jdk_${temurin_arch}_linux_hotspot_${TEMURIN_JDK25_VERSION}.tar.gz" \
  && echo "${jdk25_sha256}  /tmp/jdk25.tar.gz" | sha256sum -c - \
  && tar -xzf /tmp/jdk25.tar.gz -C /opt/java/jdk25 --strip-components=1 \
  && /opt/java/jdk25/bin/java -version >/dev/null 2>&1 \
  && rm -f /tmp/jdk8.tar.gz /tmp/jdk25.tar.gz

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
