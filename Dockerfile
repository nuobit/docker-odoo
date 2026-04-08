FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV LANGUAGE=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    vim ca-certificates curl git unzip rsync \
    gcc build-essential \
    python3 python3-pip python3-setuptools python3-venv \
    python3-dev \
    libxml2-dev libxslt1-dev \
    libldap2-dev libsasl2-dev \
    libssl-dev \
    libjpeg-dev zlib1g-dev \
    libpq-dev \
    # Odoo 19 runtime dependencies (mirrors debian/control Depends)
    python3-asn1crypto \
    python3-babel \
    python3-cbor2 \
    python3-chardet \
    python3-cryptography \
    python3-dateutil \
    python3-docutils \
    python3-freezegun \
    python3-geoip2 \
    python3-gevent \
    python3-greenlet \
    python3-idna \
    python3-jinja2 \
    python3-ldap \
    python3-libsass \
    python3-lxml \
    python3-magic \
    python3-markupsafe \
    python3-num2words \
    python3-ofxparse \
    python3-openpyxl \
    python3-openssl \
    python3-passlib \
    python3-pil \
    python3-polib \
    python3-psutil \
    python3-psycopg2 \
    python3-pypdf2 \
    python3-qrcode \
    python3-renderpm \
    python3-reportlab \
    python3-requests \
    python3-rjsmin \
    python3-stdnum \
    python3-tz \
    python3-urllib3 \
    python3-vobject \
    python3-werkzeug \
    python3-xlrd \
    python3-xlsxwriter \
    python3-zeep \
    # Fonts and web assets shipped with Odoo
    fonts-dejavu-core \
    fonts-font-awesome \
    fonts-freefont-ttf \
    fonts-inconsolata \
    fonts-roboto-unhinted \
    libjs-underscore \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# PostgreSQL client from the official pgdg repo
RUN install -d /usr/share/postgresql-common/pgdg && \
        curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
            https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
        echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
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

# optional: create a fixed user
ENV HOME=/opt/odoo
RUN useradd -m -u 99910 -d "$HOME" odoo

# Virtualenv for pip-installed tooling (git-aggregator, click-odoo-contrib,
# openupgradelib). --system-site-packages lets the venv reuse python3-*
# packages installed from apt (lxml, psycopg2, reportlab, gevent, ...).
RUN python3 -m venv --system-site-packages /opt/odoo/venv && \
    chown -R odoo:odoo /opt/odoo/venv

ENV PATH=/opt/odoo/venv/bin:$HOME/scripts/bin:$HOME/.local/bin:$PATH

# image defaults (baked in)
COPY --chown=odoo:odoo config/ /opt/odoo/dist/

# scripts (assets, lib, bin)
# - makes entrypoint executable
# - strips .sh/.py extensions from bin/ scripts (e.g. db.sh -> db)
#   so they can be called as bare commands via PATH
# - makes all bin/ scripts executable
COPY --chown=odoo:odoo scripts/ /opt/odoo/scripts/
RUN cd /opt/odoo/scripts && \
    chmod 755 entrypoint.sh && \
    cd bin && \
    for f in *.sh *.py; do mv "$f" "${f%.*}"; done && \
    chmod 755 *

USER odoo

RUN git config --global user.name "Odoo Bot" && git config --global user.email "odoo@example.com"

WORKDIR $HOME

# Lightweight check: just verify Odoo HTTP server responds.
# 120s interval to minimize worker impact (each check occupies 1 worker briefly).
HEALTHCHECK --interval=120s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -fsS -o /dev/null http://localhost:8069/web/database/selector || exit 1

ENTRYPOINT ["/opt/odoo/scripts/entrypoint.sh"]
