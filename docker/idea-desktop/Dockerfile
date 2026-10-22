FROM docker.io/library/ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Runtime libraries required by the JetBrains Runtime (JBR) and the IDE UI.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      file \
      fontconfig \
      fonts-dejavu-core \
      fonts-liberation \
      git \
      libasound2 \
      libatk-bridge2.0-0 \
      libatk1.0-0 \
      libcairo2 \
      libcanberra-gtk3-module \
      libcups2 \
      libdbus-1-3 \
      libdrm2 \
      libegl1 \
      libfontconfig1 \
      libfreetype6 \
      libgbm1 \
      libgdk-pixbuf-2.0-0 \
      libgl1 \
      libglib2.0-0 \
      libgtk-3-0 \
      libnss3 \
      libpango-1.0-0 \
      libsm6 \
      libstdc++6 \
      libx11-6 \
      libxcb-icccm4 \
      libxcb-image0 \
      libxcb-keysyms1 \
      libxcb-randr0 \
      libxcb-render-util0 \
      libxcb-render0 \
      libxcb-shape0 \
      libxcb-sync1 \
      libxcb-util1 \
      libxcb-xfixes0 \
      libxcb-xinerama0 \
      libxcb-xkb1 \
      libxcb1 \
      libxcomposite1 \
      libxdamage1 \
      libxext6 \
      libxfixes3 \
      libxi6 \
      libxkbcommon-x11-0 \
      libxkbcommon0 \
      libxrandr2 \
      libxrender1 \
      libxt6 \
      libxtst6 \
      openssh-client \
      procps \
      socat \
      xauth \
      xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 1000 --shell /bin/bash developer \
    && mkdir -p /home/developer/.config/JetBrains \
                /home/developer/.cache/JetBrains \
                /home/developer/.local/share/JetBrains \
                /home/developer/.run \
    && chown -R developer:developer /home/developer \
    && chmod 700 /home/developer/.run

USER developer
WORKDIR /home/developer
ENV HOME=/home/developer

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
USER root
RUN chmod 755 /usr/local/bin/entrypoint.sh \
    && touch /.dockerenv
USER developer

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/opt/idea/bin/idea.sh"]
