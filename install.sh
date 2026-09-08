#!/usr/bin/env bash
# =============================================================================
#  Ghost (https://docs.ghost.org/install/ubuntu) em Ubuntu 22.04/24.04
#  na Oracle Cloud Infrastructure (OCI) - instalador em um unico comando.
#
#  Uso (como root, via sudo):
#    curl -fsSL https://raw.githubusercontent.com/hebertpaes/ghost-oci/main/install.sh \
#      | sudo DOMAIN=comenta.com.br EMAIL=contato@comenta.com.br bash
#
#  Tambem serve como "Initialization script" (cloud-init) na criacao da VM:
#  basta prefixar as variaveis (ver cloud-init.example.sh).
#
#  Variaveis de ambiente:
#    DOMAIN        (obrigatoria) dominio do blog, ex: comenta.com.br
#    EMAIL         e-mail para o Let's Encrypt        (padrao: admin@DOMAIN)
#    GHOST_DIR     diretorio da instalacao            (padrao: /var/www/ghost)
#    GHOST_USER    usuario nao-root dono do Ghost     (padrao: ubuntu)
#    DB_NAME       banco MySQL                        (padrao: ghost_prod)
#    DB_USER       usuario MySQL                      (padrao: ghost)
#    DB_PASS       senha MySQL                        (padrao: gerada)
#    NODE_MAJOR    versao do Node.js                  (padrao: 22)
#    SKIP_UPGRADE  =1 pula o "apt-get upgrade"        (padrao: 0)
#    REPO_RAW      base dos scripts auxiliares (backup/restore)
#
#  Log completo: /var/log/ghost-install.log
#  Credenciais:  /root/ghost-credentials.txt (modo 600)
#
#  O script e idempotente: pode ser executado de novo para completar uma
#  instalacao interrompida sem duplicar regras de firewall nem o banco.
# =============================================================================
set -euo pipefail

LOG=/var/log/ghost-install.log
touch "$LOG" && chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1

log() { echo "[$(date '+%F %T')] $*"; }
die() { log "ERRO: $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Execute como root (sudo)."

DOMAIN="${DOMAIN:-}"
[ -n "$DOMAIN" ] || die "Defina DOMAIN=seu.dominio (ex.: DOMAIN=comenta.com.br)."
DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN%%[/:]*}"
EMAIL="${EMAIL:-admin@${DOMAIN}}"
GHOST_DIR="${GHOST_DIR:-/var/www/ghost}"
GHOST_USER="${GHOST_USER:-ubuntu}"
DB_NAME="${DB_NAME:-ghost_prod}"
DB_USER="${DB_USER:-ghost}"
NODE_MAJOR="${NODE_MAJOR:-22}"
SKIP_UPGRADE="${SKIP_UPGRADE:-0}"
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/hebertpaes/ghost-oci/main}"
CRED_FILE=/root/ghost-credentials.txt

export DEBIAN_FRONTEND=noninteractive
export HOME=/root
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Reaproveita a senha de uma execucao anterior (idempotencia); senao gera uma nova.
if [ -z "${DB_PASS:-}" ] && [ -f "$CRED_FILE" ]; then
  DB_PASS="$(sed -n 's/^MySQL senha: //p' "$CRED_FILE" | head -1 || true)"
fi
DB_PASS="${DB_PASS:-$(python3 -c 'import secrets;print(secrets.token_urlsafe(18))')}"

log "=== Ghost em OCI: DOMAIN=$DOMAIN EMAIL=$EMAIL DIR=$GHOST_DIR USER=$GHOST_USER ==="

# -----------------------------------------------------------------------------
# 0. Usuario dono do Ghost (nao-root, com sudo sem senha - exigido pelo ghost-cli)
# -----------------------------------------------------------------------------
if ! id -u "$GHOST_USER" >/dev/null 2>&1; then
  log "Criando usuario $GHOST_USER"
  adduser --disabled-password --gecos "" "$GHOST_USER"
fi
echo "$GHOST_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$GHOST_USER"
chmod 440 "/etc/sudoers.d/90-$GHOST_USER"

# -----------------------------------------------------------------------------
# 1. Credenciais ANTES de qualquer mudanca (se algo falhar depois, nada se perde)
# -----------------------------------------------------------------------------
umask 077
cat > "$CRED_FILE" <<TXT
Dominio: ${DOMAIN}
Painel admin: https://${DOMAIN}/ghost  (http:// ate o certificado ser emitido)
Diretorio: ${GHOST_DIR}
Usuario do sistema: ${GHOST_USER}
MySQL banco: ${DB_NAME}
MySQL usuario: ${DB_USER}
MySQL senha: ${DB_PASS}
MySQL root: autenticacao por socket (use: sudo mysql)
TXT
umask 022
log "Credenciais gravadas em $CRED_FILE"

