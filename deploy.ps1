#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy automatizado do EsteticaPorDoSol no Google Cloud (Cloud Run + Cloud SQL).

.DESCRIPTION
    O script e idempotente: pode ser executado quantas vezes for necessario.
    Na primeira execucao ele provisiona toda a infraestrutura; nas seguintes,
    apenas reconstroi a imagem e publica uma nova revisao.

    Se a instancia do Cloud SQL estiver desligada, o script a liga antes do
    deploy (a aplicacao aplica migrations no startup e falha sem o banco).

.PARAMETER Publico
    Libera acesso anonimo ao servico. Padrao: habilitado.
    Use -Publico:$false para publicar sem expor a aplicacao na internet.

.PARAMETER SomenteApp
    Pula toda a etapa de infraestrutura e faz apenas build + deploy.
    Mais rapido quando so o codigo mudou.

.PARAMETER BillingAccount
    ID da conta de billing (formato XXXXXX-XXXXXX-XXXXXX). Necessario apenas
    quando o projeto ainda nao existe. Se omitido e houver apenas uma conta
    disponivel, ela e usada automaticamente.

.EXAMPLE
    .\deploy.ps1
    Deploy completo, garantindo que a infraestrutura exista.

.EXAMPLE
    .\deploy.ps1 -SomenteApp
    Apenas rebuild e nova revisao.
#>
[CmdletBinding()]
param(
    [string] $ProjectId      = "estetica-por-do-sol",
    [string] $ProjectName    = "Estetica Por Do Sol",
    [string] $Region         = "southamerica-east1",
    [string] $ServiceName    = "estetica",
    [string] $SqlInstance    = "estetica-mysql",
    [string] $SqlTier        = "db-f1-micro",
    [string] $DbName         = "DbEsteticaPorDoSol",
    [string] $DbUser         = "estetica_app",
    [string] $SecretName     = "estetica-db-connection",
    [string] $RepoName       = "apps",
    [string] $ImageName      = "estetica",
    [string] $BillingAccount = "",
    [switch] $SomenteApp,
    [bool]   $Publico        = $true
)

# NAO trocar para "Stop". No PowerShell 5.1, redirecionar o stderr de um
# executavel nativo (o '2>$null' usado nas funcoes abaixo) faz cada linha de
# stderr virar um ErrorRecord; com "Stop" isso se torna erro FATAL. O gcloud
# escreve mensagens de progresso normais em stderr - como
# 'Operation ... finished successfully.' - entao o script abortava no meio de
# comandos que tinham funcionado. Verificado: falha tanto via gcloud.ps1 quanto
# via gcloud.cmd, ou seja, a causa e a redirecao + "Stop", nao o wrapper.
# Todo comando gcloud aqui tem o exit code verificado explicitamente.
$ErrorActionPreference = "Continue"
$script:PassoAtual = 0
$script:TotalPassos = 9

# Resolve para gcloud.cmd em vez de gcloud.ps1. Isso NAO e o que corrige o
# problema acima (ambos falham com "Stop"), mas evita uma camada extra: 'gcloud'
# puro resolve para gcloud.ps1, que abre outro processo PowerShell a cada
# chamada. Chamar o .cmd direto e mais rapido e deixa o exit code mais confiavel.
$script:Gcloud = $null
foreach ($candidato in @("gcloud.cmd", "gcloud")) {
    $encontrado = Get-Command $candidato -ErrorAction SilentlyContinue |
                  Where-Object { $_.CommandType -eq "Application" } |
                  Select-Object -First 1
    if ($null -ne $encontrado) { $script:Gcloud = $encontrado.Source; break }
}

# ---------------------------------------------------------------- utilitarios

function Write-Passo {
    param([string] $Texto)
    $script:PassoAtual++
    Write-Host ""
    Write-Host "[$script:PassoAtual/$script:TotalPassos] $Texto" -ForegroundColor Cyan
}

function Write-Ok   { param([string] $T) Write-Host "      OK   $T" -ForegroundColor Green }
function Write-Info { param([string] $T) Write-Host "      ..   $T" -ForegroundColor DarkGray }
function Write-Aviso{ param([string] $T) Write-Host "      !    $T" -ForegroundColor Yellow }

