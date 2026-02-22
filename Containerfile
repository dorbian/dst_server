FROM debian:bookworm-slim

ARG STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
ARG DST_APPID="343050"

# DST server is 32-bit; install 32-bit libs + steamcmd deps
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl tar bash tini \
      libstdc++6 libgcc-s1 \
      libc6:i386 libstdc++6:i386 libgcc-s1:i386 \
      libcurl4:i386 \
      libssl3:i386 \
      libz1:i386 \
      libx11-6:i386 libxext6:i386 libxrandr2:i386 libxi6:i386 \
      libxrender1:i386 libgl1-mesa-glx:i386 \
 && rm -rf /var/lib/apt/lists/*

# Create a dedicated user
RUN useradd -m -u 1000 -s /bin/bash dst

# Paths
ENV DST_HOME=/opt/dst \
    STEAM_HOME=/steam \
    KLEI_ROOT=/data \
    STEAMCMD=/opt/steamcmd/steamcmd.sh

# Install steamcmd
RUN mkdir -p /opt/steamcmd \
 && curl -fsSL "$STEAMCMD_URL" | tar -xz -C /opt/steamcmd

# Install DST Dedicated Server at build time
RUN mkdir -p ${DST_HOME} \
 && ${STEAMCMD} +force_install_dir ${DST_HOME} \
              +login anonymous \
              +app_update ${DST_APPID} validate \
              +quit

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
 && chown -R dst:dst ${DST_HOME}

# Runtime volumes: persistent cluster + persistent steam/workshop cache
VOLUME ["/data", "/steam"]

# Default ports (you’ll still map host ports)
EXPOSE 10999/udp 11000/udp 12346/udp 12347/udp

USER dst
WORKDIR /opt/dst/bin

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
