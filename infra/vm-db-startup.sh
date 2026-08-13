#!/bin/bash
# =============================================================================
#  VM de banco de dados - subnet privada, sem IP externo
#
#  Executado automaticamente pelo Compute Engine como startup script na
#  primeira inicializacao da VM. Instala e configura o MySQL 8 na mao.
#
#  Parametros chegam por metadados da instancia (definidos pelo infra.ps1).
#  A saida vai para /var/log/syslog e pode ser lida com:
#      sudo journalctl -u google-startup-scripts -f
# =============================================================================
set -euo pipefail

log() { echo "[estetica-db] $*"; }

# Marcador de idempotencia: o startup script roda a cada boot da VM, e sem isso
# a configuracao seria refeita (e a senha resetada) a cada reinicializacao.
MARCADOR=/var/lib/estetica-db-configurado
if [ -f "$MARCADOR" ]; then
    log "ja configurado anteriormente - nada a fazer"
    exit 0
fi

meta() {
    curl -sf -H "Metadata-Flavor: Google" \
        "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1"
}

DB_NAME="$(meta db-name)"
DB_USER="$(meta db-user)"
DB_PASS="$(meta db-password)"
# Padrao de host no formato do MySQL (ex: 10.10.1.%). CIDR como 10.10.1.0/24
# NAO e aceito pelo MySQL na definicao de usuario.
HOST_APP="$(meta db-host-pattern)"

log "aguardando a rede ficar disponivel"
until ping -c1 -W2 metadata.google.internal >/dev/null 2>&1; do sleep 2; done

# -----------------------------------------------------------------------------
# Swap: a e2-micro tem 1 GB de RAM e o MySQL 8 sozinho ja encosta nesse limite.
# Sem swap o servico e morto pelo OOM killer durante o primeiro import.
# -----------------------------------------------------------------------------
if [ ! -f /swapfile ]; then
    log "criando swap de 2 GB"
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

log "instalando o MySQL 8"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y mysql-server

# -----------------------------------------------------------------------------
# Por padrao o MySQL escuta apenas em 127.0.0.1. Precisa aceitar conexoes da
# subnet publica. A protecao de rede fica na regra de firewall da VPC, que
# libera a porta 3306 exclusivamente para instancias com a tag "app".
# -----------------------------------------------------------------------------
log "liberando escuta na rede interna"
cat > /etc/mysql/mysql.conf.d/estetica.cnf <<EOF
[mysqld]
bind-address = 0.0.0.0
# Ajuste para caber com folga em 1 GB de RAM (padrao seria 128 MB + overhead)
innodb_buffer_pool_size = 96M
max_connections = 50
EOF

systemctl restart mysql
systemctl enable mysql

log "criando database e usuario da aplicacao"
mysql <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
    CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

-- O host e restrito a faixa da subnet publica: mesmo que a regra de firewall
-- fosse afrouxada, o MySQL so aceita este usuario vindo da camada de aplicacao.
CREATE USER IF NOT EXISTS '${DB_USER}'@'${HOST_APP}' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'${HOST_APP}' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${HOST_APP}';
FLUSH PRIVILEGES;
EOF

touch "$MARCADOR"
log "configuracao concluida"