# -----------------------------------------------------------------------------
# 2. Firewall local da imagem Oracle: libera 80/443 ANTES da regra REJECT.
#    Idempotente. NAO usar ufw em imagens Ubuntu da Oracle (pode remover as
#    regras iSCSI/InstanceServices e a VM deixa de iniciar).
# -----------------------------------------------------------------------------
open_port() {
  local bin="$1" port="$2" pos
  command -v "$bin" >/dev/null 2>&1 || return 0
  "$bin" -C INPUT -p tcp -m state --state NEW -m tcp --dport "$port" -j ACCEPT 2>/dev/null && return 0
  pos="$("$bin" -L INPUT --line-numbers -n 2>/dev/null | awk '$2=="REJECT"{print $1; exit}')"
  if [ -n "$pos" ]; then
    "$bin" -I INPUT "$pos" -p tcp -m state --state NEW -m tcp --dport "$port" -j ACCEPT
  else
    "$bin" -A INPUT -p tcp -m state --state NEW -m tcp --dport "$port" -j ACCEPT
  fi
  log "Firewall ($bin): porta $port liberada"
}
for p in 80 443; do open_port iptables "$p"; open_port ip6tables "$p" || true; done

# -----------------------------------------------------------------------------
# 3. Pacotes base (espera o lock do unattended-upgrades no primeiro boot)
# -----------------------------------------------------------------------------
wait_apt() {
  local n=0
  while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock >/dev/null 2>&1; do
    n=$((n+1)); [ $((n % 6)) -eq 0 ] && log "aguardando lock do apt..."
    sleep 10
  done
}
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
wait_apt; apt-get update -y
wait_apt; apt-get install -y iptables-persistent
netfilter-persistent save >/dev/null
if [ "$SKIP_UPGRADE" != "1" ]; then
  wait_apt; apt-get upgrade -y
fi
wait_apt; apt-get install -y nginx mysql-server ca-certificates curl gnupg dnsutils python3 unzip
systemctl enable --now nginx mysql >/dev/null

# -----------------------------------------------------------------------------
# 4. Node.js LTS (NodeSource) + Ghost-CLI
# -----------------------------------------------------------------------------
if ! command -v node >/dev/null 2>&1 || [ "$(node -v | sed 's/^v//' | cut -d. -f1)" != "$NODE_MAJOR" ]; then
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
  wait_apt; apt-get update -y
  wait_apt; apt-get install -y nodejs
fi
log "Node $(node -v), npm $(npm -v)"
npm install -g ghost-cli@latest >/dev/null 2>&1 || npm install -g ghost-cli@latest
log "Ghost-CLI $(ghost --version 2>/dev/null | head -1)"

# -----------------------------------------------------------------------------
# 5. MySQL 8: banco + usuario do Ghost. O root continua com auth_socket
#    ("sudo mysql" segue funcionando). caching_sha2_password e o padrao do MySQL 8.
# -----------------------------------------------------------------------------
mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
log "MySQL: banco $DB_NAME e usuario $DB_USER prontos"

# -----------------------------------------------------------------------------
# 6. Diretorio + "ghost install" nao-interativo (sem SSL por enquanto: o
#    certificado e emitido automaticamente quando o DNS apontar para a VM).
# -----------------------------------------------------------------------------
mkdir -p "$GHOST_DIR"
chown "$GHOST_USER":"$GHOST_USER" "$GHOST_DIR"
chmod 775 "$GHOST_DIR"

if [ ! -f "$GHOST_DIR/config.production.json" ]; then
  log "Executando ghost install (pode levar alguns minutos)"
  sudo -u "$GHOST_USER" -H bash -lc "cd '$GHOST_DIR' && ghost install \
    --url 'http://${DOMAIN}' \
    --db mysql --dbhost localhost --dbuser '${DB_USER}' --dbpass '${DB_PASS}' --dbname '${DB_NAME}' \
    --process systemd --setup-nginx --no-setup-ssl --no-prompt --start --dir '$GHOST_DIR'"
else
  log "Ghost ja instalado em $GHOST_DIR (config.production.json existe); pulando ghost install"
fi

