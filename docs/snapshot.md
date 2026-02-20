# Snapshot command

The `snapshot` command provides named create/restore of a complete Odoo environment state: database (schema + data) and filestore (attachments, images, reports). It is designed for development workflows like "save state before testing something destructive" and for creating portable copies of an environment.

This is a separate command from `db` because a snapshot includes more than just the database — it also captures the filestore.

**Note:** The existing `db import` command (SQL-only, stdin-based) remains unchanged and serves a different purpose — importing external SQL dumps from production servers or third parties. `snapshot` is for local named create/restore workflows with full environment state (DB + filestore).

---

## Commands

```
snapshot create  [-v|--verbose] [-j|--jobs N] [-n|--note "text"] [--no-filestore] <dbname> <snapshot-name>
snapshot restore [-f|--force] [-v|--verbose] [-j|--jobs N] <snapshot-name> [dbname]
snapshot list
snapshot remove  [-f|--force] <snapshot-name>
```

| Command | Description |
|---|---|
| `create` | Create a snapshot of DB + filestore |
| `restore` | Restore a named snapshot into a database |
| `list` | List available snapshots |
| `remove` | Delete a snapshot |

### Argument order

Follows the Unix `cp`/`rsync` convention: **source first, destination second**.

- `create <dbname> <snapshot-name>` — reading FROM the database, writing TO the snapshot
- `restore <snapshot-name> [dbname]` — reading FROM the snapshot, writing TO the database

On `restore`, `dbname` is optional — if omitted, it defaults to the `source_db` recorded in `metadata.json` (i.e., the database name used at creation time). This covers the most common use case of restoring to the same database without redundant typing, while still allowing restore to a different database name when needed.

### Options

All options go after the subcommand, before positional arguments.

| Short | Long | Description | Applies to |
|---|---|---|---|
| `-f` | `--force` | Skip confirmation prompts (sets `CONFIRM_LEVEL=none`) | `restore`, `remove` |
| `-v` | `--verbose` | Show detailed output from `pg_dump`, `pg_restore`, and `rsync` (default: errors only) | `create`, `restore` |
| `-j` | `--jobs` | Parallel workers for `pg_dump`/`pg_restore` (overrides `SNAPSHOT_JOBS`) | `create`, `restore` |
| `-n` | `--note` | Optional description stored in metadata | `create` |
| | `--no-filestore` | Skip filestore (database only) | `create` |

---

## Snapshot directory structure

Each snapshot is stored as a directory containing a metadata file and up to two subdirectories:

```
$SNAPSHOT_DIR/                              # dedicated bind mount (default: /opt/odoo/snapshots)
└── before-migration/                       # snapshot name
    ├── metadata.json                       # snapshot metadata
    ├── db/                                 # pg_dump -Fd output (directory format)
    │   ├── toc.dat
    │   ├── 3456.dat.gz
    │   ├── 3457.dat.gz
    │   └── ...
    └── filestore/                          # rsync copy of Odoo filestore (absent if --no-filestore)
        ├── 00/
        ├── 01/
        └── ...
```

The `filestore/` directory is **not created** when `--no-filestore` is used. Its absence signals to `restore` that the snapshot has no filestore data.

### Why directory format (`pg_dump -Fd`)

- **Incremental-friendly**: tools like Borg or restic can deduplicate individual data files
- **Parallel dump/restore**: `pg_dump -j N` and `pg_restore -j N` use multiple workers
- **No single large file**: avoids creating multi-GB monolithic dumps

### Metadata file (`metadata.json`)

Each snapshot includes a `metadata.json` with:

```json
{
  "source_db": "production",
  "timestamp": "2026-02-20T14:30:00Z",
  "odoo_version": "10.0",
  "pg_version": "12.17",
  "note": "before upgrading account module",
  "size_db": "850M",
  "size_filestore": "380M",
  "size_total": "1.2G"
}
```

- `source_db` — the database name at creation time (informational only; restore target is independent and can be any database name)
- `timestamp` — when the snapshot was taken (independent of filesystem dates, which `rsync`/`cp` can alter)
- `odoo_version` — safety reference; helps identify compatibility when restoring
- `pg_version` — PostgreSQL server version; helps detect potential compatibility issues on restore
- `note` — optional user-provided description (omitted if `-n`/`--note` not used)
- `size_db` — database dump size (computed via `du -sh` on `db/` directory at creation time)
- `size_filestore` — filestore size (computed via `du -sh` on `filestore/` directory at creation time; omitted if `--no-filestore`)
- `size_total` — total snapshot size (computed via `du -sh` on the snapshot root). Since snapshots are immutable, sizes never become stale

Used by `snapshot list` to display information instantly without inspecting dump contents or walking the directory tree.

---

## Command details

### `snapshot create [options] <dbname> <snapshot-name>`

Creates a named snapshot from a live database and its filestore.

