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

- Base OS: Debian stretch (EOL, using `archive.debian.org`)
- Python: 2.7
- Node.js: 6.x
- wkhtmltopdf: 0.12.1.4 (static Debian package)
- User: non-root (`odoo`, uid `99910`)

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
| `/opt/odoo/entrypoint.sh` | `entrypoint.sh` | Container entrypoint |
| `/opt/odoo/.local/lib/common.sh` | `lib/common.sh` | Shared functions and variables |
| `/opt/odoo/.local/bin/initdb` | `scripts/initdb.sh` | Initialize database script |
| `/opt/odoo/.local/bin/updatemodules` | `scripts/updatemodules.sh` | Update modules script |
| `/opt/odoo/.local/bin/shell` | `scripts/shell.sh` | Interactive shell script |
| `/opt/odoo/.local/bin/fetchbasereqs` | `scripts/fetchbasereqs.sh` | Fetch base requirements script |
| `/opt/odoo/.local/bin/fetchreqs` | `scripts/fetchreqs.sh` | Fetch repo requirements script |
| `/opt/odoo/.local/bin/fetchcode` | `scripts/fetchcode.sh` | Fetch git repositories script |
| `/etc/odoo/constraints.txt` | `constraints.txt` | Python package version constraints |
| `/opt/odoo/pfbfer.zip` | `pfbfer.zip` | ReportLab Type1 fonts archive |

**Runtime directories (created at runtime or via volume mounts):**

| Path | Purpose |
|------|---------|
| `/opt/odoo/src` | Odoo source code (git-aggregated, typically volume-mounted) |
| `/var/lib/odoo` | Odoo data directory (filestore, sessions, typically volume-mounted) |
| `/etc/odoo/odoo.conf` | Odoo configuration file (typically volume-mounted) |

**Note:** Paths shown are **inside the container**. Use volume mounts in docker-compose to map host directories to container paths.

---

## EntryPoint behavior

The container uses a **stateful bootstrap mechanism**:

- On first container start:
  - fetches base Python requirements
  - fetches git repositories using `git-aggregator`
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
| `initdb` | Initialize database | `docker compose exec <container> initdb <database>` |
| `updatemodules` | Update modules | `docker compose exec <container> updatemodules <database> <all\|module_list\|changed>` |
| `shell` | Interactive Odoo shell | `docker compose exec <container> shell <database>` |
| `fetchbasereqs` | Fetch base requirements | `docker compose exec <container> fetchbasereqs` |
| `fetchreqs` | Fetch repo requirements | `docker compose exec <container> fetchreqs <repo_path>` |
| `fetchcode` | Fetch git repositories | `docker compose exec <container> fetchcode [addon_path] [jobs]` |

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

## Example docker-compose configuration

```yaml
services:
  odoo10:
    image: ghcr.io/<org>/odoo-10.0:1.0.0
    container_name: odoo10
    user: "99910:99910"
    ports:
      - "127.0.0.1:8010:8069"
    volumes:
      - ./odoo.conf:/etc/odoo/odoo.conf:ro
      - ./src:/opt/odoo/src
      - ./repos.yaml:/opt/odoo/src/repos.yaml:ro
      - ./data:/var/lib/odoo
    networks:
      - odoo-net

networks:
  odoo-net:
    external: true
```

**Note:** This example uses **relative paths** (`./odoo.conf`, `./src`, `./data`) for simplicity. In production, consider using **absolute paths** for clarity:
- Config: `/srv/docker/stack/odoo10/odoo.conf`
- Source: `/srv/docker/data/odoo10/src`
- Data: `/srv/docker/data/odoo10/data`

**Directory structure convention:**

```
/srv/docker/
├── stack/              # Configuration files
│   ├── odoo10-1/       # Container-specific folder
│   │   ├── odoo.conf
│   │   ├── repos.yaml
│   │   └── docker-compose.yml
│   └── odoo10-2/       # Another container
│       └── ...
└── data/               # Runtime data
    ├── odoo10-1/       # Container-specific folder
    │   ├── src/        # Source code
    │   └── data/       # Database filestore, sessions, etc.
    └── odoo10-2/
        └── ...
```

- `/srv/docker/stack/<container-name>/` — **Configuration files**
  - Read-only files that define how the container runs
  - Usually version-controlled and backed up separately
  - Examples: odoo.conf, repos.yaml, docker-compose.yml
  
- `/srv/docker/data/<container-name>/` — **Runtime data**
  - Large, frequently changing data
  - Requires regular backups
  - Not typically version-controlled
  - Examples: src/ (git repos), data/ (Odoo filestore)

**Note:** The `/srv/docker/` base path and the folder names are **arbitrary conventions**—use any directory structure that fits your organization's standards.

---

## Environment variables

| Variable | Default | Description |
|--------|--------|------------|
| `DAT` | `/var/lib/odoo` | Data directory |
| `SRC` | `/opt/odoo/src` | Source directory |
| `CONF_BASE` | `/etc/odoo` | Config base path |
| `CONF` | `/etc/odoo/odoo.conf` | Odoo config file |
| `AGG` | `repos.yaml` | Git-aggregator config |
| `ODOO_BIN` | `odoo-bin` | Odoo executable |
| `PYTHON` | `python` | Python interpreter |

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

## Notes & limitations

- Debian stretch and Python 2.7 are EOL
- TLS / CA issues may occur in restricted networks
- Internet access is required at first bootstrap (pip, fonts)
- This image is **not suitable for new Odoo deployments**

---

## License & disclaimer

This image is provided as-is for legacy compatibility.
Odoo is a trademark of Odoo S.A.

Use at your own risk.
