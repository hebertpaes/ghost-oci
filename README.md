# Ghost na Oracle Cloud (OCI) em um unico comando

Instala o [Ghost](https://docs.ghost.org/install/ubuntu) (CMS/blog) em uma VM Ubuntu 22.04/24.04 na Oracle Cloud Infrastructure seguindo a documentacao oficial: Nginx, MySQL 8, Node.js 22 LTS, Ghost-CLI, servico systemd, HTTPS automatico (Let's Encrypt) e backup diario.

Feito para `comenta.com.br`, mas serve para qualquer dominio: tudo e parametrizado por variaveis de ambiente.

## Instalacao em um comando

Na VM (Ubuntu), como root:

```bash
curl -fsSL https://raw.githubusercontent.com/hebertpaes/ghost-oci/main/install.sh \
  | sudo DOMAIN=comenta.com.br EMAIL=contato@comenta.com.br bash
```

Ao terminar (10 a 20 min) o Ghost responde em `http://IP-DA-VM` e em `http://SEU-DOMINIO`. Abra `http://SEU-DOMINIO/ghost` para criar a conta de administrador. O certificado HTTPS e emitido sozinho assim que o DNS apontar para a VM (ver [HTTPS automatico](#https-automatico)).

Acompanhe pelo log:

```bash
sudo tail -f /var/log/ghost-install.log
```

### Variaveis

| Variavel | Padrao | Descricao |
|---|---|---|
| `DOMAIN` | obrigatoria | Dominio do site, ex. `comenta.com.br` |
| `EMAIL` | `admin@DOMAIN` | E-mail da conta Let's Encrypt (avisos de expiracao) |
| `GHOST_DIR` | `/var/www/ghost` | Pasta da instalacao |
| `GHOST_USER` | `ubuntu` | Usuario nao-root dono do Ghost (criado se nao existir) |
| `DB_NAME` / `DB_USER` | `ghost_prod` / `ghost` | Banco e usuario MySQL |
| `DB_PASS` | gerada | Senha do MySQL (fica em `/root/ghost-credentials.txt`) |
| `NODE_MAJOR` | `22` | Versao do Node.js |
| `SKIP_UPGRADE` | `0` | `1` pula o `apt-get upgrade` |

O script e idempotente: se algo falhar no meio (rede, lock do apt), rode o mesmo comando de novo. Ele nao duplica regras de firewall, reaproveita a senha ja gerada e pula o `ghost install` se ja existir.

## Criar a VM na OCI (console web)

Testado com **VM.Standard.E5.Flex (AMD), 1 OCPU, 12 GB**, Ubuntu 24.04, regiao Brazil East (Sao Paulo). Esse shape nao e "Always Free" (custa cerca de US$ 0,04/hora); a alternativa gratuita e o shape ARM **VM.Standard.A1.Flex** (ate 4 OCPU / 24 GB no Always Free), que tambem funciona com este script.

1. **Rede antes da VM.** Networking > Virtual cloud networks > **Start VCN Wizard > Create VCN with Internet Connectivity**. O assistente cria VCN, sub-rede publica, Internet Gateway e rotas.
   Criar a VCN "inline" no formulario da instancia deixa o toggle de IP publico desativado; por isso a VCN vem primeiro.
2. Na VCN criada: **Security > Default Security List > Add Ingress Rules**: origem `0.0.0.0/0`, protocolo TCP, portas de destino `80,443`. (Veja [Permissoes necessarias](#permissoes-necessarias).)
3. Compute > Instances > **Create instance**:
   - Image: **Canonical Ubuntu 24.04**. Shape: **AMD > VM.Standard.E5.Flex** (1 OCPU / 12 GB).
   - Basic information > **Advanced options > Management > Initialization script > Paste cloud-init script**: cole o conteudo de [`cloud-init.example.sh`](cloud-init.example.sh) com o seu `DOMAIN` e `EMAIL`. A VM instala tudo sozinha no primeiro boot.
   - Networking: **Select existing VCN** > a VCN do passo 1 > sub-rede **publica**; confira que **Automatically assign public IPv4 address** esta ligado.
   - SSH keys: **Paste public key** com a sua chave (`ssh-keygen -t ed25519`).
   - Storage: o boot volume padrao (46,6 GB) e suficiente.
4. **Create**. Quando ficar `Running`, copie o **Public IPv4 address**.
5. DNS: registro **A** de `SEU-DOMINIO` (e `www`) apontando para esse IP.

Sem cloud-init, basta entrar por SSH depois que a VM subir e rodar o comando da secao anterior:

```bash
ssh -i ~/.ssh/sua-chave ubuntu@IP-DA-VM
```

## Permissoes necessarias

### 1. OCI IAM (quem cria a VM)

Administrador do tenancy ja tem tudo. Para um usuario/grupo restrito, a policy minima no compartimento e:

```text
Allow group ghost-admins to manage instance-family in compartment <nome>
Allow group ghost-admins to manage virtual-network-family in compartment <nome>
Allow group ghost-admins to manage volume-family in compartment <nome>
Allow group ghost-admins to read app-catalog-listing in tenancy
Allow group ghost-admins to use tag-namespaces in tenancy
```

### 2. Security List da sub-rede (firewall da nuvem)

Por padrao a OCI so libera SSH (22). Sem estas regras o site nao abre e o Let's Encrypt (porta 80) falha:

| Direcao | Origem | Protocolo | Porta destino | Uso |
|---|---|---|---|---|
| Ingress | `0.0.0.0/0` | TCP | 80 | HTTP e validacao do certificado |
| Ingress | `0.0.0.0/0` | TCP | 443 | HTTPS |
| Ingress | seu IP ou `0.0.0.0/0` | TCP | 22 | SSH (ja existe) |

Se usar Network Security Groups (NSG) no lugar da Security List, as regras sao as mesmas.

### 3. Firewall dentro da VM

As imagens Ubuntu da Oracle vem com `iptables` bloqueando tudo exceto 22. O `install.sh` insere as regras de 80/443 antes da regra `REJECT` e salva com `netfilter-persistent`. **Nao use `ufw` nessas imagens**: a Oracle documenta que ele pode apagar as regras iSCSI e a VM deixa de iniciar.

### 4. Usuario do sistema e sudo

O Ghost-CLI se recusa a rodar como root. O script usa o usuario `ubuntu` (ou `GHOST_USER`), que precisa de `sudo` sem senha (`/etc/sudoers.d/90-ubuntu`). O proprio Ghost roda sob o usuario de sistema `ghost`, criado pelo Ghost-CLI para o servico systemd.

### 5. Arquivos

| Caminho | Dono | Modo |
|---|---|---|
| `/var/www/ghost` | `ubuntu:ubuntu` | `775` |
| `/var/www/ghost/content` | `ghost:ghost` (ajustado pelo Ghost-CLI) | `775` |
| `/root/ghost-credentials.txt` | `root` | `600` |
| `/var/backups/ghost` | `root` | `700` |

### 6. MySQL

O usuario `root` do MySQL continua com autenticacao por socket (`sudo mysql` funciona, sem senha). O Ghost usa o usuario `ghost` com privilegios apenas no banco `ghost_prod`.

### 7. DNS (Cloudflare ou outro)

- Registro **A** para o dominio raiz e para `www` apontando para o IP publico da VM.
- No Cloudflare, deixe o **proxy desligado (DNS only, nuvem cinza)** ate o certificado ser emitido; o script compara o IP resolvido com o IP da VM e, com o proxy ligado, ele ve os IPs do Cloudflare. Depois do HTTPS ativo voce pode ligar o proxy com SSL/TLS em **Full (strict)**.
- O dominio precisa estar ativo no registrador (no registro.br, um dominio vencido fica `on-hold` e some do DNS ate ser renovado).

## HTTPS automatico

`install.sh` instala o Ghost em `http://DOMAIN` e agenda `/usr/local/sbin/ghost-ssl-setup` a cada 5 minutos (`/etc/cron.d/ghost-ssl`). Quando `dig A DOMAIN` (via 1.1.1.1) devolver o IP publico da VM, ele executa:

```bash
ghost setup ssl --sslemail EMAIL --no-prompt
ghost config url https://DOMAIN
ghost restart
```

e remove o cron. A renovacao do certificado fica por conta do `acme.sh` instalado pelo Ghost-CLI. Para forcar manualmente:

```bash
sudo /usr/local/sbin/ghost-ssl-setup && sudo tail -n 5 /var/log/ghost-install.log
```

## Backup e restauracao

`install.sh` instala [`backup.sh`](backup.sh) como `/usr/local/sbin/ghost-backup` e agenda todo dia as 03:00 (`/etc/cron.d/ghost-backup`). Cada backup e um `.tar.gz` com o dump do MySQL, a pasta `content/` (imagens, temas, uploads) e o `config.production.json`, guardado em `/var/backups/ghost` por 14 dias.

```bash
sudo ghost-backup                                   # backup agora
ls -lh /var/backups/ghost                           # listar
sudo RCLONE_REMOTE=oci:ghost-backups ghost-backup   # copiar tambem para um bucket (rclone configurado)
```

Para guardar fora da VM, configure o `rclone` (OCI Object Storage, S3, Google Drive) e defina `RCLONE_REMOTE` no `/etc/cron.d/ghost-backup`.

Restaurar (substitui banco e `content/` da VM; pede confirmacao):

```bash
sudo ghost-restore /var/backups/ghost/ghost-AAAAMMDD-HHMMSS.tar.gz
```

Migrar para outra VM: rode o `install.sh` na VM nova, copie o `.tar.gz` (`scp`) e execute `ghost-restore` la.

## Comandos uteis

```bash
sudo cat /root/ghost-credentials.txt                  # senhas e caminhos
cd /var/www/ghost && ghost status                     # estado do servico
cd /var/www/ghost && ghost log                        # logs do Ghost
cd /var/www/ghost && ghost update                     # atualizar o Ghost
cd /var/www/ghost && ghost restart
sudo iptables -L INPUT -n --line-numbers              # firewall da VM
sudo nginx -t && sudo systemctl reload nginx
```

## Solucao de problemas

- **Site nao abre pelo IP**: confira a Security List (80/443) e `sudo iptables -L INPUT -n`. Teste local na VM: `curl -I http://127.0.0.1`.
- **Instalacao parece parada**: `sudo tail -f /var/log/ghost-install.log`. No primeiro boot o `apt` pode esperar o `unattended-upgrades` liberar o lock por alguns minutos.
- **HTTPS nao ativou**: `dig +short A SEU-DOMINIO @1.1.1.1` precisa devolver o IP da VM (proxy do Cloudflare desligado, dominio ativo). Veja as linhas `ssl:` no log.
- **`ghost install` falhou**: corrija a causa mostrada no log e rode o `install.sh` de novo; ou `cd /var/www/ghost && ghost doctor`.
- **MySQL**: `sudo mysql -e "SHOW DATABASES;"` funciona como root sem senha (auth_socket).

## Custos (referencia)

| Item | Valor aproximado |
|---|---|
| VM.Standard.E5.Flex 1 OCPU / 12 GB | ~US$ 0,04/h (~US$ 31/mes) |
| Boot volume 47 GB | ~US$ 1,20/mes |
| VM.Standard.A1.Flex ate 4 OCPU / 24 GB | Always Free |
| Trafego de saida | 10 TB/mes gratis |

## Arquivos

| Arquivo | Funcao |
|---|---|
| [`install.sh`](install.sh) | Instalador completo (um comando) |
| [`cloud-init.example.sh`](cloud-init.example.sh) | Script de inicializacao para colar no console da OCI |
| [`backup.sh`](backup.sh) | Backup do banco + conteudo (instalado como `ghost-backup`) |
| [`restore.sh`](restore.sh) | Restauracao de um backup (instalado como `ghost-restore`) |

Licenca MIT.