**Steps:**

1. Validate that `$SNAPSHOT_DIR/<snapshot-name>` does **not** already exist (error if it does)
2. Create `$SNAPSHOT_DIR/<snapshot-name>/db/` directory (and `filestore/` unless `--no-filestore`)
3. Dump the database:
   ```
   pg_dump -Fd -j $SNAPSHOT_JOBS --no-owner --no-acl \
     -h $DB_HOST -U $DB_OWNER -d <dbname> \
     -f $SNAPSHOT_DIR/<snapshot-name>/db/
   ```
4. Copy the filestore (skipped if `--no-filestore`):
   ```
   rsync -a $ODOO_DATA_DIR/filestore/<dbname>/ $SNAPSHOT_DIR/<snapshot-name>/filestore/
   ```
5. Compute sizes with `du -sh` and write `metadata.json` (source dbname, timestamp, Odoo version, PG version, note, sizes)
6. On failure, clean up the partially created snapshot directory

**Notes:**
- No connection blocking — `pg_dump` takes a consistent snapshot of a live database
- Uses `--no-owner --no-acl` so the dump is portable across different DB users/names
- Uses `PGPASSWORD` with `DB_OWNER` credentials (read from `odoo.conf`)
- If the source filestore directory is missing (and `--no-filestore` was not used), shows a WARNING and proceeds with database-only snapshot

### `snapshot restore [options] <snapshot-name> [dbname]`

Restores a named snapshot into a database, replacing it completely.

If `dbname` is omitted, defaults to `source_db` from the snapshot's `metadata.json`.

**Steps:**

1. Validate that `$SNAPSHOT_DIR/<snapshot-name>` **exists** (error if not)
2. Resolve target database name: use provided `dbname`, or read `source_db` from `metadata.json`
3. Confirmation prompt (same `confirm_destructive` pattern as `db drop`/`db reset`):
   - Warns that database `<dbname>` will be dropped and recreated
   - User must type the database name to confirm
   - Skipped with `-f`/`--force`
4. If snapshot has no filestore (`filestore/` directory absent) but the target database has an existing filestore on disk, warn the user:
   ```
   WARNING: Snapshot '<name>' has no filestore, but '<dbname>' has an existing filestore.
   The existing filestore will NOT be modified.
   Continue? [y/N]
   ```
   Skipped with `-f`/`--force`.
5. Drop the existing database (reuses `db` command):
   ```
   db drop -f <dbname>
   ```
6. Create a fresh database (reuses `db` command):
   ```
   db create <dbname>
   ```
7. Restore the database dump:
   ```
   pg_restore -Fd -j $SNAPSHOT_JOBS --no-owner --no-acl \
     -h $DB_HOST -U $DB_OWNER -d <dbname> \
     $SNAPSHOT_DIR/<snapshot-name>/db/
   ```
8. Restore the filestore (skipped if `filestore/` directory absent in snapshot):
   ```
   rsync -a --delete $SNAPSHOT_DIR/<snapshot-name>/filestore/ $ODOO_DATA_DIR/filestore/<dbname>/
   ```

**Notes:**
- The target `<dbname>` can differ from the original — `--no-owner` makes this transparent
- `--delete` on rsync ensures the target filestore is an exact copy (removes stale files)
- Reuses `db drop` and `db create` commands as-is — no changes to `db.sh` needed
- `db` is called with `-f` flag because confirmation is already handled by `snapshot restore` itself

### `snapshot list`

Lists available snapshots with metadata and disk usage.

**Output format:**

```
NAME                 SOURCE DB     DATE                  DB      FILESTORE  TOTAL
before-migration     production    2026-02-20 14:30:00   850M    380M       1.2G
  Note: before upgrading account module
after-cleanup        staging       2026-02-19 10:15:00   290M    50M        340M
db-only-save         production    2026-02-18 16:00:00   850M    -          850M
```

Snapshots created with `--no-filestore` show `-` in the FILESTORE column. Notes are displayed below the snapshot entry when present.

**Steps:**

1. Iterate directories in `$SNAPSHOT_DIR`
2. Read `metadata.json` from each (sizes are pre-computed at creation time)
3. Display formatted table sorted by date (newest first)

### `snapshot remove [options] <snapshot-name>`

Deletes a snapshot.

**Steps:**

1. Validate that `$SNAPSHOT_DIR/<snapshot-name>` **exists** (error if not)
2. Confirmation prompt (same `confirm_destructive` pattern, skipped with `-f`/`--force`):
   - User must type the snapshot name to confirm
3. `rm -rf $SNAPSHOT_DIR/<snapshot-name>/`

---

## Configuration

### New variables in `defaults.env`

| Variable | Default | Description |
|---|---|---|
| `SNAPSHOT_DIR` | `/opt/odoo/snapshots` | Directory where snapshots are stored (should be a dedicated bind mount) |
| `SNAPSHOT_JOBS` | `2` | Parallel workers for `pg_dump`/`pg_restore` (`-j` flag) |

