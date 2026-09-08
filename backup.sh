#!/usr/bin/env bash
# =============================================================================
#  Backup do Ghost: dump do MySQL + pasta content/ (imagens, temas, uploads,
#  configuracoes de rotas/redirects) + config.production.json.
#
#  Uso (como root):  ghost-backup
#  Instalado por install.sh em /usr/local/sbin/ghost-backup e agendado todo
#  dia as 03:00 via /etc/cron.d/ghost-backup.
#
#  Variaveis (opcionais):
#    GHOST_DIR       padrao /var/www/ghost
#    BACKUP_DIR      padrao /var/backups/ghost
#    KEEP_DAYS       padrao 14 (apaga backups locais mais antigos que isso)
#    RCLONE_REMOTE   ex.: "oci:ghost-backups" -> copia o arquivo para um bucket
#                    (OCI Object Storage, S3, Google Drive...) se o rclone
#                    estiver instalado e configurado (rclone config).
#
#  Restauracao: ghost-restore /var/backups/ghost/ghost-AAAAMMDD-HHMMSS.tar.gz
# =============================================================================
set -euo pipefail

GHOST_DIR="${GHOST_DIR:-/var/www/ghost}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/ghost}"
KEEP_DAYS="${KEEP_DAYS:-14}"
RCLONE_REMOTE="${RCLONE_REMOTE:-}"
CFG="$GHOST_DIR/config.production.json"

[ "$(id -u)" -eq 0 ] || { echo "Execute como root (sudo ghost-backup)"; exit 1; }
[ -f "$CFG" ] || { echo "Config nao encontrado: $CFG"; exit 1; }

# Le as credenciais do banco direto do config do Ghost (uma por linha).
mapfile -t DB < <(python3 - "$CFG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))["database"]["connection"]
for k in ("host", "port", "user", "password", "database"):
    print(c.get(k, {"host": "localhost", "port": 3306}.get(k, "")))
PY
)
DB_HOST="${DB[0]:-localhost}"; DB_PORT="${DB[1]:-3306}"; DB_USER="${DB[2]}"; DB_PASS="${DB[3]}"; DB_NAME="${DB[4]}"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$BACKUP_DIR/ghost-$STAMP.tar.gz"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# Credenciais via arquivo temporario (nao aparecem em "ps").
MYCNF="$WORK/my.cnf"
umask 077
printf '[client]\nhost=%s\nport=%s\nuser=%s\npassword=%s\n' "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" > "$MYCNF"
umask 022

echo "[$(date '+%F %T')] dump do banco $DB_NAME"
mysqldump --defaults-extra-file="$MYCNF" --single-transaction --quick --routines --triggers \
  --set-gtid-purged=OFF "$DB_NAME" > "$WORK/db.sql"

# Versao do Ghost (util na hora de restaurar em outra VM)
GHOST_VERSION="$(ls -1 "$GHOST_DIR/versions" 2>/dev/null | sort -V | tail -1 || true)"
printf 'ghost_version=%s\ndomain=%s\ncreated=%s\n' "$GHOST_VERSION" \
  "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("url",""))' "$CFG")" \
  "$(date -Is)" > "$WORK/backup-info.txt"

echo "[$(date '+%F %T')] empacotando content/ e config"
tar -czf "$OUT" \
  -C "$WORK" db.sql backup-info.txt \
  -C "$GHOST_DIR" --exclude='content/logs' content config.production.json
chmod 600 "$OUT"

# Retencao local
find "$BACKUP_DIR" -maxdepth 1 -name 'ghost-*.tar.gz' -mtime +"$KEEP_DAYS" -delete

# Copia opcional para um bucket remoto
if [ -n "$RCLONE_REMOTE" ] && command -v rclone >/dev/null 2>&1; then
  echo "[$(date '+%F %T')] enviando para $RCLONE_REMOTE"
  rclone copy "$OUT" "$RCLONE_REMOTE" && echo "enviado."
fi

echo "[$(date '+%F %T')] OK: $OUT ($(du -h "$OUT" | cut -f1))"
