FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

# Chromium is the reference browser. The Flutter SDK is mounted from the host
# at the same absolute path, so it does not inflate this image.
RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium ca-certificates curl git unzip xz-utils \
    libgtk-3-0t64 libglu1-mesa libfontconfig1 libnss3 libasound2t64 \
    libxkbcommon0 libpango-1.0-0 libcairo2 libgdk-pixbuf-2.0-0 \
    libdbus-1-3 libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 \
    libdrm2 libxcomposite1 libxdamage1 libxrandr2 libgbm1 \
    fonts-noto-core fonts-dejavu-core \
    cmake ninja-build clang pkg-config libc++-dev libc++abi-dev \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /home/k3vin

ENV HOME=/tmp
ENV PUB_CACHE=/home/k3vin/.pub-cache
ENV NATIVAX_PERF_NO_SANDBOX=1
ENV FLUTTER_SUPPRESS_ANALYTICS=true
ENV CI=true

WORKDIR /home/k3vin/Documents/nativax