function Stop-ComErro {
    param([string] $Mensagem)
    Write-Host ""
    Write-Host "ERRO: $Mensagem" -ForegroundColor Red
    Write-Host ""
    exit 1
}

# Executa gcloud e aborta se o comando falhar. Retorna a saida como string.
function Invoke-Gcloud {
    param(
        [Parameter(Mandatory = $true)][string[]] $Argumentos,
        [string] $AoFalhar = ""
    )
    $saida = & $script:Gcloud @Argumentos 2>$null
    if ($LASTEXITCODE -ne 0) {
        if ([string]::IsNullOrWhiteSpace($AoFalhar)) {
            # Censura senhas antes de ecoar o comando: '--root-password' e
            # '--password' apareceriam em texto puro no console e em qualquer
            # log ou print de tela feito a partir dele.
            $seguros = $Argumentos | ForEach-Object {
                if ($_ -match '^(--(?:root-)?password)=') { "$($Matches[1])=***" } else { $_ }
            }
            $AoFalhar = "falha ao executar: gcloud $($seguros -join ' ')"
        }
        Stop-ComErro $AoFalhar
    }
    if ($null -eq $saida) { return "" }
    return ($saida -join "`n").Trim()
}

# Consulta que pode legitimamente nao retornar nada (usada para checar existencia).
function Get-GcloudValor {
    param([Parameter(Mandatory = $true)][string[]] $Argumentos)
    $saida = & $script:Gcloud @Argumentos 2>$null
    if ($LASTEXITCODE -ne 0) { return "" }
    if ($null -eq $saida) { return "" }
    return ($saida -join "`n").Trim()
}

function New-SenhaAleatoria {
    param([int] $Tamanho = 28)
    # Sem simbolos: a senha vai dentro de uma connection string, onde ';' e '='
    # tem significado sintatico.
    $alfabeto = [char[]]'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    $bytes = New-Object byte[] $Tamanho
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return (-join ($bytes | ForEach-Object { $alfabeto[$_ % $alfabeto.Length] }))
}

# ------------------------------------------------------------------ constantes

$InstanceConnectionName = "${ProjectId}:${Region}:${SqlInstance}"
$ImagemBase = "$Region-docker.pkg.dev/$ProjectId/$RepoName/$ImageName"
$Tag        = Get-Date -Format "yyyyMMdd-HHmmss"
$ImagemTag  = "${ImagemBase}:${Tag}"
$RaizProjeto = $PSScriptRoot

Write-Host ""
Write-Host "=====================================================" -ForegroundColor White
Write-Host " Deploy - EsteticaPorDoSol" -ForegroundColor White
Write-Host "=====================================================" -ForegroundColor White
Write-Host " Projeto GCP : $ProjectId"
Write-Host " Regiao      : $Region"
Write-Host " Servico     : $ServiceName"
Write-Host " Imagem      : ${ImageName}:${Tag}"
Write-Host " Modo        : $(if ($SomenteApp) { 'somente aplicacao' } else { 'completo (infra + aplicacao)' })"
Write-Host " Acesso      : $(if ($Publico) { 'PUBLICO na internet' } else { 'restrito (requer autenticacao IAM)' })"
Write-Host "====================================================="

if ($SomenteApp) { $script:TotalPassos = 3 }

# ------------------------------------------------- 1. verificacoes preliminares

Write-Passo "Verificando pre-requisitos"

if ([string]::IsNullOrWhiteSpace($script:Gcloud)) {
    Stop-ComErro "Google Cloud CLI nao encontrado. Instale em https://cloud.google.com/sdk/docs/install e rode 'gcloud auth login'."
}
Write-Ok "gcloud encontrado ($script:Gcloud)"

$conta = Get-GcloudValor @("auth", "list", "--filter=status:ACTIVE", "--format=value(account)")
if ([string]::IsNullOrWhiteSpace($conta)) {
    Stop-ComErro "Nenhuma conta autenticada. Rode: gcloud auth login"
}
Write-Ok "autenticado como $conta"

foreach ($arquivo in @("Dockerfile", "EsteticaPorDoSol.csproj")) {
    if (-not (Test-Path (Join-Path $RaizProjeto $arquivo))) {
        Stop-ComErro "'$arquivo' nao encontrado em $RaizProjeto. Rode o script de dentro da pasta do projeto."
    }
}
Write-Ok "Dockerfile e .csproj presentes"

