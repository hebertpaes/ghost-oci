#!/usr/bin/env bash
# =============================================================================
#  Script de inicializacao (cloud-init) para a VM na Oracle Cloud.
#
#  Onde colar: Compute -> Instances -> Create instance -> secao "Basic
#  information" -> Advanced options -> Management -> Initialization script
#  -> "Paste cloud-init script".
#
#  Roda como root no primeiro boot. Ajuste DOMAIN e EMAIL. Acompanhe o
#  progresso pela VM com:  sudo tail -f /var/log/ghost-install.log
#  (a instalacao leva de 10 a 20 minutos; o "apt upgrade" pode esperar o
#  unattended-upgrades terminar).
# =============================================================================
export DOMAIN="comenta.com.br"
export EMAIL="contato@comenta.com.br"

curl -fsSL https://raw.githubusercontent.com/hebertpaes/ghost-oci/main/install.sh | bash
