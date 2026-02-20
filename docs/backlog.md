# Backlog

Future decisions and tasks to revisit. Not in current scope.

- [ ] Split README.md into separate docs per command (db, snapshot, etc.) instead of one monolithic README
- [x] Define snapshot directory convention: where to place it on the host and on the container and how it maps into the container (bind mount path, naming, permissions) — defined in `docs/snapshot.md`
- [ ] Install `shellcheck` and validate all existing shell scripts (`scripts/bin/*.sh`, `scripts/lib/*.sh`) — fix any issues found
- [ ] Review `genaddonspath.py` exclude logic — current check is exact string match on `normpath`; should use path-boundary matching (`==` or `startswith(ex + "/")`) so `SRC_ODOO_REPO_DIR=odoo` also excludes `./odoo/addons` but not `./odoopepe`
- [ ] Harden `snapshot.sh` and `db.sh` against path traversal and unsafe `rm -rf`
  - **Problem:** Snapshot names and database names are used directly in filesystem paths without validation. A name like `../../etc/cron.d/evil` builds `$SNAPSHOT_DIR/../../etc/cron.d/evil`, which resolves outside the snapshot directory. This affects `mkdir -p`, `pg_dump -f`, `rsync`, and `rm -rf` — all would operate on arbitrary paths.
  - **Affected commands:** `backup` (creates dirs + writes outside SNAPSHOT_DIR), `restore` (reads from arbitrary path), `remove` (deletes arbitrary path). The `rm -rf` in `remove` and the backup ERR trap are the most dangerous.
  - **Same pattern in `db.sh`:** database names are used in filestore paths (`$ODOO_DATA_DIR/filestore/$dbname`) without validation — e.g., `rsync --delete` on restore could wipe arbitrary directories.
  - **Fix (two layers of defense):**
    1. **Input validation** — Add a `validate_name` helper to `common.sh` that rejects names containing `/`, `..`, or `.` (must be a single safe path component). Call it early in every command that takes user-provided names.
    2. **Safe deletion** — Add a `safe_remove_dir` helper to `common.sh` that resolves both parent and target with `realpath -m` before checking containment, then runs `rm -rf`. Replace all bare `rm -rf` calls with it. String prefix checks alone are not enough (`"foo/../../bar"` starts with `"foo/"` but resolves outside).
  - Both helpers belong in `common.sh` for reuse across all scripts.
