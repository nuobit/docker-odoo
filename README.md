# Odoo 10.0 Docker Image

This repository contains a custom **Odoo 10.0** Docker image with a robust bootstrap/entrypoint system designed for long-running environments and legacy Odoo installations.

The image is intended for users who need:
- Odoo 10 (Python 2.7, Node 6)
- Git-aggregated source code
- Repeatable container bootstrapping
- Explicit control over upgrades and initialization

---

## Image

```
ghcr.io/<org>/odoo-10.0
```

**Note:** Replace `<org>` with your organization name (e.g., `nuobit`, `mycompany`, etc.)

### Available tags
- `1.0.0`, `1.0.1`, etc. — immutable release versions
- `edge` — latest build from main branch (moving tag, may break)

**Recommended:** always pin to a specific numbered tag in production (e.g., `1.0.0`).

**Tag strategy:**
- **Numbered versions** (`1.0.0`): Stable, tested releases that never change
- **`edge`**: Bleeding edge, rebuilt on every commit - use only for testing

---

## Base characteristics

- Base OS: Debian Stretch (EOL, using `archive.debian.org`)
- Python: 2.7
- Node.js: 6.x
- wkhtmltopdf: 0.12.1.4 (static Debian package)
- User: non-root (`odoo`, uid `99910`)
- Healthcheck: HTTP check on `/web/database/selector` every 120s

This image is **legacy by design** and intended for environments that must keep Odoo 10 running.

---

## User ID management

The container uses a **fixed UID `99910`** for the `odoo` user, deliberately hardcoded in both the Dockerfile and docker-compose configuration.

### Why we force a specific UID

Instead of letting Docker auto-assign UIDs, we **explicitly control** the user ID to ensure:
- **Predictable ownership**: Files created by the container always have the same UID across all environments
- **Dockerfile-compose consistency**: The UID in the image matches the UID specified in `user:` directive
- **Manageable permissions**: Administrators know exactly which UID to `chown` on host directories

### Why 99910?

- **Arbitrary but intentional**: We chose a high, arbitrary UID outside typical ranges
- **High UID range (90000+)**: Avoids collision with:
  - System users (typically < 1000)
  - Regular host users (typically 1000-60000)
  - Service users (typically 60000-90000)
- **Version indicator**: The `10` suffix represents Odoo version 10, making it identifiable
- **Consistent across deployments**: Same UID in development, staging, and production

### The problem we solve

**Without a fixed UID**, Docker might assign UID `1000` to the container user. If your host user also has UID `1000`:
- Files created by the container appear to belong to your host user
- Your host user can accidentally modify container-owned files
- Permissions become confusing and unpredictable
- Different environments might get different UIDs, breaking reproducibility

**With a fixed high UID (99910)**, there's no collision, and ownership is always clear.

### How to use

**You do NOT need to create this user on the host.** Linux uses numeric UIDs, not usernames. The container's `odoo` user (UID 99910) can access files owned by UID 99910 on the host, regardless of username.

**Set ownership on host bind-mounted directories:**
```bash
# Example for a container (could be odoo10-1, odoo10-customer1, etc.)
sudo chown -R 99910:99910 /srv/docker/data/odoo10-1
```

**Restrict permissions for security:**
```bash
sudo chmod -R o-rwx /srv/docker/data/odoo10-1
```

**Note:** Both the container name (`odoo10-1`) and host path (`/srv/docker/data/`) are **arbitrary examples**. You can use any naming convention and path structure that suits your environment:
- Container: `odoo10-customer1`, `odoo10-prod`, etc.
- Host path: `/srv/docker/data/`, `/opt/containers/`, `/home/user/docker/`, etc.

### Running multiple containers

You can run **multiple Odoo 10 containers** on the same host (e.g., `odoo10-1`, `odoo10-2`, `odoo10-customer1`), all using the **same UID `99910`**.

**This is NOT a problem** as long as:
- ✅ Each container has **its own separate bind-mounted directories**
- ✅ Directories are named clearly to match the container (e.g., `/srv/docker/data/odoo10-1`, `/srv/docker/data/odoo10-2`)