# Sem o site default do nginx, o Ghost responde tambem pelo IP publico.
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# -----------------------------------------------------------------------------
# 7. SSL automatico: a cada 5 min verifica se DOMAIN resolve para o IP publico
#    desta VM; quando resolver, emite o certificado (Let's Encrypt via acme.sh
#    do ghost-cli), troca a URL para https e remove o cron.
# -----------------------------------------------------------------------------
cat > /usr/local/sbin/ghost-ssl-setup <<EOF
#!/usr/bin/env bash
# Gerado por install.sh (ghost-oci). Emite o certificado quando o DNS apontar para esta VM.
set -uo pipefail
DOMAIN="${DOMAIN}"; EMAIL="${EMAIL}"; GHOST_DIR="${GHOST_DIR}"; GHOST_USER="${GHOST_USER}"
LOG=/var/log/ghost-install.log
log() { echo "[\$(date '+%F %T')] ssl: \$*" >> "\$LOG"; }
[ -f "\$GHOST_DIR/system/files/\${DOMAIN}-ssl.conf" ] && { rm -f /etc/cron.d/ghost-ssl; exit 0; }
PUB_IP="\$(curl -sf -m 5 -H 'Authorization: Bearer Oracle' http://169.254.169.254/opc/v2/vnics/ \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[0].get("publicIp",""))' 2>/dev/null || true)"
[ -n "\$PUB_IP" ] || PUB_IP="\$(curl -sf -m 5 https://api.ipify.org || true)"
RESOLVED="\$(dig +short A "\$DOMAIN" @1.1.1.1 2>/dev/null | tail -1)"
if [ -z "\$PUB_IP" ] || [ "\$RESOLVED" != "\$PUB_IP" ]; then
  log "aguardando DNS: \$DOMAIN -> '\$RESOLVED' (IP desta VM: '\$PUB_IP')"
  exit 0
fi
log "DNS ok (\$DOMAIN -> \$PUB_IP); emitindo certificado Let's Encrypt"
if sudo -u "\$GHOST_USER" -H bash -lc "cd '\$GHOST_DIR' && ghost setup ssl --sslemail '\$EMAIL' --no-prompt" \
   && sudo -u "\$GHOST_USER" -H bash -lc "cd '\$GHOST_DIR' && ghost config url 'https://\$DOMAIN' && ghost restart"; then
  rm -f /etc/cron.d/ghost-ssl
  log "HTTPS ativo em https://\$DOMAIN"
else
  log "falha ao emitir o certificado; nova tentativa em 5 min"
fi
EOF
chmod 755 /usr/local/sbin/ghost-ssl-setup
echo "*/5 * * * * root /usr/local/sbin/ghost-ssl-setup" > /etc/cron.d/ghost-ssl
chmod 644 /etc/cron.d/ghost-ssl
/usr/local/sbin/ghost-ssl-setup || true

# -----------------------------------------------------------------------------
# 8. Backup diario (banco + conteudo) em /var/backups/ghost, 14 dias de retencao
# -----------------------------------------------------------------------------
for s in backup restore; do
  if curl -fsSL -m 20 "$REPO_RAW/$s.sh" -o "/usr/local/sbin/ghost-$s.tmp"; then
    mv "/usr/local/sbin/ghost-$s.tmp" "/usr/local/sbin/ghost-$s"; chmod 755 "/usr/local/sbin/ghost-$s"
    log "instalado /usr/local/sbin/ghost-$s"
  else
    rm -f "/usr/local/sbin/ghost-$s.tmp"; log "aviso: nao foi possivel baixar $s.sh de $REPO_RAW"
  fi
done
if [ -x /usr/local/sbin/ghost-backup ]; then
  cat > /etc/cron.d/ghost-backup <<EOF
# Backup diario do Ghost (banco + content). Ajuste GHOST_DIR/KEEP_DAYS/BACKUP_DIR se precisar.
GHOST_DIR=${GHOST_DIR}
0 3 * * * root /usr/local/sbin/ghost-backup >> /var/log/ghost-backup.log 2>&1
EOF
  chmod 644 /etc/cron.d/ghost-backup
fi

# -----------------------------------------------------------------------------
# 9. Resumo
# -----------------------------------------------------------------------------
PUB_IP="$(curl -sf -m 5 -H 'Authorization: Bearer Oracle' http://169.254.169.254/opc/v2/vnics/ \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[0].get("publicIp",""))' 2>/dev/null || true)"
cat <<TXT

============================================================
 Ghost instalado.
   IP publico desta VM : ${PUB_IP:-desconhecido}
   Site                : http://${DOMAIN}  (https automatico quando o DNS apontar para o IP)
   Painel admin        : http://${DOMAIN}/ghost  -> crie a conta de administrador
   Credenciais         : ${CRED_FILE}
   Log                 : ${LOG}
   Backup diario       : /usr/local/sbin/ghost-backup (03:00) -> /var/backups/ghost

 Pendencias fora da VM:
   1. DNS: registro A de ${DOMAIN} (e www) -> ${PUB_IP:-IP-PUBLICO}, sem proxy.
   2. OCI: Security List da sub-rede com ingress TCP 80 e 443 de 0.0.0.0/0.
============================================================
TXT
