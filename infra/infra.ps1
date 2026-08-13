#Requires -Version 5.1
<#
.SYNOPSIS
    Provisiona a infraestrutura IaaS do EsteticaPorDoSol no Google Cloud:
    VPC propria, duas subnets, regras de firewall, Cloud NAT e duas VMs.

.DESCRIPTION
    Arquitetura criada (equivalentes AWS entre parenteses):

        Internet
           |  :80
        +--|------------------------------------------+
        |  VPC estetica-vpc  (VPC)                    |
        |  v                                          |
        |  subnet-publica  10.10.1.0/24  (subnet)     |
        |    vm-app   e2-micro, IP externo  (EC2)     |
        |    Nginx :80 -> Kestrel 127.0.0.1:5000      |
        |    systemd mantem o processo no ar          |
        |         |  :3306                            |
        |  subnet-privada  10.10.2.0/24               |
        |    vm-db    e2-micro, SEM IP externo        |
        |    MySQL 8 instalado e configurado na mao   |
        |                                             |
        |  Cloud Router + Cloud NAT (NAT Gateway)     |
        |  Firewall por tags        (security group)  |
        +---------------------------------------------+

    O script e idempotente: rode quantas vezes precisar. Recursos existentes
    sao preservados; apenas o que falta e criado.

.PARAMETER SomenteApp
    Pula a infraestrutura e apenas reenvia o codigo e republica na vm-app.
    Use depois de alterar a aplicacao.

.PARAMETER Destruir
    Remove tudo o que este script cria, na ordem correta de dependencias.

.EXAMPLE
    .\infra.ps1
.EXAMPLE
    .\infra.ps1 -SomenteApp
.EXAMPLE
    .\infra.ps1 -Destruir
#>
[CmdletBinding()]
param(
    [string] $ProjectId    = "estetica-por-do-sol",
    [string] $Region       = "southamerica-east1",
    [string] $Zone         = "southamerica-east1-a",

    [string] $Vpc          = "estetica-vpc",
    [string] $SubnetPub    = "subnet-publica",
    [string] $SubnetPriv   = "subnet-privada",
    [string] $CidrPub      = "10.10.1.0/24",
    [string] $CidrPriv     = "10.10.2.0/24",

    [string] $VmApp        = "vm-app",
    [string] $VmDb         = "vm-db",
    [string] $TipoMaquina  = "e2-micro",

    [string] $DbName       = "DbEsteticaPorDoSol",
    [string] $DbUser       = "estetica_app",
    [string] $SecretSenha  = "estetica-db-senha",
    [string] $DotnetCanal  = "10.0",

    [switch] $SomenteApp,
    [switch] $Destruir
)

# Ver DEPLOY.md: com "Stop", o stderr do gcloud (que carrega mensagens de
# progresso, nao so erros) vira erro fatal e derruba o script no meio de
# comandos bem-sucedidos. Cada chamada tem o exit code conferido a mao.
$ErrorActionPreference = "Continue"

$script:Passo = 0
$script:Total = if ($Destruir) { 2 } elseif ($SomenteApp) { 4 } else { 10 }

$script:Gcloud = $null
foreach ($c in @("gcloud.cmd", "gcloud")) {
    $achado = Get-Command $c -ErrorAction SilentlyContinue |
              Where-Object { $_.CommandType -eq "Application" } | Select-Object -First 1
    if ($null -ne $achado) { $script:Gcloud = $achado.Source; break }
}

$RaizInfra   = $PSScriptRoot
$RaizProjeto = Split-Path $RaizInfra -Parent

# ----------------------------------------------------------------- utilitarios

function Write-Passo {
    param([string] $T)
    $script:Passo++
    Write-Host ""
    Write-Host "[$script:Passo/$script:Total] $T" -ForegroundColor Cyan
}
function Write-Ok    { param([string] $T) Write-Host "      OK   $T" -ForegroundColor Green }
function Write-Info  { param([string] $T) Write-Host "      ..   $T" -ForegroundColor DarkGray }
function Write-Aviso { param([string] $T) Write-Host "      !    $T" -ForegroundColor Yellow }