# O Cloud Build roda em Linux, que diferencia maiusculas de minusculas. Um
# arquivo chamado 'DockerFile' passa despercebido no Windows e quebra o build.
$nomeReal = (Get-ChildItem -Path $RaizProjeto -Filter "Dockerfile" -Force | Select-Object -First 1).Name
if ($nomeReal -cne "Dockerfile") {
    Stop-ComErro "O arquivo esta como '$nomeReal'. O Cloud Build (Linux) exige exatamente 'Dockerfile'. Corrija com: git mv $nomeReal Dockerfile.tmp; git mv Dockerfile.tmp Dockerfile"
}
Write-Ok "nome do Dockerfile correto para build em Linux"

if ($SomenteApp) {
    $existe = Get-GcloudValor @("run", "services", "list", "--project=$ProjectId", "--region=$Region", "--filter=metadata.name=$ServiceName", "--format=value(metadata.name)")
    if ([string]::IsNullOrWhiteSpace($existe)) {
        Stop-ComErro "-SomenteApp exige um servico ja existente, e '$ServiceName' nao foi encontrado. Rode sem -SomenteApp."
    }
    Write-Ok "servico '$ServiceName' existente"

    # -SomenteApp pula a etapa que religa o banco. Avisar e melhor que deixar o
    # deploy falhar no startup por causa das migrations.
    $estadoSql = Get-GcloudValor @("sql", "instances", "list", "--project=$ProjectId", "--filter=name=$SqlInstance", "--format=value(state)")
    if ($estadoSql -ne "RUNNABLE") {
        Write-Aviso "a instancia '$SqlInstance' esta em '$estadoSql', nao RUNNABLE."
        Write-Aviso "o container aplica migrations no boot e vai falhar. Rode sem -SomenteApp para religar o banco,"
        Write-Aviso "ou ligue manualmente: gcloud sql instances patch $SqlInstance --activation-policy=ALWAYS --project=$ProjectId"
    }
}

# ------------------------------------------------------------ infraestrutura

