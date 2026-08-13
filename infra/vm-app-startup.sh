#!/bin/bash
# =============================================================================
#  VM de aplicacao - subnet publica, com IP externo
#
#  Startup script do Compute Engine. Prepara o servidor: runtime .NET, Nginx
#  como proxy reverso e a unidade systemd que mantem a aplicacao no ar.
#
#  NAO publica o codigo - isso e feito depois pelo infra.ps1, que envia os
#  fontes da maquina local e chama /opt/estetica/publicar.sh.
#
#  Acompanhe com:  sudo journalctl -u google-startup-scripts -f
# =============================================================================
set -euo pipefail

log() { echo "[estetica-app] $*"; }

MARCADOR=/var/lib/estetica-app-configurado
if [ -f "$MARCADOR" ]; then
    log "ja configurado anteriormente - nada a fazer"
    exit 0
fi

meta() {
    curl -sf -H "Metadata-Flavor: Google" \
        "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1"
}

DOTNET_CANAL="$(meta dotnet-channel)"

log "aguardando a rede ficar disponivel"
until ping -c1 -W2 metadata.google.internal >/dev/null 2>&1; do sleep 2; done

# -----------------------------------------------------------------------------
# Swap: a e2-micro tem 1 GB de RAM, e o "dotnet publish" (compilacao, nao apenas
# execucao) passa disso com folga. Sem swap o build morre no OOM killer.
# -----------------------------------------------------------------------------
if [ ! -f /swapfile ]; then
    log "criando swap de 2 GB"
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx curl ca-certificates libicu-dev

# -----------------------------------------------------------------------------
# .NET via script oficial da Microsoft, e nao via apt: os repositorios do Ubuntu
# costumam estar varias versoes atras, e o projeto exige net10.0 exato.
# Instala o SDK porque a publicacao (dotnet publish) acontece na propria VM.
# -----------------------------------------------------------------------------
log "instalando o SDK .NET (canal $DOTNET_CANAL)"
curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
chmod +x /tmp/dotnet-install.sh
/tmp/dotnet-install.sh --channel "$DOTNET_CANAL" --install-dir /usr/share/dotnet
ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
dotnet --info | head -n 5

# Usuario de servico sem shell e sem home: se a aplicacao for comprometida,
# o atacante nao ganha um login utilizavel na maquina.
if ! id estetica >/dev/null 2>&1; then
    log "criando usuario de servico"
    useradd --system --no-create-home --shell /usr/sbin/nologin estetica
fi

mkdir -p /opt/estetica/fonte /opt/estetica/publish
chown -R estetica:estetica /opt/estetica

# -----------------------------------------------------------------------------
# Nginx como proxy reverso: o Kestrel escuta apenas em 127.0.0.1:5000 e nunca
# fica exposto diretamente. O Nginx trata a porta 80 e repassa os cabecalhos
# de origem, que o UseForwardedHeaders da aplicacao le.
# -----------------------------------------------------------------------------
log "configurando o Nginx"
cat > /etc/nginx/sites-available/estetica <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location / {
        proxy_pass         http://127.0.0.1:5000;
        proxy_http_version 1.1;

        proxy_set_header Upgrade           $http_upgrade;
        proxy_set_header Connection        keep-alive;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 120s;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/estetica /etc/nginx/sites-enabled/estetica
nginx -t
systemctl restart nginx
systemctl enable nginx

# -----------------------------------------------------------------------------
# systemd mantem a aplicacao rodando e a religa em caso de falha ou reboot.
# As variaveis sensiveis ficam em /etc/estetica.env (modo 600), fora da unidade,
# porque o conteudo de unidades systemd e legivel por qualquer usuario.
# -----------------------------------------------------------------------------
log "criando o servico systemd"
cat > /etc/systemd/system/estetica.service <<'EOF'
[Unit]
Description=Estetica Por Do Sol - aplicacao ASP.NET Core
After=network.target

[Service]
WorkingDirectory=/opt/estetica/publish
ExecStart=/usr/bin/dotnet /opt/estetica/publish/EsteticaPorDoSol.dll
Restart=always
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=estetica
User=estetica
EnvironmentFile=/etc/estetica.env

[Install]
WantedBy=multi-user.target
EOF

touch /etc/estetica.env
chmod 600 /etc/estetica.env
systemctl daemon-reload
systemctl enable estetica

# -----------------------------------------------------------------------------
# Script de publicacao, chamado remotamente pelo infra.ps1 apos o envio dos
# fontes. Fica na VM para que uma republicacao seja um unico comando SSH.
# -----------------------------------------------------------------------------
cat > /opt/estetica/publicar.sh <<'EOF'
#!/bin/bash
set -euo pipefail
echo "[publicar] compilando"
cd /opt/estetica/fonte
dotnet publish -c Release -o /opt/estetica/publish
chown -R estetica:estetica /opt/estetica/publish
echo "[publicar] reiniciando o servico"
systemctl restart estetica
sleep 5
systemctl is-active --quiet estetica && echo "[publicar] servico ativo" \
    || { echo "[publicar] FALHOU - ultimos logs:"; journalctl -u estetica -n 40 --no-pager; exit 1; }
EOF
chmod +x /opt/estetica/publicar.sh

touch "$MARCADOR"
log "servidor preparado - aguardando o envio do codigo"