**What to avoid:**
- ❌ **Never share the same data directory** between multiple containers
- ❌ Don't bind `/srv/docker/data/odoo-shared` to both `odoo10-1` and `odoo10-2`

**Why this works:**
- Linux permissions are per-file, not per-user
- Multiple containers with UID 99910 can coexist peacefully
- Each container only accesses its own mounted directories
- File conflicts are impossible when directories are separate

**Example multi-container setup:**
```bash
# Container 1
sudo chown -R 99910:99910 /srv/docker/data/odoo10-1
sudo chmod -R o-rwx /srv/docker/data/odoo10-1

# Container 2 (different directory, same UID - no problem!)
sudo chown -R 99910:99910 /srv/docker/data/odoo10-2
sudo chmod -R o-rwx /srv/docker/data/odoo10-2
```

This ensures:
- Container can read/write bind-mounted volumes
- Files have consistent ownership across environments  
- No confusion with existing host users
- Other users cannot access sensitive data
- Multiple containers coexist without permission conflicts

---

## Runtime layout

**Container internal paths:**

| Container Path | Repository File | Purpose |
|----------------|-----------------|---------|
| `/opt/odoo/scripts/entrypoint.sh` | `scripts/entrypoint.sh` | Container entrypoint |
| `/opt/odoo/scripts/lib/common.sh` | `scripts/lib/common.sh` | Shared functions and variables |
| `/opt/odoo/scripts/bin/updatemodules` | `scripts/bin/updatemodules.sh` | Update modules script |
| `/opt/odoo/scripts/bin/shell` | `scripts/bin/shell.sh` | Interactive shell script |
| `/opt/odoo/scripts/bin/fetchbasereqs` | `scripts/bin/fetchbasereqs.sh` | Fetch base requirements script |
| `/opt/odoo/scripts/bin/fetchreqs` | `scripts/bin/fetchreqs.sh` | Fetch repo requirements script |
| `/opt/odoo/scripts/bin/fetchcode` | `scripts/bin/fetchcode.sh` | Fetch git repositories script |
| `/opt/odoo/scripts/bin/genaddonspath` | `scripts/bin/genaddonspath.py` | Generate addons_path from repos.yaml |
| `/opt/odoo/scripts/bin/db` | `scripts/bin/db.sh` | Database management script |
| `/opt/odoo/dist/defaults.env` | `config/defaults.env` | Image default configuration |
| `/opt/odoo/dist/constraints.txt` | `config/constraints.txt` | Python package version constraints |
| `/opt/odoo/scripts/assets/pfbfer.zip` | `scripts/assets/pfbfer.zip` | ReportLab Type1 fonts archive |

**Runtime directories (created at runtime or via volume mounts):**