if (-not $SomenteApp) {

    # ------------------------------------------------ 2. projeto, billing, APIs

    Write-Passo "Garantindo projeto, billing e APIs"

    $projetoExiste = Get-GcloudValor @("projects", "list", "--filter=projectId=$ProjectId", "--format=value(projectId)")

    if ([string]::IsNullOrWhiteSpace($projetoExiste)) {
        Write-Info "criando projeto $ProjectId"
        Invoke-Gcloud @("projects", "create", $ProjectId, "--name=$ProjectName") `
            -AoFalhar "nao foi possivel criar o projeto '$ProjectId'. O ID pode ja estar em uso globalmente por outra conta - escolha outro com -ProjectId."
        Write-Ok "projeto criado"
    } else {
        Write-Ok "projeto ja existe"
    }

    $billingAtivo = Get-GcloudValor @("beta", "billing", "projects", "describe", $ProjectId, "--format=value(billingEnabled)")

    if ($billingAtivo -ne "True") {
        $contaBilling = $BillingAccount
        if ([string]::IsNullOrWhiteSpace($contaBilling)) {
            $disponiveis = @(Get-GcloudValor @("beta", "billing", "accounts", "list", "--filter=open=true", "--format=value(name)") -split "`n" | Where-Object { $_ })
            if ($disponiveis.Count -eq 1) {
                $contaBilling = ($disponiveis[0] -replace "billingAccounts/", "")
                Write-Info "usando a unica conta de billing disponivel: $contaBilling"
            } elseif ($disponiveis.Count -eq 0) {
                Stop-ComErro "Nenhuma conta de billing ativa encontrada. Cloud Run e Cloud SQL exigem billing habilitado."
            } else {
                Stop-ComErro "Ha mais de uma conta de billing. Informe qual usar: .\deploy.ps1 -BillingAccount XXXXXX-XXXXXX-XXXXXX"
            }
        }
        Invoke-Gcloud @("beta", "billing", "projects", "link", $ProjectId, "--billing-account=$contaBilling")
        Write-Ok "billing vinculado"
    } else {
        Write-Ok "billing ja habilitado"
    }

    Write-Info "habilitando APIs (pode levar ~1 min na primeira vez)"
    Invoke-Gcloud @("services", "enable",
        "run.googleapis.com", "cloudbuild.googleapis.com", "sqladmin.googleapis.com",
        "secretmanager.googleapis.com", "artifactregistry.googleapis.com",
        "--project=$ProjectId")
    Write-Ok "APIs habilitadas"

    # ------------------------------------------------- 3. Artifact Registry

    Write-Passo "Garantindo repositorio de imagens"

    $repoExiste = Get-GcloudValor @("artifacts", "repositories", "list", "--project=$ProjectId", "--location=$Region", "--filter=name~/$RepoName`$", "--format=value(name)")
    if ([string]::IsNullOrWhiteSpace($repoExiste)) {
        Invoke-Gcloud @("artifacts", "repositories", "create", $RepoName,
            "--repository-format=docker", "--location=$Region",
            "--description=Imagens da aplicacao", "--project=$ProjectId")
        Write-Ok "repositorio '$RepoName' criado"
    } else {
        Write-Ok "repositorio '$RepoName' ja existe"
    }

    # ------------------------------------------------------- 4. Cloud SQL

    Write-Passo "Garantindo instancia Cloud SQL"

    $senhaNova = $null
    $estado = Get-GcloudValor @("sql", "instances", "list", "--project=$ProjectId", "--filter=name=$SqlInstance", "--format=value(state)")

    if ([string]::IsNullOrWhiteSpace($estado)) {
        Write-Aviso "criando instancia MySQL - isso leva de 5 a 10 minutos"
        $senhaNova = New-SenhaAleatoria
        Invoke-Gcloud @("sql", "instances", "create", $SqlInstance,
            "--database-version=MYSQL_8_0", "--edition=enterprise", "--tier=$SqlTier",
            "--region=$Region", "--storage-size=10GB", "--storage-type=HDD",
            "--root-password=$senhaNova", "--project=$ProjectId")
        Write-Ok "instancia criada"
    } else {
        Write-Ok "instancia ja existe (estado: $estado)"

        $politica = Get-GcloudValor @("sql", "instances", "describe", $SqlInstance, "--project=$ProjectId", "--format=value(settings.activationPolicy)")
        if ($politica -eq "NEVER" -or $estado -eq "STOPPED") {
            Write-Info "instancia desligada - religando (a aplicacao aplica migrations no boot e falha sem o banco)"
            Invoke-Gcloud @("sql", "instances", "patch", $SqlInstance, "--activation-policy=ALWAYS", "--project=$ProjectId", "--quiet")

            $limite = (Get-Date).AddMinutes(10)
            do {
                Start-Sleep -Seconds 10
                $estado = Get-GcloudValor @("sql", "instances", "list", "--project=$ProjectId", "--filter=name=$SqlInstance", "--format=value(state)")
                Write-Info "estado: $estado"
            } while ($estado -ne "RUNNABLE" -and (Get-Date) -lt $limite)

            if ($estado -ne "RUNNABLE") {
                Stop-ComErro "a instancia nao ficou pronta em 10 minutos (estado atual: $estado)."
            }
            Write-Ok "instancia no ar"
        }
    }

    # -------------------------------------------- 5. database, usuario, secret

    Write-Passo "Garantindo database, usuario e credenciais"

    # Atencao: 'sql databases list' e 'sql users list' falham quando a instancia
    # nao esta RUNNABLE, e a falha e indistinguivel de "nao existe". Por isso a
    # criacao tolera erro e reconsulta antes de abortar.
    $dbExiste = Get-GcloudValor @("sql", "databases", "list", "--instance=$SqlInstance", "--project=$ProjectId", "--filter=name=$DbName", "--format=value(name)")
    if ([string]::IsNullOrWhiteSpace($dbExiste)) {
        & $script:Gcloud sql databases create $DbName "--instance=$SqlInstance" `
            "--charset=utf8mb4" "--collation=utf8mb4_general_ci" "--project=$ProjectId" 2>$null
        if ($LASTEXITCODE -ne 0) {
            $dbExiste = Get-GcloudValor @("sql", "databases", "list", "--instance=$SqlInstance", "--project=$ProjectId", "--filter=name=$DbName", "--format=value(name)")
            if ([string]::IsNullOrWhiteSpace($dbExiste)) {
                Stop-ComErro "nao foi possivel criar o database '$DbName' na instancia '$SqlInstance'."
            }
            Write-Ok "database '$DbName' ja existia"
        } else {
            Write-Ok "database '$DbName' criado"
        }
    } else {
        Write-Ok "database '$DbName' ja existe"
    }

    $secretExiste = Get-GcloudValor @("secrets", "list", "--project=$ProjectId", "--filter=name~/$SecretName`$", "--format=value(name)")
    $usuarioExiste = Get-GcloudValor @("sql", "users", "list", "--instance=$SqlInstance", "--project=$ProjectId", "--filter=name=$DbUser", "--format=value(name)")

    # A senha nunca e lida de volta do banco. Se o secret ainda nao existe,
    # e preciso definir uma senha conhecida para poder gravar a connection string.
    if ([string]::IsNullOrWhiteSpace($secretExiste)) {
        if ($null -eq $senhaNova) { $senhaNova = New-SenhaAleatoria }

        if ([string]::IsNullOrWhiteSpace($usuarioExiste)) {
            & $script:Gcloud sql users create $DbUser "--instance=$SqlInstance" `
                "--host=%" "--password=$senhaNova" "--project=$ProjectId" 2>$null
            if ($LASTEXITCODE -ne 0) {
                # Mesmo caso do database: pode ja existir. Como precisamos de uma
                # senha conhecida para gravar no secret, redefinimos a dele.
                Invoke-Gcloud @("sql", "users", "set-password", $DbUser, "--instance=$SqlInstance",
                    "--host=%", "--password=$senhaNova", "--project=$ProjectId") `
                    -AoFalhar "nao foi possivel criar nem redefinir a senha do usuario '$DbUser'."
                Write-Ok "usuario '$DbUser' ja existia - senha redefinida"
            } else {
                Write-Ok "usuario '$DbUser' criado"
            }
        } else {
            Write-Aviso "usuario '$DbUser' existe mas o secret nao - redefinindo a senha"
            Invoke-Gcloud @("sql", "users", "set-password", $DbUser, "--instance=$SqlInstance",
                "--host=%", "--password=$senhaNova", "--project=$ProjectId")
            Write-Ok "senha redefinida"
        }

        # 'Server' iniciando com '/' e interpretado pelo MySqlConnector como
        # caminho de socket Unix - o Cloud Run monta o socket do Cloud SQL ali.
        $connectionString = "Server=/cloudsql/$InstanceConnectionName;Database=$DbName;User Id=$DbUser;Password=$senhaNova;"

        $arquivoTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("conn-" + [guid]::NewGuid().ToString() + ".txt")
        try {
            # Gravado em arquivo, e nao passado como argumento, para a senha nao
            # aparecer no historico do shell nem na lista de processos.
            [System.IO.File]::WriteAllText($arquivoTemp, $connectionString, (New-Object System.Text.ASCIIEncoding))
            Invoke-Gcloud @("secrets", "create", $SecretName, "--replication-policy=automatic", "--project=$ProjectId")
            Invoke-Gcloud @("secrets", "versions", "add", $SecretName, "--data-file=$arquivoTemp", "--project=$ProjectId")
            Write-Ok "secret '$SecretName' criado"
        } finally {
            if (Test-Path $arquivoTemp) { Remove-Item $arquivoTemp -Force }
        }
    } else {
        Write-Ok "secret '$SecretName' ja existe (credenciais preservadas)"
        if ([string]::IsNullOrWhiteSpace($usuarioExiste)) {
            Write-Aviso "o secret existe mas o usuario '$DbUser' nao esta no banco - o deploy vai falhar na conexao."
            Write-Aviso "apague o secret e rode de novo para regerar as credenciais:"
            Write-Aviso "  gcloud secrets delete $SecretName --project=$ProjectId"
        }
    }

    # ------------------------------------------------------------- 6. IAM

    Write-Passo "Garantindo permissoes da service account"

    $numeroProjeto = Invoke-Gcloud @("projects", "describe", $ProjectId, "--format=value(projectNumber)")
    $serviceAccount = "$numeroProjeto-compute@developer.gserviceaccount.com"

    # Sem secretAccessor a revisao nem inicia; sem cloudsql.client o container
    # sobe mas nao conecta no banco.
    Invoke-Gcloud @("secrets", "add-iam-policy-binding", $SecretName,
        "--member=serviceAccount:$serviceAccount", "--role=roles/secretmanager.secretAccessor",
        "--project=$ProjectId", "--format=value(etag)") | Out-Null
    Invoke-Gcloud @("projects", "add-iam-policy-binding", $ProjectId,
        "--member=serviceAccount:$serviceAccount", "--role=roles/cloudsql.client",
        "--format=value(etag)") | Out-Null
    Write-Ok "permissoes aplicadas a $serviceAccount"
}

