FROM debian:stretch-slim

ENV DEBIAN_FRONTEND=noninteractive

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV LANGUAGE=C.UTF-8

# Stretch is EOL -> use archive.debian.org
RUN sed -i 's|deb.debian.org/debian|archive.debian.org/debian|g' /etc/apt/sources.list && \
    sed -i 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' /etc/apt/sources.list && \
    sed -i '/stretch-updates/d' /etc/apt/sources.list 

#RUN printf 'Acquire::Check-Valid-Until "false";\nAcquire::AllowInsecureRepositories "true";\n' > /etc/apt/apt.conf.d/99no-check-valid-until

RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https vim ca-certificates curl git unzip \
    gcc build-essential \
    python2.7 python-pip python-setuptools \
    python-dev \
    libxml2-dev libxslt1-dev \
    libldap2-dev libsasl2-dev \
    libssl-dev \
    libjpeg-dev zlib1g-dev \
    libpq-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# PostgreSQL client from official archive repo (Stretch EOL)
RUN install -d /usr/share/postgresql-common/pgdg && \
        curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
            https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
        echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt-archive.postgresql.org/pub/repos/apt stretch-pgdg main" \
            > /etc/apt/sources.list.d/pgdg.list && \
        apt-get update && apt-get install -y --no-install-recommends postgresql-client && \
        apt-get clean && rm -rf /var/lib/apt/lists/*

## wkhtmltopdf
RUN apt-get update && apt-get install -y --no-install-recommends \
    fontconfig libfreetype6 libpng16-16 \
    libx11-6 libxcb1 libxext6 libxrender1 \
    xfonts-base xfonts-75dpi gsfonts \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN set -eux; \
    cd /tmp; \
    curl -fsSL \
      https://github.com/wkhtmltopdf/packaging/releases/download/0.12.1.4-2/wkhtmltox_0.12.1.4-2.stretch_amd64.deb \
      -o wkhtml.deb; \
    dpkg -i wkhtml.deb; \
    rm -f wkhtml.deb

ENV PYTHONIOENCODING=UTF-8

# ---- Node.js 6.x (official binary) for Odoo 10 ----
ENV NODE_VERSION=6.17.1
RUN set -eux; \
    cd /tmp; \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" -o node.tar.xz; \
    tar -xJf node.tar.xz; \
    cp -r node-v${NODE_VERSION}-linux-x64/bin /usr/local/; \
    cp -r node-v${NODE_VERSION}-linux-x64/lib /usr/local/; \
    cp -r node-v${NODE_VERSION}-linux-x64/include /usr/local/; \
    cp -r node-v${NODE_VERSION}-linux-x64/share /usr/local/; \
    rm -rf /tmp/node*
RUN npm install -g less@2.7.3 less-plugin-clean-css@1.5.1

# optional: create a fixed user
ENV HOME=/opt/odoo
RUN useradd -m -u 99910 -d "$HOME" odoo

ENV PATH=$HOME/scripts/bin:$HOME/.local/bin:$PATH

# image defaults (baked in)
COPY --chown=odoo:odoo config/ /opt/odoo/dist/

# assets
COPY --chown=odoo:odoo scripts/assets/pfbfer.zip /opt/odoo/scripts/assets/pfbfer.zip

# scripts
COPY --chown=odoo:odoo scripts/lib/common.sh /opt/odoo/scripts/lib/common.sh
COPY --chown=odoo:odoo --chmod=755 scripts/entrypoint.sh /opt/odoo/scripts/entrypoint.sh
COPY --chown=odoo:odoo --chmod=755 scripts/bin/updatemodules.sh /opt/odoo/scripts/bin/updatemodules
COPY --chown=odoo:odoo --chmod=755 scripts/bin/shell.sh /opt/odoo/scripts/bin/shell
COPY --chown=odoo:odoo --chmod=755 scripts/bin/fetchbasereqs.sh /opt/odoo/scripts/bin/fetchbasereqs
COPY --chown=odoo:odoo --chmod=755 scripts/bin/fetchreqs.sh /opt/odoo/scripts/bin/fetchreqs
COPY --chown=odoo:odoo --chmod=755 scripts/bin/fetchcode.sh /opt/odoo/scripts/bin/fetchcode
COPY --chown=odoo:odoo --chmod=755 scripts/bin/genaddonspath.py /opt/odoo/scripts/bin/genaddonspath
COPY --chown=odoo:odoo --chmod=755 scripts/bin/db.sh /opt/odoo/scripts/bin/db

USER odoo

RUN git config --global user.name "Odoo Bot" && git config --global user.email "odoo@example.com"

WORKDIR $HOME

ENTRYPOINT ["/opt/odoo/scripts/entrypoint.sh"]