| Path | Purpose |
|------|---------|
| `/opt/odoo/config/` | Instance configuration directory (bind-mounted) |
| `/opt/odoo/config/odoo.conf` | Odoo configuration file — at minimum set `db_host`, `db_user`, `db_password` and `admin_passwd` |
| `/opt/odoo/config/repos.yaml` | Git-aggregator config — contains all OCA repos with a `10.0` branch and actual Odoo modules (see [Localization repos](#localization-repos-l10n)) |
| `/opt/odoo/config/settings.env` | Instance-level overrides (optional) |
| `/opt/odoo/src` | Odoo source code (git-aggregated, typically volume-mounted) |
| `/var/lib/odoo` | Odoo data directory (filestore, sessions, typically volume-mounted) |

**Note:** Paths shown are **inside the container**. Use volume mounts in docker-compose to map host directories to container paths.

---

## EntryPoint behavior

The container uses a **stateful bootstrap mechanism**:

- On first container start:
  - fetches base Python requirements
  - fetches git repositories using `git-aggregator`
  - generates `addons_path` from repos.yaml and updates `odoo.conf`
  - fetches Odoo Python requirements
  - installs ReportLab Type1 fonts
- On subsequent restarts:
  - skips bootstrap
  - runs Odoo directly

Bootstrap state is stored in:
```
/var/lib/odoo/.bootstrap/
```

---

## Available scripts

These scripts can be executed inside the running container:

| Script | Description | Usage |
|--------|------------|-------|
| `db` | Database management | `docker compose exec <container> db <command> [args...]` |
| `updatemodules` | Update modules | `docker compose exec <container> updatemodules <database> <all\|module_list\|changed>` |
| `shell` | Interactive Odoo shell | `docker compose exec <container> shell <database>` |
| `fetchbasereqs` | Fetch base requirements | `docker compose exec <container> fetchbasereqs` |
| `fetchreqs` | Fetch repo requirements | `docker compose exec <container> fetchreqs <repo_path>` |
| `fetchcode` | Fetch git repositories | `docker compose exec <container> fetchcode [addon_path] [jobs]` |

### Database management with `db`

The `db` script provides database management commands:

```bash
# Create a database (with unaccent extension):
docker compose exec <container> db create <database>

# Initialize Odoo base module in database:
docker compose exec <container> db init <database>
docker compose exec <container> db init <database> demo   # with demo data

# Drop a database:
docker compose exec <container> db drop <database>

# Reset (drop and recreate) a database:
docker compose exec <container> db reset <database>

# List databases owned by DB_OWNER:
docker compose exec <container> db list

# List PostgreSQL users:
docker compose exec <container> db users

# Create/drop the DB owner user:
docker compose exec <container> db createuser
docker compose exec <container> db dropuser
```

#### Automatic connection termination on drop/reset

The `drop` and `reset` commands automatically handle active connections before dropping a database:

1. **Block all new connections** — sets `datallowconn = false` on the database, preventing anyone (including superusers) from opening new connections
2. **Terminate existing connections** — kills all active backends connected to the database
3. **Drop the database**

This two-step approach eliminates the race condition where new connections could sneak in between termination and the actual drop. You do **not** need to manually stop Odoo or disconnect clients — the script handles it for you.

#### Connection control helpers

The `db` script also provides lower-level connection control functions (used internally, but available for manual recovery or maintenance):

| Function | SQL effect | Who's blocked |
|---|---|---|
| `do_block_all_connections` | `datallowconn = false` | Everyone (including superusers) |
| `do_unblock_all_connections` | `datallowconn = true` | Nobody |
| `do_block_user_connections` | `CONNECTION LIMIT 0` | Regular users only (superusers can still connect) |
| `do_unblock_user_connections` | `CONNECTION LIMIT -1` | Nobody (unlimited) |

Use `do_block_user_connections` / `do_unblock_user_connections` when you need to prevent regular users from connecting while keeping superuser access for maintenance. Use the `_all_` variants for a complete lockout (e.g., before dropping a database).

#### Configuration

Connection settings are read from `odoo.conf` (`db_host`, `db_user`, `db_password`). Admin credentials come from `defaults.env` (or overridden in `settings.env`):

| Variable | Source | Description |
|---|---|---|
| `DB_HOST` | `db_host` in odoo.conf | PostgreSQL host |
| `DB_PGUSER` | `defaults.env` | PostgreSQL admin user |
| `DB_PGDB` | `defaults.env` | PostgreSQL maintenance database |
| `DB_PGUSER_PASSWORD` | `settings.env` | PostgreSQL admin password (prompted if unset) |
| `DB_FORCE` | `defaults.env` | Skip database name confirmation on drop/reset |

The `-f` / `--force` flag can also be used to skip the name confirmation:
```bash
docker compose exec <container> db -f drop <database>
```

**Interactive shell access:**
```bash
docker compose exec -it <container> bash
```

**Running Python scripts via stdin:**
When piping a script to `shell`, use the `-T` flag:
```bash
docker compose exec -T <container> shell <database> < myscript.py
```

---

## Deploying an instance

This repository is for **building the Docker image**, not for running containers directly. To deploy an instance, copy the template files from `deploy/` to your instance directory and customize them.

### 1. Copy template files

```bash
# Create the instance directory and copy all deploy files
cp -r deploy/* /srv/docker/stack/odoo10-1/

# Create data directories
mkdir -p /srv/docker/data/odoo10-1/{src,data}

# Set ownership
sudo chown -R 99910:99910 /srv/docker/stack/odoo10-1/config
sudo chown -R 99910:99910 /srv/docker/data/odoo10-1
```

**Important — config directory ownership:** The `config/` directory (and its contents) **must** be owned by UID `99910` on the host. During bootstrap, the `genaddonspath` script writes the generated `addons_path` directly into `odoo.conf`. If the container cannot write to this file, bootstrap will fail and Odoo will start without the correct addons path.

```bash
# Required: ensure the container can write to config files
sudo chown -R 99910:99910 /srv/docker/stack/odoo10-1/config
```

### 2. Customize configuration

Edit the copied files for your instance:
- `config/odoo.conf` — at minimum set `db_host`, `db_user`, `db_password` and `admin_passwd`
- `config/repos.yaml` — enable/disable OCA repos as needed
- `config/settings.env` — set `DB_PGUSER_PASSWORD` and any overrides
- `docker-compose.yml` — adjust image tag, ports, network name

### 3. Start the container

```bash
cd /srv/docker/stack/odoo10-1
docker compose up -d
```

### Directory structure convention

The `deploy/` folder mirrors the target instance layout:

```
deploy/                              /srv/docker/stack/odoo10-1/
├── docker-compose.yml         →     ├── docker-compose.yml
└── config/                    →     └── config/  (bind-mounted to /opt/odoo/config/)
    ├── odoo.conf                        ├── odoo.conf
    ├── repos.yaml                       ├── repos.yaml
    └── settings.env                     └── settings.env
```

Runtime data is stored separately:

```
/srv/docker/data/odoo10-1/
├── src/         # Source code (git-aggregated)
└── data/        # Odoo filestore, sessions, etc.
```

- `/srv/docker/stack/<container>/` — **Configuration** (version-controlled, backed up separately)
- `/srv/docker/data/<container>/` — **Runtime data** (large, requires regular backups)

**Note:** The `/srv/docker/` base path and the folder names are **arbitrary conventions**—use any directory structure that fits your organization's standards.

### Example docker-compose configuration

```yaml
services:
  odoo10-1:
    container_name: odoo10-1
    image: ghcr.io/<org>/odoo-10.0:1.0.0
    user: "99910:99910"
    ports:
      - "127.0.0.1:8010:8069"
    volumes:
      - /srv/docker/stack/odoo10-1/config:/opt/odoo/config
      - /srv/docker/data/odoo10-1/src:/opt/odoo/src
      - /srv/docker/data/odoo10-1/data:/var/lib/odoo
    restart: unless-stopped
    mem_limit: 4g
    networks: [pg96-1-net]

networks:
  pg96-1-net:
    external: true
```

---

## Environment variables

### Image defaults (`config/defaults.env`)

Baked into the image at `/opt/odoo/dist/defaults.env` (from `config/defaults.env` in the repo). Can be overridden by instance `settings.env`.

| Variable | Default | Description |
|---|---|---|
| `PYTHON_BIN` | `/usr/bin/python` | Python interpreter |
| `DIST_DIR` | _(auto)_ | Image dist directory (`/opt/odoo/dist/`) |
| `DIST_CONSTRAINTS` | `${DIST_DIR}/constraints.txt` | pip constraints file |
| `INSTANCE_DIR` | `${HOME}/config` | Instance config directory (bind-mounted) |
| `INSTANCE_SETTINGS` | `${INSTANCE_DIR}/settings.env` | Instance overrides file |
| `INSTANCE_REPOS` | `${INSTANCE_DIR}/repos.yaml` | Git-aggregator config |
| `SRC_DIR` | `${HOME}/src` | Source code directory |
| `SRC_ODOO_REPO_DIR` | `odoo` | Odoo repo directory name |
| `ODOO_DIR` | `${SRC_DIR}/odoo` | Odoo source directory |
| `ODOO_BIN` | `${ODOO_DIR}/odoo-bin` | Odoo executable |
| `ODOO_CONF` | `${INSTANCE_DIR}/odoo.conf` | Odoo config file |
| `ODOO_DATA_DIR` | `/var/lib/odoo` | Odoo data directory |
| `DB_PGUSER` | `postgres` | PostgreSQL admin user |
| `DB_PGDB` | `postgres` | PostgreSQL maintenance database |
| `DB_FORCE` | `false` | Skip name confirmation on drop/reset |

### Instance overrides (`settings.env`)

Bind-mounted at `/opt/odoo/config/settings.env`. Sourced after `defaults.env`, overrides any value. Changes take effect on next script execution or container restart — no image rebuild or container recreation needed.

A reference template is available in the `deploy/` directory of the project repository.

| Variable | Description |
|---|---|
| `DB_PGUSER_PASSWORD` | PostgreSQL admin password (prompted if unset) |
| `DB_FORCE` | Skip database name confirmation on drop/reset |

---

## Building locally

```bash
docker build -t odoo-10.0:local .
```

---

## Building and publishing to registry

**Note:** Replace `<org>` with your organization name in all commands below.

### Build and push edge version

```bash
# Build with edge tag
docker build -t ghcr.io/<org>/odoo-10.0:edge .

# Push to registry
docker push ghcr.io/<org>/odoo-10.0:edge
```

### Build and tag a release version

```bash
# Build with version tag (always 3 numbers: MAJOR.MINOR.PATCH)
docker build -t ghcr.io/<org>/odoo-10.0:1.0.0 .

# Push the tag
docker push ghcr.io/<org>/odoo-10.0:1.0.0
```

### Best practices for tagging

1. **Always use semantic versioning with 3 numbers**: `MAJOR.MINOR.PATCH`
   - Example: `1.0.0`, `1.2.5`, `2.0.0`
   - `MAJOR` (1st number): Breaking changes, incompatible updates
   - `MINOR` (2nd number): New features, backwards compatible
   - `PATCH` (3rd number): Bug fixes only, no new features
   - **Never use fewer than 3 numbers** - always use the format `X.Y.Z`

2. **Production recommendations**:
   - ✅ Always pin to full 3-number version: `ghcr.io/<org>/odoo-10.0:1.0.0`
   - ❌ Never use `edge` in production
   - ❌ Never use short versions like `1.0` or `1`

3. **Test before tagging**:
   - Build and test locally first
   - Only push to registry after validation
   - Tag releases from tested commits only

---

## Localization repos (l10n)

The `repos.yaml` file includes all OCA addon repositories that have a `10.0` branch with actual Odoo modules. **Localization repos are commented out by default** to avoid fetching unnecessary country-specific code.

To enable a localization, edit your instance `repos.yaml` and uncomment the relevant `l10n-*` block. For example, to enable Spanish localization:

```yaml
./oca/l10n-spain:
    remotes:
        oca: https://github.com/OCA/l10n-spain.git
    target:
        oca 10.0
    merges:
        - oca 10.0
```

After uncommenting, re-run `fetchcode` to clone the newly enabled repos.

---

## OpenUpgrade (database migration)

The `repos.yaml` file includes a **commented-out** entry for [OCA/OpenUpgrade](https://github.com/OCA/OpenUpgrade). OpenUpgrade is a patched fork of Odoo that adds migration scripts for upgrading a database from a previous Odoo version (e.g. 9.0 to 10.0).

**When to enable it:**
- You are migrating an existing database from Odoo 9.0 (or earlier) to 10.0
- You need the OpenUpgrade migration scripts to transform data and schema

**How to use:**
1. Uncomment the `./openupgrade` block in `repos.yaml`
2. Run `fetchcode` to clone the OpenUpgrade repo
3. Run the migration following the [OpenUpgrade documentation](https://github.com/OCA/OpenUpgrade/blob/10.0/README.md)
4. After a successful migration, **comment it back out** and restart normally with the standard Odoo/OCB source

**Do not leave OpenUpgrade enabled in normal operation** — it is only needed during the migration process itself.

---

## Notes & limitations

- Debian Stretch and Python 2.7 are EOL
- TLS / CA issues may occur in restricted networks
- Internet access is required at first bootstrap (pip, fonts)
- This image is **not suitable for new Odoo deployments**

---

## License & disclaimer

This image is provided as-is for legacy compatibility.
Odoo is a trademark of Odoo S.A.

Use at your own risk.
