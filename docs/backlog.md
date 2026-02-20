# Backlog

Future decisions and tasks to revisit. Not in current scope.

- [ ] Split README.md into separate docs per command (db, snapshot, etc.) instead of one monolithic README
- [x] Define snapshot directory convention: where to place it on the host and on the container and how it maps into the container (bind mount path, naming, permissions) — defined in `docs/snapshot.md`
- [ ] Install `shellcheck` and validate all existing shell scripts (`scripts/bin/*.sh`, `scripts/lib/*.sh`) — fix any issues found
- [ ] Review `genaddonspath.py` exclude logic — current check is exact string match on `normpath`; should use path-boundary matching (`==` or `startswith(ex + "/")`) so `SRC_ODOO_REPO_DIR=odoo` also excludes `./odoo/addons` but not `./odoopepe`
