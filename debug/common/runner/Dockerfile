FROM debian:trixie

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build pkg-config \
    libjavascriptcoregtk-4.1-dev \
    libgl1-mesa-dev libglu1-mesa-dev \
    libx11-dev libxcursor-dev libxi-dev \
    python3 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . /src
RUN rm -rf /src/build /src/build-asan && cmake -S /src -B /src/build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo && cmake --build /src/build -j