Both can be overridden in `settings.env`.

### Required bind mount

The snapshot directory requires a **dedicated bind mount** in `docker-compose.yml`:

**Default — same volume as data (simplest setup):**

```yaml
services:
  odoo10-1:
    volumes:
      - /srv/docker/data/odoo10-1/data:/var/lib/odoo                   # Odoo runtime data (existing)
      - /srv/docker/data/odoo10-1/snapshots:/opt/odoo/snapshots        # snapshots (new, sibling of data/)
```

**Alternative — separate volume (e.g., snapshots on a larger/cheaper disk):**

```yaml
services:
  odoo10-1:
    volumes:
      - /srv/docker/data/odoo10-1/data:/var/lib/odoo                   # SSD LVM volume
      - /srv/backups/odoo/odoo10-1/snapshots:/opt/odoo/snapshots       # HDD LVM volume
```

The snapshot directory is a **sibling** of `data/` on the host (or on a completely different path/volume). This allows placing each on a different LVM volume, disk, or partition — e.g., `data/` on a fast SSD for production performance, `snapshots/` on a larger HDD for storage capacity.

**Why a dedicated mount:**
- **Separate volumes** — `data/` and `snapshots/` can live on different LVM volumes, disks, or partitions
- **Separation of concerns** — snapshots are a dev tool, not Odoo runtime data
- **Independent sizing** — snapshot storage can grow independently without affecting Odoo's data volume
- **Visibility** — easy to browse from the host without digging into Odoo's data volume
- **Cleanup** — wipe snapshots without touching Odoo's data
- **Sharing** — multiple containers can point at the same snapshots directory

---

## Script location

```
scripts/
├── bin/
│   ├── db.sh              → `db` command        (database-only operations)
│   ├── snapshot.sh        → `snapshot` command   (database + filestore)
│   ├── shell.sh           → `shell` command
│   └── ...
├── lib/
│   └── common.sh
└── entrypoint.sh
```

The Dockerfile strips `.sh` extensions and adds `scripts/bin/` to PATH, so `snapshot.sh` automatically becomes the `snapshot` command.

---

## Reuse from `db.sh`

`snapshot.sh` calls `db` commands as external CLI commands — no changes to `db.sh` are needed.

| Operation | How snapshot.sh does it |
|---|---|
| Drop database + terminate connections | `db drop -f <dbname>` |
| Create database + unaccent extension | `db create <dbname>` |
| Admin password handling | Handled by `db` internally |

`snapshot.sh` only needs DB_OWNER credentials (from `odoo.conf`) for `pg_dump`/`pg_restore`. It reads these using the same `odoo_conf_get` pattern, sourced from `common.sh`.

---

## Validations

| Command | Condition | Behavior |
|---|---|---|
| `create` | Snapshot already exists | `ERROR: Snapshot '<name>' already exists. Remove it first or choose a different name.` |
| `create` | Filestore directory missing (without `--no-filestore`) | `WARNING: No filestore found for '<dbname>'. Creating database-only snapshot.` |
| `restore` | Snapshot does not exist | `ERROR: Snapshot '<name>' not found in $SNAPSHOT_DIR.` |
| `restore` | Destructive confirmation | Same `confirm_destructive` as `db drop` — type database name to confirm |
| `restore` | No filestore in snapshot but existing filestore on target | `WARNING` + interactive confirmation (proceed leaves existing filestore untouched) |
| `remove` | Snapshot does not exist | `ERROR: Snapshot '<name>' not found in $SNAPSHOT_DIR.` |
| `remove` | Destructive confirmation | Type snapshot name to confirm |
| All | `$SNAPSHOT_DIR` not mounted/accessible | `ERROR: Snapshot directory '$SNAPSHOT_DIR' does not exist or is not accessible.` |

---

## Usage examples

```bash
# Save current state before a risky operation
docker compose exec odoo snapshot create mydb before-migration

# Save with a note
docker compose exec odoo snapshot create -n "before upgrading account module" mydb before-migration

# Save database only (skip filestore)
docker compose exec odoo snapshot create --no-filestore mydb quick-save

# List available snapshots
docker compose exec odoo snapshot list

# Restore to the original database (dbname from metadata.json)
docker compose exec odoo snapshot restore before-migration

# Restore to a different database name
docker compose exec odoo snapshot restore before-migration mydb-test

# Delete a snapshot
docker compose exec odoo snapshot remove before-migration

# Skip confirmation prompts
docker compose exec odoo snapshot restore -f before-migration mydb
docker compose exec odoo snapshot remove -f old-snapshot

# Verbose output (show pg_dump/pg_restore/rsync progress)
docker compose exec odoo snapshot create -v mydb before-migration
docker compose exec odoo snapshot restore -v before-migration
```