# ------------------------------------------------------------- 7. build

Write-Passo "Construindo a imagem no Cloud Build"
Write-Info "enviando o codigo e compilando no servidor (~1-2 min)"
Write-Info "nao e necessario ter .NET SDK nem Docker nesta maquina"

Push-Location $RaizProjeto
try {
    & $script:Gcloud builds submit --tag $ImagemTag --project=$ProjectId
    if ($LASTEXITCODE -ne 0) {
        Stop-ComErro "o build falhou. Veja o log completo acima ou no console: https://console.cloud.google.com/cloud-build/builds?project=$ProjectId"
    }
} finally {
    Pop-Location
}
Write-Ok "imagem publicada: ${ImageName}:${Tag}"

# ------------------------------------------------------------ 8. deploy

Write-Passo "Publicando no Cloud Run"

$argsDeploy = @(
    "run", "deploy", $ServiceName,
    "--image=$ImagemTag",
    "--region=$Region",
    "--platform=managed",
    "--port=8080",
    "--add-cloudsql-instances=$InstanceConnectionName",
    "--set-secrets=ConnectionStrings__DefaultConnection=${SecretName}:latest",
    "--project=$ProjectId"
)
if ($Publico) { $argsDeploy += "--allow-unauthenticated" }

& $script:Gcloud @argsDeploy
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Aviso "o deploy falhou. Para ver o motivo:"
    Write-Aviso "  gcloud run services logs read $ServiceName --region=$Region --project=$ProjectId --limit=50"
    Stop-ComErro "nao foi possivel publicar a revisao."
}