function Stop-ComErro {
    param([string] $M)
    Write-Host ""
    Write-Host "ERRO: $M" -ForegroundColor Red
    Write-Host ""
    exit 1
}

function Ocultar-Segredos {
    param([string[]] $A)
    return $A | ForEach-Object {
        if ($_ -match '^(--metadata=.*db-password)=') { "--metadata=<omitido>" }
        elseif ($_ -match '(password|senha)=') { ($_ -replace '=(?<=password=|senha=).*', '=***') }
        else { $_ }
    }
}

function Invoke-Gcloud {
    param([Parameter(Mandatory=$true)][string[]] $A, [string] $AoFalhar = "")
    $saida = & $script:Gcloud @A 2>$null
    if ($LASTEXITCODE -ne 0) {
        if ([string]::IsNullOrWhiteSpace($AoFalhar)) {
            $AoFalhar = "falha ao executar: gcloud $((Ocultar-Segredos $A) -join ' ')"
        }
        Stop-ComErro $AoFalhar
    }
    if ($null -eq $saida) { return "" }
    return ($saida -join "`n").Trim()
}

# Consulta que pode legitimamente vir vazia (checagem de existencia).
function Get-Valor {
    param([Parameter(Mandatory=$true)][string[]] $A)
    $saida = & $script:Gcloud @A 2>$null
    if ($LASTEXITCODE -ne 0) { return "" }
    if ($null -eq $saida) { return "" }
    return ($saida -join "`n").Trim()
}

function Test-Existe {
    param([string[]] $A)
    return -not [string]::IsNullOrWhiteSpace((Get-Valor $A))
}

function New-Senha {
    param([int] $N = 28)
    $alf = [char[]]'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    $b = New-Object byte[] $N
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($b) } finally { $rng.Dispose() }
    return (-join ($b | ForEach-Object { $alf[$_ % $alf.Length] }))
}

# SSH/SCP sempre atraves do IAP: a vm-db nao tem IP externo, e o firewall so
# libera a porta 22 para a faixa do IAP (35.235.240.0/20), nunca para a internet.
# --quiet evita o prompt interativo de passphrase na geracao da chave SSH.
function Invoke-SshVm {
    param([string] $Vm, [string] $Comando, [switch] $Tolerante)
    $a = @("compute","ssh",$Vm,"--zone=$Zone","--project=$ProjectId",
           "--tunnel-through-iap","--quiet","--command=$Comando")
    $saida = & $script:Gcloud @a 2>$null
    if ($LASTEXITCODE -ne 0 -and -not $Tolerante) {
        Stop-ComErro "falha no SSH para '$Vm'. Verifique a regra de firewall do IAP e tente: gcloud compute ssh $Vm --zone=$Zone --tunnel-through-iap"
    }
    if ($null -eq $saida) { return "" }
    return ($saida -join "`n").Trim()
}

function Copy-ParaVm {
    param([string] $Origem, [string] $Destino, [string] $Vm, [switch] $Recursivo)
    $a = @("compute","scp")
    if ($Recursivo) { $a += "--recurse" }
    $a += @($Origem, "${Vm}:${Destino}", "--zone=$Zone", "--project=$ProjectId",
            "--tunnel-through-iap", "--quiet")
    & $script:Gcloud @a 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-ComErro "falha ao copiar '$Origem' para $Vm." }
}

# ------------------------------------------------------------------- cabecalho

Write-Host ""
Write-Host "=====================================================" -ForegroundColor White
Write-Host " Infraestrutura IaaS - EsteticaPorDoSol" -ForegroundColor White
Write-Host "=====================================================" -ForegroundColor White
Write-Host " Projeto : $ProjectId"
Write-Host " Regiao  : $Region  (zona $Zone)"
Write-Host " Rede    : $Vpc  |  $SubnetPub $CidrPub  |  $SubnetPriv $CidrPriv"
Write-Host " VMs     : $VmApp (publica) + $VmDb (privada) - $TipoMaquina"
Write-Host " Modo    : $(if ($Destruir) { 'DESTRUIR' } elseif ($SomenteApp) { 'somente aplicacao' } else { 'completo' })"
Write-Host "====================================================="

