#!/usr/bin/env bash
# =============================================================================
#  Restaura um backup gerado por backup.sh (ghost-backup).
#
#  Uso (como root):  ghost-restore /var/backups/ghost/ghost-AAAAMMDD-HHMMSS.tar.gz [--yes]
#
#  O que faz:
#    1. para o Ghost;
#    2. recria o banco a partir do db.sql do backup (SUBSTITUI o banco atual);
#    3. substitui a pasta content/ (SUBSTITUI imagens, temas e uploads atuais);
#    4. mantem o config.production.json atual (o do backup fica como
#       config.production.json.backup para consulta);
#    5. inicia o Ghost.
#
#  Para migrar para uma VM nova: rode install.sh nela, copie o .tar.gz e
#  execute este script. A senha do banco usada e a do config atual da VM.
#
#  Variaveis (opcionais): GHOST_DIR (padrao /var/www/ghost)
# =============================================================================
set -euo pipefail

ARCHIVE="${1:-}"
[ -n "$ARCHIVE" ] || { echo "uso: ghost-restore ARQUIVO.tar.gz [--yes]"; exit 1; }
[ -f "$ARCHIVE" ] || { echo "Arquivo nao encontrado: $ARCHIVE"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "Execute como root (sudo ghost-restore ...)"; exit 1; }

GHOST_DIR="${GHOST_DIR:-/var/www/ghost}"
CFG="$GHOST_DIR/config.production.json"
[ -f "$CFG" ] || { echo "Ghost nao encontrado em $GHOST_DIR (rode install.sh primeiro)"; exit 1; }
GHOST_USER="$(stat -c '%U' "$GHOST_DIR")"

if [ "${2:-}" != "--yes" ]; then
  echo "ATENCAO: isso SUBSTITUI o banco de dados e a pasta content/ de $GHOST_DIR"
  read -r -p "Continuar? [s/N] " ans
  [ "${ans,,}" = "s" ] || { echo "cancelado."; exit 0; }
fi

mapfile -t DB < <(python3 - "$CFG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))["database"]["connection"]
for k in ("host", "port", "user", "password", "database"):
    print(c.get(k, {"host": "localhost", "port": 3306}.get(k, "")))
PY
)
DB_HOST="${DB[0]:-localhost}"; DB_PORT="${DB[1]:-3306}"; DB_USER="${DB[2]}"; DB_PASS="${DB[3]}"; DB_NAME="${DB[4]}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
tar -xzf "$ARCHIVE" -C "$WORK"
[ -f "$WORK/db.sql" ] && [ -d "$WORK/content" ] || { echo "Backup invalido (faltam db.sql/content)"; exit 1; }
[ -f "$WORK/backup-info.txt" ] && { echo "Backup:"; sed 's/^/  /' "$WORK/backup-info.txt"; }

MYCNF="$WORK/my.cnf"
umask 077
printf '[client]\nhost=%s\nport=%s\nuser=%s\npassword=%s\n' "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" > "$MYCNF"
umask 022

echo "[$(date '+%F %T')] parando o Ghost"
sudo -u "$GHOST_USER" -H bash -lc "cd '$GHOST_DIR' && ghost stop" || true

echo "[$(date '+%F %T')] restaurando banco $DB_NAME"
# O usuario do Ghost so tem privilegios no proprio banco; DROP/CREATE do banco
# exigem root (auth_socket -> "mysql -u root" funciona como root do sistema).
mysql -u root -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
mysql --defaults-extra-file="$MYCNF" "$DB_NAME" < "$WORK/db.sql"

echo "[$(date '+%F %T')] restaurando content/"
rm -rf "$GHOST_DIR/content.restore-old"
[ -d "$GHOST_DIR/content" ] && mv "$GHOST_DIR/content" "$GHOST_DIR/content.restore-old"
cp -a "$WORK/content" "$GHOST_DIR/content"
mkdir -p "$GHOST_DIR/content/logs"
chown -R "$GHOST_USER":"$GHOST_USER" "$GHOST_DIR/content"
[ -f "$WORK/config.production.json" ] && cp "$WORK/config.production.json" "$GHOST_DIR/config.production.json.backup" \
  && chown "$GHOST_USER":"$GHOST_USER" "$GHOST_DIR/config.production.json.backup"

echo "[$(date '+%F %T')] iniciando o Ghost"
sudo -u "$GHOST_USER" -H bash -lc "cd '$GHOST_DIR' && ghost start"
rm -rf "$GHOST_DIR/content.restore-old"
echo "[$(date '+%F %T')] OK: restaurado de $ARCHIVE"
