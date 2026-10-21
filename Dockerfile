# syntax=docker/dockerfile:1.7
#
# Canary server image for the homelab deployment.
#
# This intentionally builds from source instead of relying on the rolling
# upstream image, so engine changes are picked up through the fork's CI.

FROM ubuntu:24.04 AS build

ARG DEBIAN_FRONTEND=noninteractive
ENV DEBIAN_FRONTEND=${DEBIAN_FRONTEND}
ENV TZ=Etc/UTC

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        gcc-14 \
        g++-14 \
        git \
        libtool \
        ninja-build \
        pkg-config \
        python3 \
        tar \
        unzip \
        zip \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 100 \
        --slave /usr/bin/g++ g++ /usr/bin/g++-14 \
    && update-alternatives --set gcc /usr/bin/gcc-14 \
    && rm -rf /var/lib/apt/lists/*

ENV VCPKG_ROOT=/opt/vcpkg

COPY vcpkg.json /tmp/vcpkg.json
RUN git clone https://github.com/microsoft/vcpkg.git "${VCPKG_ROOT}" \
    && cd "${VCPKG_ROOT}" \
    && git checkout "$(sed -n 's/.*"builtin-baseline"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/vcpkg.json)" \
    && ./bootstrap-vcpkg.sh -disableMetrics

WORKDIR /src
COPY . .

RUN --mount=type=cache,target=/opt/vcpkg/downloads \
    cmake --preset linux-release -DTOGGLE_BIN_FOLDER=ON \
    && cmake --build --preset linux-release --target canary -j2

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG CANARY_MAP_URL=https://github.com/opentibiabr/canary/releases/download/v3.6.1/otservbr.otbm
ENV DEBIAN_FRONTEND=${DEBIAN_FRONTEND}
ENV TZ=Etc/UTC

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        mariadb-client \
        tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r canary \
    && useradd -r -g canary -d /canary -s /usr/sbin/nologin canary

COPY --from=build /src/build/linux-release/bin/canary /bin/canary
COPY LICENSE schema.sql key.pem /canary/
COPY config.lua.dist /canary/config.lua
COPY data /canary/data
COPY data-canary /canary/data-canary
COPY data-otservbr-global /canary/data-otservbr-global
COPY docker/data/01-test_account.sql /canary/01-test_account.sql
COPY docker/data/02-test_account_players.sql /canary/02-test_account_players.sql
COPY --chmod=755 docker/data/start.sh /canary/start.sh

RUN set -eux; \
    mkdir -p \
        /canary/data-otservbr-global/world \
        /canary/data/logs \
        /canary/data/reports \
        /canary/data/cache/maps \
        /data; \
    curl -fL --retry 5 --retry-delay 5 --connect-timeout 10 --max-time 900 \
        -o /canary/data-otservbr-global/world/otservbr.otbm \
        "${CANARY_MAP_URL}"; \
    test -s /canary/data-otservbr-global/world/otservbr.otbm; \
    sed -i 's/^ulimit -c unlimited$/ulimit -c unlimited || true/' /canary/start.sh; \
    chown -R canary:canary /canary /data /bin/canary

WORKDIR /canary
USER canary

EXPOSE 7171 7172 7173 7174 7175

ENTRYPOINT ["/canary/start.sh"]
