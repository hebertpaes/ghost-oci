#!/usr/bin/env bash
# =============================================================================
#  Cria a VM do Ghost na Oracle Cloud (OCI) em um unico comando, usando a OCI
#  CLI. Feito para rodar no Cloud Shell do console (ja autenticado) ou em
#  qualquer maquina com a OCI CLI configurada (~/.oci/config).
#
#  Uso (Cloud Shell, regiao selecionada no console):
#    curl -fsSL https://raw.githubusercontent.com/hebertpaes/ghost-oci/main/oci-launch.sh \
#      | bash -s -- comenta.hebertpaes.com.br contato@exemplo.com
#
#  O que faz (idempotente: pode rodar de novo):
#    1. localiza a VCN (VCN_NAME) e a sub-rede publica dela;
#    2. cria (ou reaproveita) o Network Security Group "ghost-web" liberando
#       TCP 80 e 443 de 0.0.0.0/0;
#    3. cria (ou reaproveita) a instancia NAME com Ubuntu 24.04, chave SSH e
#       cloud-init que baixa e executa o install.sh deste repositorio;
#    4. espera ficar RUNNING e imprime o IP publico.
#
#  Variaveis (opcionais):
#    NAME            nome da instancia            (padrao: ghost-comenta)
#    VCN_NAME        nome da VCN existente        (padrao: vcn-ghost)
#    SHAPE           shape                        (padrao: VM.Standard.E5.Flex)
#    OCPUS / MEM_GB  tamanho                      (padrao: 1 / 12)
#    OS_VERSION      versao do Ubuntu             (padrao: 24.04)
#    AD              availability domain          (padrao: o primeiro)
#    COMPARTMENT_ID  OCID do compartimento        (padrao: tenancy/root)
#    REGION          regiao                       (padrao: a da sessao/config)
#    SSH_PUB         chave publica SSH            (padrao: authorized_keys do repo)
#    REPO_RAW        base dos scripts             (padrao: este repositorio no GitHub)
# =============================================================================
set -euo pipefail