$url = Invoke-Gcloud @("run", "services", "describe", $ServiceName, "--region=$Region", "--project=$ProjectId", "--format=value(status.url)")
Write-Ok "revisao publicada"

# ------------------------------------------------------------ 9. validacao

Write-Passo "Validando"

if (-not $Publico) {
    Write-Aviso "servico publicado sem acesso anonimo - o teste HTTP retornaria 403, entao foi pulado"
} else {
    # A primeira requisicao sobe o container do zero, que aplica as migrations
    # antes de escutar na porta. Por isso o timeout generoso e as tentativas.
    $codigo = 0
    for ($i = 1; $i -le 3; $i++) {
        Write-Info "tentativa $i de 3"
        try {
            $resposta = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 90
            $codigo = [int] $resposta.StatusCode
        } catch {
            if ($_.Exception.Response) { $codigo = [int] $_.Exception.Response.StatusCode } else { $codigo = -1 }
        }
        if ($codigo -ge 200 -and $codigo -lt 400) { break }
        Start-Sleep -Seconds 10
    }

    if ($codigo -ge 200 -and $codigo -lt 400) {
        Write-Ok "aplicacao respondeu HTTP $codigo"
    } else {
        Write-Host ""
        Write-Aviso "a aplicacao respondeu HTTP $codigo - a revisao subiu, mas algo esta errado em execucao."
        Write-Aviso "causas mais comuns: migration com erro ou banco inacessivel. Veja os logs:"
        Write-Aviso "  gcloud run services logs read $ServiceName --region=$Region --project=$ProjectId --limit=50"
    }
}

# ---------------------------------------------------------------- resumo final

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Green
Write-Host " Deploy concluido" -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green
Write-Host " URL   : $url"
Write-Host " Imagem: ${ImageName}:${Tag}"
Write-Host "====================================================="
Write-Host ""
Write-Host " Lembrete de custo: o Cloud Run escala a zero, mas o Cloud SQL" -ForegroundColor Yellow
Write-Host " cobra por hora ligado. Para desligar quando nao estiver usando:" -ForegroundColor Yellow
Write-Host "   gcloud sql instances patch $SqlInstance --activation-policy=NEVER --project=$ProjectId" -ForegroundColor Yellow
Write-Host ""
