# Build xrdp pulseaudio modules in builder container
# See https://github.com/neutrinolabs/pulseaudio-module-xrdp/wiki/README
ARG TAG=noble
FROM ubuntu:$TAG AS builder

RUN apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -y --no-install-recommends \
        autoconf \
        build-essential \
        ca-certificates \
        dpkg-dev \
        libpulse-dev \
        lsb-release \
        git \
        libtool \
        libltdl-dev \
        sudo && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/neutrinolabs/pulseaudio-module-xrdp.git /pulseaudio-module-xrdp
WORKDIR /pulseaudio-module-xrdp
RUN scripts/install_pulseaudio_sources_apt.sh && \
    ./bootstrap && \
    ./configure PULSE_DIR=$HOME/pulseaudio.src && \
    make && \
    make install DESTDIR=/tmp/install


# Build the final image
FROM ubuntu:$TAG

RUN apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -y --no-install-recommends \
        dbus-x11 \
        fonts-noto-cjk \
        fonts-wqy-microhei \
        fonts-wqy-zenhei \
        git \
        ibus \
        ibus-gtk \
        ibus-gtk3 \
        ibus-libpinyin \
        libglib2.0-bin \
        locales \
        pavucontrol \
        pulseaudio \
        pulseaudio-utils \
        software-properties-common \
        sudo \
        vim \
        x11-xserver-utils \
        xfce4 \
        xfce4-goodies \
        xfce4-pulseaudio-plugin \
        xfonts-wqy \
        xorgxrdp \
        xrdp \
        xubuntu-icon-theme && \
    add-apt-repository -y ppa:mozillateam/ppa && \
    echo "Package: *"  > /etc/apt/preferences.d/mozilla-firefox && \
    echo "Pin: release o=LP-PPA-mozillateam" >> /etc/apt/preferences.d/mozilla-firefox && \
    echo "Pin-Priority: 1001" >> /etc/apt/preferences.d/mozilla-firefox && \
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -y --no-install-recommends firefox && \
    rm -rf /var/lib/apt/lists/* && \
    deluser --remove-home ubuntu && \
    locale-gen en_US.UTF-8 zh_CN.UTF-8 && \
    update-locale LANG=en_US.UTF-8

COPY --from=builder /tmp/install /
RUN sed -i 's|^Exec=.*|Exec=/usr/bin/pulseaudio|' /etc/xdg/autostart/pulseaudio-xrdp.desktop

# Refresh the fontconfig cache so the CJK fonts are usable right away
RUN fc-cache -f

# Enable the US keyboard layout plus the intelligent pinyin engine in IBus
RUN printf '%s\n' \
        '[org.freedesktop.ibus.general]' \
        "preload-engines=['xkb:us::eng', 'libpinyin']" \
        > /usr/share/glib-2.0/schemas/99-ibus-cn.gschema.override && \
    glib-compile-schemas /usr/share/glib-2.0/schemas

# Start the IBus daemon inside every desktop session so Chinese can be typed
RUN printf '%s\n' \
        '[Desktop Entry]' \
        'Type=Application' \
        'Name=IBus' \
        'Comment=Start the IBus input method daemon' \
        'Exec=ibus-daemon --daemonize --replace --xim' \
        'Terminal=false' \
        'NoDisplay=true' \
        > /etc/xdg/autostart/ibus-daemon.desktop

# English desktop, but Chinese text still renders (CJK fonts + UTF-8) and can be
# typed with IBus. LC_CTYPE=zh_CN.UTF-8 only affects character/width handling, the
# interface language comes from LC_MESSAGES (LANG), which stays English.
ENV LANG=en_US.UTF-8 \
    LC_CTYPE=zh_CN.UTF-8 \
    GTK_IM_MODULE=ibus \
    QT_IM_MODULE=ibus \
    XMODIFIERS=@im=ibus

COPY entrypoint.sh /usr/bin/entrypoint
EXPOSE 3389/tcp
ENTRYPOINT ["/usr/bin/entrypoint"]