DOMAIN="${1:-${DOMAIN:-}}"
[ -n "$DOMAIN" ] || { echo "uso: oci-launch.sh DOMINIO [EMAIL]"; exit 1; }
[[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "dominio invalido: $DOMAIN"; exit 1; }
EMAIL="${2:-${EMAIL:-admin@$DOMAIN}}"
[[ "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$ ]] || { echo "e-mail invalido: $EMAIL"; exit 1; }

NAME="${NAME:-ghost-comenta}"
VCN_NAME="${VCN_NAME:-vcn-ghost}"
SHAPE="${SHAPE:-VM.Standard.E5.Flex}"
OCPUS="${OCPUS:-1}"; MEM_GB="${MEM_GB:-12}"
OS_VERSION="${OS_VERSION:-24.04}"
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/hebertpaes/ghost-oci/main}"
REGION="${REGION:-}"

command -v oci >/dev/null || { echo "OCI CLI nao encontrada (use o Cloud Shell do console)"; exit 1; }
command -v jq  >/dev/null || { echo "jq nao encontrado"; exit 1; }
oci() { command oci ${REGION:+--region "$REGION"} "$@"; }
log() { echo "[$(date '+%H:%M:%S')] $*"; }

C="${COMPARTMENT_ID:-${OCI_TENANCY:-}}"
[ -n "$C" ] || C="$(sed -n 's/^tenancy *= *//p' ~/.oci/config 2>/dev/null | head -1)"
[ -n "$C" ] || { echo "Defina COMPARTMENT_ID (OCID do compartimento)"; exit 1; }

SSH_PUB="${SSH_PUB:-}"
[ -n "$SSH_PUB" ] || SSH_PUB="$(curl -fsSL "$REPO_RAW/authorized_keys" | grep -m1 '^ssh-' || true)"
[ -n "$SSH_PUB" ] || { echo "Defina SSH_PUB='ssh-ed25519 AAAA...' (chave publica)"; exit 1; }

log "compartimento=$C regiao=${REGION:-sessao} instancia=$NAME dominio=$DOMAIN"

# 1. Rede ------------------------------------------------------------------
VCN="$(oci network vcn list --compartment-id "$C" --display-name "$VCN_NAME" --lifecycle-state AVAILABLE \
        --query 'data[0].id' --raw-output 2>/dev/null || true)"
[ -n "$VCN" ] && [ "$VCN" != "null" ] || { echo "VCN '$VCN_NAME' nao encontrada. Crie com Networking > Start VCN Wizard."; exit 1; }
SUBNET="$(oci network subnet list --compartment-id "$C" --vcn-id "$VCN" --lifecycle-state AVAILABLE \
        --query 'data[?"prohibit-public-ip-on-vnic"==`false`] | [0].id' --raw-output)"
[ -n "$SUBNET" ] && [ "$SUBNET" != "null" ] || { echo "Nenhuma sub-rede publica na VCN $VCN_NAME"; exit 1; }
log "vcn=$VCN"
log "subnet publica=$SUBNET"

# 2. NSG com 80/443 ----------------------------------------------------------
NSG="$(oci network nsg list --compartment-id "$C" --vcn-id "$VCN" --display-name ghost-web --lifecycle-state AVAILABLE \
        --query 'data[0].id' --raw-output 2>/dev/null || true)"
if [ -z "$NSG" ] || [ "$NSG" = "null" ]; then
  NSG="$(oci network nsg create --compartment-id "$C" --vcn-id "$VCN" --display-name ghost-web \
          --wait-for-state AVAILABLE --query data.id --raw-output)"
  oci network nsg rules add --nsg-id "$NSG" --security-rules '[
    {"direction":"INGRESS","protocol":"6","source":"0.0.0.0/0","sourceType":"CIDR_BLOCK","isStateless":false,
     "description":"HTTP","tcpOptions":{"destinationPortRange":{"min":80,"max":80}}},
    {"direction":"INGRESS","protocol":"6","source":"0.0.0.0/0","sourceType":"CIDR_BLOCK","isStateless":false,
     "description":"HTTPS","tcpOptions":{"destinationPortRange":{"min":443,"max":443}}}]' >/dev/null
  log "NSG ghost-web criado com ingress TCP 80/443"
else
  log "NSG ghost-web ja existe: $NSG"
fi

# 3. Instancia ---------------------------------------------------------------
ID="$(oci compute instance list --compartment-id "$C" --display-name "$NAME" \
       --query 'data[?"lifecycle-state"!=`TERMINATED` && "lifecycle-state"!=`TERMINATING`] | [0].id' --raw-output 2>/dev/null || true)"
if [ -n "$ID" ] && [ "$ID" != "null" ]; then
  log "instancia $NAME ja existe: $ID"
else
  AD="${AD:-$(oci iam availability-domain list --compartment-id "$C" --query 'data[0].name' --raw-output)}"
  IMG="$(oci compute image list --compartment-id "$C" --operating-system "Canonical Ubuntu" \
          --operating-system-version "$OS_VERSION" --shape "$SHAPE" --sort-by TIMECREATED --sort-order DESC \
          --query 'data[0].id' --raw-output)"
  [ -n "$IMG" ] && [ "$IMG" != "null" ] || { echo "Imagem Ubuntu $OS_VERSION nao encontrada para $SHAPE"; exit 1; }
  log "ad=$AD"
  log "imagem=$IMG"

  USER_DATA="$(printf '#!/bin/bash\nexport DOMAIN="%s" EMAIL="%s"\nfor i in 1 2 3 4 5 6; do curl -fsSL "%s/install.sh" -o /root/install.sh && break; sleep 10; done\nbash /root/install.sh\n' \
                "$DOMAIN" "$EMAIL" "$REPO_RAW" | base64 | tr -d '\n')"
  META="$(jq -cn --arg k "$SSH_PUB" --arg u "$USER_DATA" '{ssh_authorized_keys:$k, user_data:$u}')"

  log "criando instancia $NAME ($SHAPE ${OCPUS} OCPU / ${MEM_GB} GB)..."
  ID="$(oci compute instance launch --compartment-id "$C" --availability-domain "$AD" \
          --display-name "$NAME" --shape "$SHAPE" \
          --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEM_GB}" \
          --image-id "$IMG" --subnet-id "$SUBNET" --assign-public-ip true \
          --nsg-ids "[\"$NSG\"]" --metadata "$META" \
          --query data.id --raw-output)"
  log "instancia=$ID"
fi

# 4. Espera RUNNING e pega o IP ------------------------------------------------
for _ in $(seq 1 60); do
  STATE="$(oci compute instance get --instance-id "$ID" --query 'data."lifecycle-state"' --raw-output)"
  [ "$STATE" = "RUNNING" ] && break
  log "estado: $STATE (aguardando)"; sleep 10
done
IP=""
for _ in $(seq 1 30); do
  IP="$(oci compute instance list-vnics --instance-id "$ID" --query 'data[0]."public-ip"' --raw-output 2>/dev/null || true)"
  [ -n "$IP" ] && [ "$IP" != "null" ] && break
  sleep 5
done

cat <<TXT
============================================================
 Instancia : $NAME  ($STATE)
 IP publico: ${IP:-nao atribuido}
 SSH       : ssh ubuntu@${IP:-IP}   (chave: a de authorized_keys / SSH_PUB)
 Log       : sudo tail -f /var/log/ghost-install.log  (10 a 20 min)
 DNS       : registro A ${DOMAIN} -> ${IP:-IP} (sem proxy)
 Site      : http://${DOMAIN}  -> https automatico quando o DNS apontar
============================================================
TXT