# ------------------------------------------------------- 1. pre-requisitos

Write-Passo "Verificando pre-requisitos"

if ([string]::IsNullOrWhiteSpace($script:Gcloud)) {
    Stop-ComErro "Google Cloud CLI nao encontrado. Instale e rode 'gcloud auth login'."
}
Write-Ok "gcloud: $script:Gcloud"

$conta = Get-Valor @("auth","list","--filter=status:ACTIVE","--format=value(account)")
if ([string]::IsNullOrWhiteSpace($conta)) { Stop-ComErro "Nenhuma conta autenticada. Rode: gcloud auth login" }
Write-Ok "autenticado como $conta"

if (-not (Test-Existe @("projects","list","--filter=projectId=$ProjectId","--format=value(projectId)"))) {
    Stop-ComErro "Projeto '$ProjectId' nao encontrado. Crie-o antes ou informe outro com -ProjectId."
}
Write-Ok "projeto '$ProjectId' encontrado"

# ============================================================================
#  MODO DESTRUIR
# ============================================================================
if ($Destruir) {
    Write-Passo "Removendo a infraestrutura"
    Write-Aviso "isto apaga as VMs e TODOS os dados do banco"

    # Ordem obrigatoria: instancias -> NAT/router -> firewall -> subnets -> VPC.
    # Inverter derruba o comando por dependencia ainda em uso.
    foreach ($vm in @($VmApp, $VmDb)) {
        if (Test-Existe @("compute","instances","list","--project=$ProjectId","--filter=name=$vm","--format=value(name)")) {
            Write-Info "apagando VM $vm"
            & $script:Gcloud compute instances delete $vm "--zone=$Zone" "--project=$ProjectId" --quiet 2>$null
        }
    }
    if (Test-Existe @("compute","routers","list","--project=$ProjectId","--filter=name=estetica-router","--format=value(name)")) {
        Write-Info "apagando Cloud Router e NAT"
        & $script:Gcloud compute routers delete estetica-router "--region=$Region" "--project=$ProjectId" --quiet 2>$null
    }
    foreach ($fw in @("estetica-allow-http","estetica-allow-ssh-iap","estetica-allow-mysql")) {
        if (Test-Existe @("compute","firewall-rules","list","--project=$ProjectId","--filter=name=$fw","--format=value(name)")) {
            Write-Info "apagando regra $fw"
            & $script:Gcloud compute firewall-rules delete $fw "--project=$ProjectId" --quiet 2>$null
        }
    }
    foreach ($sn in @($SubnetPub, $SubnetPriv)) {
        if (Test-Existe @("compute","networks","subnets","list","--project=$ProjectId","--filter=name=$sn","--format=value(name)")) {
            Write-Info "apagando subnet $sn"
            & $script:Gcloud compute networks subnets delete $sn "--region=$Region" "--project=$ProjectId" --quiet 2>$null
        }
    }
    if (Test-Existe @("compute","networks","list","--project=$ProjectId","--filter=name=$Vpc","--format=value(name)")) {
        Write-Info "apagando VPC $Vpc"
        & $script:Gcloud compute networks delete $Vpc "--project=$ProjectId" --quiet 2>$null
    }

    Write-Host ""
    Write-Host "Infraestrutura removida." -ForegroundColor Green
    Write-Host "O secret '$SecretSenha' foi mantido. Para apagar tambem:" -ForegroundColor DarkGray
    Write-Host "  gcloud secrets delete $SecretSenha --project=$ProjectId" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

# ============================================================================
#  INFRAESTRUTURA
# ============================================================================
if (-not $SomenteApp) {

    Write-Passo "Habilitando APIs"
    Invoke-Gcloud @("services","enable","compute.googleapis.com","iap.googleapis.com",
                    "secretmanager.googleapis.com","--project=$ProjectId")
    Write-Ok "compute, iap e secretmanager habilitados"

    # ------------------------------------------------------- 3. VPC e subnets

    Write-Passo "Criando a VPC e as subnets"

    if (-not (Test-Existe @("compute","networks","list","--project=$ProjectId","--filter=name=$Vpc","--format=value(name)"))) {
        # Modo custom (e nao "auto"): sem ele o GCP cria automaticamente uma
        # subnet em cada regiao do mundo, o oposto de projetar a rede.
        Invoke-Gcloud @("compute","networks","create",$Vpc,
                        "--subnet-mode=custom","--project=$ProjectId")
        Write-Ok "VPC '$Vpc' criada (modo custom)"
    } else { Write-Ok "VPC '$Vpc' ja existe" }

    if (-not (Test-Existe @("compute","networks","subnets","list","--project=$ProjectId","--filter=name=$SubnetPub","--format=value(name)"))) {
        Invoke-Gcloud @("compute","networks","subnets","create",$SubnetPub,
                        "--network=$Vpc","--range=$CidrPub","--region=$Region","--project=$ProjectId")
        Write-Ok "subnet publica '$SubnetPub' ($CidrPub)"
    } else { Write-Ok "subnet publica ja existe" }

    if (-not (Test-Existe @("compute","networks","subnets","list","--project=$ProjectId","--filter=name=$SubnetPriv","--format=value(name)"))) {
        Invoke-Gcloud @("compute","networks","subnets","create",$SubnetPriv,
                        "--network=$Vpc","--range=$CidrPriv","--region=$Region","--project=$ProjectId")
        Write-Ok "subnet privada '$SubnetPriv' ($CidrPriv)"
    } else { Write-Ok "subnet privada ja existe" }

    # ------------------------------------------------------- 4. firewall

    Write-Passo "Criando as regras de firewall"

    # A VPC em modo custom ja nega todo ingresso por padrao; abrimos apenas o
    # necessario, sempre mirando TAGS em vez de IPs de maquina.
    if (-not (Test-Existe @("compute","firewall-rules","list","--project=$ProjectId","--filter=name=estetica-allow-http","--format=value(name)"))) {
        Invoke-Gcloud @("compute","firewall-rules","create","estetica-allow-http",
                        "--network=$Vpc","--direction=INGRESS","--action=ALLOW",
                        "--rules=tcp:80,tcp:443","--source-ranges=0.0.0.0/0",
                        "--target-tags=app","--project=$ProjectId",
                        "--description=Acesso web publico a camada de aplicacao")
        Write-Ok "estetica-allow-http  : 0.0.0.0/0 -> tag 'app' (80, 443)"
    } else { Write-Ok "estetica-allow-http ja existe" }

    if (-not (Test-Existe @("compute","firewall-rules","list","--project=$ProjectId","--filter=name=estetica-allow-ssh-iap","--format=value(name)"))) {
        # 35.235.240.0/20 e a faixa fixa do Identity-Aware Proxy. Restringir o
        # SSH a ela significa que a porta 22 nunca fica exposta na internet, e
        # ainda assim a vm-db (sem IP externo) continua acessivel.
        Invoke-Gcloud @("compute","firewall-rules","create","estetica-allow-ssh-iap",
                        "--network=$Vpc","--direction=INGRESS","--action=ALLOW",
                        "--rules=tcp:22","--source-ranges=35.235.240.0/20",
                        "--target-tags=app,db","--project=$ProjectId",
                        "--description=SSH apenas via Identity-Aware Proxy")
        Write-Ok "estetica-allow-ssh-iap: IAP -> tags 'app' e 'db' (22)"
    } else { Write-Ok "estetica-allow-ssh-iap ja existe" }

    if (-not (Test-Existe @("compute","firewall-rules","list","--project=$ProjectId","--filter=name=estetica-allow-mysql","--format=value(name)"))) {
        # Origem por TAG, nao por CIDR: so quem carrega a tag 'app' alcanca o
        # banco, mesmo que outra VM suba na mesma subnet.
        Invoke-Gcloud @("compute","firewall-rules","create","estetica-allow-mysql",
                        "--network=$Vpc","--direction=INGRESS","--action=ALLOW",
                        "--rules=tcp:3306","--source-tags=app",
                        "--target-tags=db","--project=$ProjectId",
                        "--description=MySQL acessivel somente pela camada de aplicacao")
        Write-Ok "estetica-allow-mysql  : tag 'app' -> tag 'db' (3306)"
    } else { Write-Ok "estetica-allow-mysql ja existe" }

    # ------------------------------------------------------- 5. Cloud NAT

    Write-Passo "Criando Cloud Router e Cloud NAT"

    if (-not (Test-Existe @("compute","routers","list","--project=$ProjectId","--filter=name=estetica-router","--format=value(name)"))) {
        Invoke-Gcloud @("compute","routers","create","estetica-router",
                        "--network=$Vpc","--region=$Region","--project=$ProjectId")
        Write-Ok "Cloud Router criado"
    } else { Write-Ok "Cloud Router ja existe" }

    $natExiste = Get-Valor @("compute","routers","nats","list","--router=estetica-router",
                             "--region=$Region","--project=$ProjectId","--format=value(name)")
    if ([string]::IsNullOrWhiteSpace($natExiste)) {
        # Sem NAT a vm-db, que nao tem IP externo, nao consegue baixar pacotes
        # do apt e o startup script falha na instalacao do MySQL.
        Invoke-Gcloud @("compute","routers","nats","create","estetica-nat",
                        "--router=estetica-router","--region=$Region",
                        "--nat-all-subnet-ip-ranges","--auto-allocate-nat-external-ips",
                        "--project=$ProjectId")
        Write-Ok "Cloud NAT criado (saida para a subnet privada)"
    } else { Write-Ok "Cloud NAT ja existe" }
}

# --------------------------------------------------------- 6. senha do banco

Write-Passo "Obtendo a senha do banco"

$temSecret = Test-Existe @("secrets","list","--project=$ProjectId","--filter=name~/$SecretSenha`$","--format=value(name)")
if ($temSecret) {
    $Senha = Invoke-Gcloud @("secrets","versions","access","latest","--secret=$SecretSenha","--project=$ProjectId")
    Write-Ok "senha recuperada do Secret Manager"
} else {
    $Senha = New-Senha
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("s-" + [guid]::NewGuid().ToString() + ".txt")
    try {
        # Via arquivo, para a senha nao entrar no historico do shell.
        [System.IO.File]::WriteAllText($tmp, $Senha, (New-Object System.Text.ASCIIEncoding))
        Invoke-Gcloud @("secrets","create",$SecretSenha,"--replication-policy=automatic","--project=$ProjectId")
        Invoke-Gcloud @("secrets","versions","add",$SecretSenha,"--data-file=$tmp","--project=$ProjectId")
        Write-Ok "senha gerada e guardada em '$SecretSenha'"
    } finally { if (Test-Path $tmp) { Remove-Item $tmp -Force } }
}

# ------------------------------------------------------------- 7. VMs

if (-not $SomenteApp) {

    Write-Passo "Criando as VMs"

    $scriptDb  = Join-Path $RaizInfra "vm-db-startup.sh"
    $scriptApp = Join-Path $RaizInfra "vm-app-startup.sh"
    foreach ($s in @($scriptDb, $scriptApp)) {
        if (-not (Test-Path $s)) { Stop-ComErro "script de provisionamento nao encontrado: $s" }
    }

    # O MySQL nao aceita CIDR em definicao de usuario: '10.10.1.0/24' e invalido,
    # o formato correto e o curinga '10.10.1.%'.
    $hostApp = ($CidrPub -replace '\.0/24$', '.%')

    if (-not (Test-Existe @("compute","instances","list","--project=$ProjectId","--filter=name=$VmDb","--format=value(name)"))) {
        Write-Aviso "criando $VmDb - a instalacao do MySQL leva alguns minutos"
        Invoke-Gcloud @("compute","instances","create",$VmDb,
            "--zone=$Zone","--machine-type=$TipoMaquina",
            "--subnet=$SubnetPriv","--no-address",
            "--image-family=ubuntu-2404-lts-amd64","--image-project=ubuntu-os-cloud",
            "--boot-disk-size=10GB","--boot-disk-type=pd-balanced",
            "--tags=db",
            "--metadata-from-file=startup-script=$scriptDb",
            "--metadata=db-name=$DbName,db-user=$DbUser,db-password=$Senha,db-host-pattern=$hostApp",
            "--project=$ProjectId") `
            -AoFalhar "nao foi possivel criar a VM '$VmDb'."
        Write-Ok "$VmDb criada na subnet privada, sem IP externo"
    } else { Write-Ok "$VmDb ja existe" }

    if (-not (Test-Existe @("compute","instances","list","--project=$ProjectId","--filter=name=$VmApp","--format=value(name)"))) {
        Write-Aviso "criando $VmApp - a instalacao do .NET e do Nginx leva alguns minutos"
        Invoke-Gcloud @("compute","instances","create",$VmApp,
            "--zone=$Zone","--machine-type=$TipoMaquina",
            "--subnet=$SubnetPub",
            "--image-family=ubuntu-2404-lts-amd64","--image-project=ubuntu-os-cloud",
            "--boot-disk-size=15GB","--boot-disk-type=pd-balanced",
            "--tags=app",
            "--metadata-from-file=startup-script=$scriptApp",
            "--metadata=dotnet-channel=$DotnetCanal",
            "--project=$ProjectId") `
            -AoFalhar "nao foi possivel criar a VM '$VmApp'."
        Write-Ok "$VmApp criada na subnet publica, com IP externo"
    } else { Write-Ok "$VmApp ja existe" }

    # --------------------------------------------- 8. esperar provisionamento

    Write-Passo "Aguardando os servidores terminarem de se configurar"
    Write-Info "instalando pacotes nas duas VMs - normal levar de 5 a 10 minutos"

    foreach ($par in @(@($VmDb, "/var/lib/estetica-db-configurado"),
                       @($VmApp, "/var/lib/estetica-app-configurado"))) {
        $vm = $par[0]; $marcador = $par[1]
        $limite = (Get-Date).AddMinutes(15)
        $pronto = $false
        while (-not $pronto -and (Get-Date) -lt $limite) {
            Start-Sleep -Seconds 20
            $r = Invoke-SshVm -Vm $vm -Tolerante `
                 -Comando "test -f $marcador && echo PRONTO || echo AGUARDE"
            if ($r -match "PRONTO") { $pronto = $true } else { Write-Info "$vm ainda configurando" }
        }
        if (-not $pronto) {
            Stop-ComErro "'$vm' nao concluiu a configuracao em 15 minutos. Investigue com: gcloud compute ssh $vm --zone=$Zone --tunnel-through-iap --command='sudo journalctl -u google-startup-scripts -n 60'"
        }
        Write-Ok "$vm configurada"
    }
}

# ------------------------------------------------------- 9. publicar o codigo

Write-Passo "Enviando o codigo para a $VmApp"

$ipDb = Invoke-Gcloud @("compute","instances","describe",$VmDb,"--zone=$Zone",
                        "--project=$ProjectId","--format=value(networkInterfaces[0].networkIP)")
if ([string]::IsNullOrWhiteSpace($ipDb)) { Stop-ComErro "nao foi possivel descobrir o IP interno da '$VmDb'." }
Write-Ok "IP interno do banco: $ipDb"

# Copia so o que a compilacao precisa. Sem isso o .git, o PDF e os artefatos
# locais seriam enviados junto, deixando o upload lento a toa.
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("estetica-" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
try {
    Write-Info "preparando os arquivos"
    $null = robocopy $RaizProjeto $stage /E /NFL /NDL /NJH /NJS /NP `
                /XD ".git" "infra" "bin" "obj" ".vs" `
                /XF "*.pdf" "*.html" "*.ps1" "*.bat"
    # robocopy usa 0-7 para sucesso e >=8 para falha real.
    if ($LASTEXITCODE -ge 8) { Stop-ComErro "falha ao preparar os arquivos (robocopy $LASTEXITCODE)." }

    Invoke-SshVm -Vm $VmApp -Comando "sudo rm -rf /opt/estetica/fonte && sudo mkdir -p /opt/estetica/fonte && sudo chown -R \$(whoami) /opt/estetica/fonte" | Out-Null
    Copy-ParaVm -Origem (Join-Path $stage "*") -Destino "/opt/estetica/fonte/" -Vm $VmApp -Recursivo
    Write-Ok "codigo enviado"
} finally {
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Info "gravando as variaveis de ambiente"
$envTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("env-" + [guid]::NewGuid().ToString("N") + ".txt")
try {
    # UseHttpsRedirection=false: o Nginx serve apenas HTTP na porta 80; com o
    # redirecionamento ligado a aplicacao mandaria o navegador para uma porta
    # 443 que ninguem escuta.
    $conteudo = @(
        "ASPNETCORE_ENVIRONMENT=Production",
        "ASPNETCORE_URLS=http://127.0.0.1:5000",
        "UseHttpsRedirection=false",
        "ConnectionStrings__DefaultConnection=Server=$ipDb;Port=3306;Database=$DbName;User Id=$DbUser;Password=$Senha;"
    ) -join "`n"
    [System.IO.File]::WriteAllText($envTmp, $conteudo + "`n", (New-Object System.Text.UTF8Encoding($false)))

    Copy-ParaVm -Origem $envTmp -Destino "/tmp/estetica.env" -Vm $VmApp
    # Movido por SSH em vez de escrito por linha de comando: a senha nunca
    # aparece na lista de processos da VM.
    Invoke-SshVm -Vm $VmApp -Comando "sudo mv /tmp/estetica.env /etc/estetica.env && sudo chmod 600 /etc/estetica.env && sudo chown root:root /etc/estetica.env" | Out-Null
    Write-Ok "/etc/estetica.env gravado (modo 600)"
} finally {
    if (Test-Path $envTmp) { Remove-Item $envTmp -Force }
}

Write-Info "compilando e publicando na VM"
$pub = Invoke-SshVm -Vm $VmApp -Comando "sudo /opt/estetica/publicar.sh" -Tolerante
Write-Host $pub
if ($pub -notmatch "servico ativo") {
    Stop-ComErro "a aplicacao nao subiu. Veja: gcloud compute ssh $VmApp --zone=$Zone --tunnel-through-iap --command='sudo journalctl -u estetica -n 60'"
}
Write-Ok "aplicacao publicada e ativa"

# ------------------------------------------------------------- 10. validacao

Write-Passo "Validando"

$ipApp = Invoke-Gcloud @("compute","instances","describe",$VmApp,"--zone=$Zone","--project=$ProjectId",
                         "--format=value(networkInterfaces[0].accessConfigs[0].natIP)")
$url = "http://$ipApp/"

$codigo = 0
for ($i = 1; $i -le 5; $i++) {
    Write-Info "tentativa $i de 5 em $url"
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
        $codigo = [int] $r.StatusCode
    } catch {
        if ($_.Exception.Response) { $codigo = [int] $_.Exception.Response.StatusCode } else { $codigo = -1 }
    }
    if ($codigo -ge 200 -and $codigo -lt 400) { break }
    Start-Sleep -Seconds 10
}

if ($codigo -ge 200 -and $codigo -lt 400) {
    Write-Ok "aplicacao respondeu HTTP $codigo"
} else {
    Write-Aviso "resposta HTTP $codigo - o servico subiu, mas algo esta errado."
    Write-Aviso "  gcloud compute ssh $VmApp --zone=$Zone --tunnel-through-iap --command='sudo journalctl -u estetica -n 60'"
}

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Green
Write-Host " Infraestrutura no ar" -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green
Write-Host " URL          : $url"
Write-Host " VM aplicacao : $VmApp   $ipApp (publico)"
Write-Host " VM banco     : $VmDb   $ipDb (interno, sem IP externo)"
Write-Host "====================================================="
Write-Host ""
Write-Host " As VMs cobram por hora ligada. Para pausar sem apagar nada:" -ForegroundColor Yellow
Write-Host "   gcloud compute instances stop $VmApp $VmDb --zone=$Zone --project=$ProjectId" -ForegroundColor Yellow
Write-Host " Para apagar tudo:  .\infra.ps1 -Destruir" -ForegroundColor Yellow
Write-Host ""
