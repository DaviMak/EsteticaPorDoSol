# Deploy no Google Cloud — EsteticaPorDoSol

Documento do deploy da aplicação no Google Cloud Platform, feito em **29/07/2026**.
Descreve a arquitetura, os comandos executados, as alterações que o código exigiu e
como operar o ambiente no dia a dia.

**URL da aplicação:** https://estetica-935668627687.southamerica-east1.run.app

---

## 1. Visão geral

A aplicação é um ASP.NET Core MVC (.NET 10) com Entity Framework Core e MySQL
(provider `Pomelo.EntityFrameworkCore.MySql`). Como o projeto já tinha um Dockerfile,
o destino natural é o **Cloud Run**: serviço gerenciado que roda containers, escala
automaticamente e reduz a zero instância quando não há tráfego.

```
        Internet (HTTPS)
               │
               ▼
    ┌──────────────────────┐
    │      Cloud Run       │   serviço "estetica"
    │   container :8080    │   escala 0 → N
    └──────┬────────┬──────┘
           │        │
   socket  │        │  variável de ambiente
   Unix    │        │  ConnectionStrings__DefaultConnection
           ▼        ▼
    ┌───────────┐  ┌─────────────────┐
    │ Cloud SQL │  │ Secret Manager  │
    │  MySQL 8  │  │  (credenciais)  │
    └───────────┘  └─────────────────┘
```

O TLS é terminado no proxy do Cloud Run — o container recebe HTTP puro na porta 8080.
A conexão com o banco não passa pela internet: o Cloud Run monta um **socket Unix** em
`/cloudsql/<instance-connection-name>`, e a autenticação é feita pela identidade da
service account (IAM), não por IP liberado em firewall.

### Recursos criados

| Recurso | Identificador | Configuração |
|---|---|---|
| Projeto GCP | `estetica-por-do-sol` | número `935668627687` |
| Região | `southamerica-east1` | São Paulo |
| Cloud Run | serviço `estetica` | porta 8080, público, escala a zero |
| Cloud SQL | instância `estetica-mysql` | MySQL 8.0, `db-f1-micro`, 10 GB HDD |
| Database | `DbEsteticaPorDoSol` | charset `utf8mb4`, collation `utf8mb4_general_ci` |
| Usuário do banco | `estetica_app` | host `%` |
| Secret Manager | `estetica-db-connection` | connection string completa |
| Artifact Registry | repositório `apps` | imagem `estetica:v1` |

O `instance-connection-name` do Cloud SQL — usado na connection string e no deploy — é:

```
estetica-por-do-sol:southamerica-east1:estetica-mysql
```

---

## 2. Pré-requisitos

- **Google Cloud CLI** instalado e autenticado (`gcloud auth login`).
- Uma **conta de billing** ativa. Cloud Run, Cloud SQL e Cloud Build exigem billing
  habilitado no projeto, mesmo dentro do nível gratuito.
- **Não é necessário** ter .NET SDK nem Docker na máquina local: a compilação e a
  construção da imagem acontecem no Cloud Build, no servidor.

Para descobrir o ID da sua conta de billing:

```powershell
gcloud beta billing accounts list
```

O ID tem o formato `XXXXXX-XXXXXX-XXXXXX`. Nos comandos abaixo ele aparece como
`SUA-CONTA-DE-BILLING` — substitua pelo valor real.

---

## 3. Passo a passo executado

Todos os comandos foram rodados no PowerShell, no Windows.

### 3.1 Criar o projeto e habilitar as APIs

```powershell
gcloud projects create estetica-por-do-sol --name="Estetica Por Do Sol"

gcloud config set project estetica-por-do-sol

gcloud beta billing projects link estetica-por-do-sol `
  --billing-account=SUA-CONTA-DE-BILLING

gcloud services enable `
  run.googleapis.com `
  cloudbuild.googleapis.com `
  sqladmin.googleapis.com `
  secretmanager.googleapis.com `
  artifactregistry.googleapis.com `
  --project=estetica-por-do-sol
```

O projeto foi criado separado dos demais para isolar recursos, permissões e custos —
facilita ver quanto essa aplicação especificamente está consumindo, e permite apagar
tudo de uma vez se necessário.

### 3.2 Provisionar o Cloud SQL

A senha foi gerada aleatoriamente (28 caracteres, alfanuméricos, via
`RandomNumberGenerator`) e **nunca digitada nem salva no repositório**.

```powershell
gcloud sql instances create estetica-mysql `
  --database-version=MYSQL_8_0 `
  --edition=enterprise `
  --tier=db-f1-micro `
  --region=southamerica-east1 `
  --storage-size=10GB `
  --storage-type=HDD `
  --root-password="<SENHA>" `
  --project=estetica-por-do-sol
```

A criação da instância leva de 5 a 10 minutos. Em seguida, o database e o usuário
que a aplicação usa:

```powershell
gcloud sql databases create DbEsteticaPorDoSol `
  --instance=estetica-mysql `
  --charset=utf8mb4 --collation=utf8mb4_general_ci `
  --project=estetica-por-do-sol

gcloud sql users create estetica_app `
  --instance=estetica-mysql --host=% `
  --password="<SENHA>" `
  --project=estetica-por-do-sol
```

`utf8mb4` foi escolhido para que acentuação e emojis sejam armazenados corretamente —
o `utf8` do MySQL é incompleto e não cobre todos os caracteres.

### 3.3 Guardar a connection string no Secret Manager

A connection string aponta para o socket Unix, não para um host de rede. O
`MySqlConnector` (usado pelo Pomelo) interpreta um `Server` que começa com `/`
como caminho de socket:

```
Server=/cloudsql/estetica-por-do-sol:southamerica-east1:estetica-mysql;Database=DbEsteticaPorDoSol;User Id=estetica_app;Password=<SENHA>;
```

```powershell
gcloud secrets create estetica-db-connection `
  --replication-policy=automatic `
  --project=estetica-por-do-sol

gcloud secrets versions add estetica-db-connection `
  --data-file="caminho\para\conn.txt" `
  --project=estetica-por-do-sol
```

O valor foi passado por arquivo (`--data-file`) em vez de argumento de linha de comando
para que a senha não fique registrada no histórico do shell. O arquivo temporário ficou
fora do diretório do projeto.

### 3.4 Permissões da service account

O Cloud Run roda, por padrão, com a service account de compute do projeto. Ela precisa
de duas permissões: ler o secret e abrir conexão com o Cloud SQL.

```powershell
$num = (gcloud projects describe estetica-por-do-sol --format="value(projectNumber)")
$sa = "$num-compute@developer.gserviceaccount.com"

gcloud secrets add-iam-policy-binding estetica-db-connection `
  --member="serviceAccount:$sa" `
  --role="roles/secretmanager.secretAccessor" `
  --project=estetica-por-do-sol

gcloud projects add-iam-policy-binding estetica-por-do-sol `
  --member="serviceAccount:$sa" `
  --role="roles/cloudsql.client"
```

Sem `cloudsql.client` o container sobe mas falha ao conectar; sem `secretAccessor` a
revisão nem inicia, porque o Cloud Run não consegue montar a variável de ambiente.

### 3.5 Build da imagem

```powershell
gcloud artifacts repositories create apps `
  --repository-format=docker `
  --location=southamerica-east1 `
  --project=estetica-por-do-sol

gcloud builds submit `
  --config=cloudbuild.yaml `
  --substitutions=_IMAGEM=southamerica-east1-docker.pkg.dev/estetica-por-do-sol/apps/estetica:v1 `
  --project=estetica-por-do-sol
```


O `builds submit` envia o código-fonte, executa o Dockerfile em uma máquina do Cloud
Build e publica a imagem no Artifact Registry. O build levou **1m03s**.

A configuração vai pelo `cloudbuild.yaml` em vez do atalho `--tag` porque o Dockerfile
mora em `back-end/`, e o `--tag` sozinho só procura um Dockerfile na raiz do contexto.
O contexto continua sendo a raiz: a imagem precisa de `back-end/` e de `front-end/`.

### 3.6 Deploy no Cloud Run

```powershell
gcloud run deploy estetica `
  --image=southamerica-east1-docker.pkg.dev/estetica-por-do-sol/apps/estetica:v1 `
  --region=southamerica-east1 `
  --platform=managed `
  --allow-unauthenticated `
  --port=8080 `
  --add-cloudsql-instances=estetica-por-do-sol:southamerica-east1:estetica-mysql `
  --set-secrets="ConnectionStrings__DefaultConnection=estetica-db-connection:latest" `
  --project=estetica-por-do-sol
```

Dois detalhes importantes:

- `--add-cloudsql-instances` é o que faz o Cloud Run montar o socket em `/cloudsql/...`.
- `--set-secrets` injeta o secret como variável de ambiente com o nome
  `ConnectionStrings__DefaultConnection`. O duplo underscore é a convenção do
  ASP.NET Core para hierarquia de configuração: essa variável sobrescreve
  automaticamente o valor de `ConnectionStrings:DefaultConnection` do
  `appsettings.json`, **sem precisar de código adicional** para ler o secret.

### 3.7 Validação

```powershell
Invoke-WebRequest -Uri "https://estetica-935668627687.southamerica-east1.run.app/" -UseBasicParsing
```

Resultado: **HTTP 200**, título `Login - EsteticaPorDoSol`. Os logs confirmaram que as
três migrations foram aplicadas no banco:

- `20260602004150_CriacaoInicial`
- `20260602033802_AdicionarCamposAtendimento`
- `20260603040946_TelefoneOpcional`

---

## 4. Alterações necessárias no código

O projeto não subia sem estes quatro ajustes. Cada um corresponde a uma diferença real
entre rodar na máquina local e rodar em container atrás de um proxy gerenciado.

### 4.1 `DockerFile` → `Dockerfile`

O arquivo estava com F maiúsculo. O Windows não diferencia maiúsculas de minúsculas em
nomes de arquivo, então localmente isso nunca deu problema — mas o Cloud Build roda em
Linux, que diferencia, e o build falharia por não encontrar o `Dockerfile`.

Renomear em sistema case-insensitive exige dois passos, senão o Git ignora a mudança:

```powershell
git mv DockerFile Dockerfile.tmp
git mv Dockerfile.tmp Dockerfile
```

### 4.2 `ServerVersion.AutoDetect` → `ServerVersion.Parse`

```csharp
// antes
options.UseMySql(
    builder.Configuration.GetConnectionString("DefaultConnection"),
    ServerVersion.AutoDetect(builder.Configuration.GetConnectionString("DefaultConnection"))
);

// depois
options.UseMySql(
    builder.Configuration.GetConnectionString("DefaultConnection"),
    ServerVersion.Parse("8.0-mysql")
);
```

O `AutoDetect` abre uma conexão com o banco durante a **construção** do host, para
descobrir a versão do servidor. Isso torna a inicialização dependente de o banco estar
respondendo naquele instante: qualquer indisponibilidade momentânea derruba o container
antes de ele conseguir escutar na porta, e o Cloud Run marca a revisão como falha.
Declarar a versão explicitamente elimina essa dependência e ainda deixa o boot mais rápido.

### 4.3 `UseForwardedHeaders` — evitar loop de redirecionamento

```csharp
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.KnownNetworks.Clear();
    options.KnownProxies.Clear();
});

// ...

app.UseForwardedHeaders();   // antes de qualquer outro middleware
```

Este é o ajuste menos óbvio e o que mais quebra deploys de ASP.NET Core no Cloud Run.

O código já tinha `app.UseHttpsRedirection()`. O Cloud Run termina o TLS no proxy e
entrega a requisição ao container como HTTP simples, informando o protocolo original
no header `X-Forwarded-Proto: https`. Sem o middleware de forwarded headers, o
ASP.NET Core não lê esse header: vê `Request.IsHttps == false`, e o
`UseHttpsRedirection` responde com um redirecionamento 307 para a versão HTTPS. O
navegador segue o redirecionamento, chega no proxy por HTTPS, o proxy repassa por HTTP,
e o ciclo se repete — **loop infinito**, o site não abre.

O `UseForwardedHeaders` faz o ASP.NET Core confiar nesses headers e reconhecer a
requisição como HTTPS. Os `Clear()` em `KnownNetworks`/`KnownProxies` são necessários
porque o IP do proxy do Cloud Run não é fixo nem conhecido antecipadamente; isso é
seguro aqui porque o container só recebe tráfego através do proxy do Cloud Run, nunca
diretamente da internet.

> **Aviso de depreciação no build:** o .NET 10 marcou `KnownNetworks` como obsoleto em
> favor de `KnownIPNetworks` (warning `ASPDEPR005`). É apenas aviso — compila e funciona.
> Para eliminá-lo, troque `options.KnownNetworks.Clear()` por
> `options.KnownIPNetworks.Clear()`.

### 4.4 Migrations aplicadas no startup

```csharp
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
    db.Database.Migrate();
}
```

O caminho usual seria rodar `dotnet ef database update` apontando para o banco através
do Cloud SQL Auth Proxy. Isso não era possível: **não há .NET SDK instalado nesta
máquina** (`dotnet --list-sdks` não retorna nada), e o `dotnet-ef` depende do SDK.

Aplicar as migrations no startup resolve sem exigir ferramental local: quando a
aplicação sobe, ela mesma cria ou atualiza o schema. O EF Core usa uma lock table no
banco (`__DbEsteticaPorDoSol_EFMigrationsLock`), então duas instâncias subindo ao mesmo
tempo não corrompem o schema — a segunda espera a primeira terminar.

**Ressalva:** em produção séria, migração automática no boot não é o ideal, porque uma
migration com erro impede a aplicação de subir, e um `DROP COLUMN` acidental é aplicado
sem revisão. Para este projeto a simplicidade compensa. Se um dia houver .NET SDK
disponível, o caminho mais controlado é gerar o script e aplicar separadamente:

```powershell
dotnet ef migrations script --idempotent -o migracao.sql
```

### 4.5 `.dockerignore`

Adicionado para não enviar `.git`, `bin`, `obj` e `.vs` ao Cloud Build — deixa o upload
menor e evita que artefatos compilados localmente entrem na imagem.

---

## 5. Operação

### Publicar uma nova versão (automatizado)

O jeito mais simples é usar o script `deploy.ps1`, que executa tudo o que está
documentado na seção 3 de forma idempotente:

```powershell
.\deploy.ps1                # completo: garante a infra e publica
.\deploy.ps1 -SomenteApp    # mais rápido: só rebuild + nova revisão
```

Ou clique duas vezes em **`deploy.bat`**, que apenas chama o `deploy.ps1` contornando a
ExecutionPolicy do PowerShell.

O script:

- verifica pré-requisitos (gcloud instalado, conta autenticada, `Dockerfile` com o nome
  correto para build em Linux);
- cria o que estiver faltando e preserva o que já existe — inclusive **religa a instância
  do Cloud SQL** se ela estiver desligada, o que é necessário porque a aplicação aplica
  migrations no boot;
- gera senha aleatória e grava no Secret Manager apenas na primeira execução; se o
  secret já existe, as credenciais são preservadas;
- versiona a imagem com timestamp (`estetica:20260729-203916`), permitindo rollback;
- testa a URL no final e aponta o comando de logs se a aplicação não responder.

Parâmetros úteis: `-Publico:$false` publica sem expor na internet, `-ProjectId` e
`-Region` mudam o destino, `-BillingAccount` é necessário só na criação do projeto.

### Publicar uma nova versão (manual)

Após alterar o código, troque a tag da imagem (`v2`, `v3`, …) para manter histórico e
permitir rollback:

```powershell
gcloud builds submit `
  --config=cloudbuild.yaml `
  --substitutions=_IMAGEM=southamerica-east1-docker.pkg.dev/estetica-por-do-sol/apps/estetica:v2 `
  --project=estetica-por-do-sol

gcloud run deploy estetica `
  --image=southamerica-east1-docker.pkg.dev/estetica-por-do-sol/apps/estetica:v2 `
  --region=southamerica-east1 `
  --project=estetica-por-do-sol
```

O segundo comando não repete `--add-cloudsql-instances` nem `--set-secrets`: o Cloud Run
preserva a configuração do serviço entre deploys, alterando apenas o que é informado.

### Ver logs

```powershell
gcloud run services logs read estetica `
  --region=southamerica-east1 --project=estetica-por-do-sol --limit=50
```

### Voltar para a versão anterior

```powershell
gcloud run services update-traffic estetica `
  --to-revisions=estetica-00001-qh8=100 `
  --region=southamerica-east1 --project=estetica-por-do-sol
```

### Conectar ao banco manualmente

```powershell
gcloud sql connect estetica-mysql --user=estetica_app --project=estetica-por-do-sol
```

Esse comando libera temporariamente seu IP na instância e abre um cliente MySQL.

### Recuperar a senha do banco

A senha não está em nenhum arquivo do projeto. Ela vive no secret:

```powershell
gcloud secrets versions access latest --secret=estetica-db-connection `
  --project=estetica-por-do-sol
```

---

## 6. Custos

**O Cloud Run escala a zero** — sem acessos, o custo de compute é praticamente nulo, e
o nível gratuito cobre bem um projeto acadêmico.

**O Cloud SQL cobra por hora ligado, independentemente de uso.** É o item dominante da
fatura: a instância `db-f1-micro` fica na faixa de **R$ 50 a 90 por mês** rodando 24h.
Se a aplicação só é usada esporadicamente, vale desligar a instância entre os usos:

```powershell
# desligar
gcloud sql instances patch estetica-mysql --activation-policy=NEVER `
  --project=estetica-por-do-sol

# ligar novamente
gcloud sql instances patch estetica-mysql --activation-policy=ALWAYS `
  --project=estetica-por-do-sol
```

Com a instância desligada os dados são preservados (continua-se pagando apenas o
armazenamento, poucos reais), mas a aplicação retorna erro ao acessar o banco.

Para apagar tudo e zerar o custo:

```powershell
gcloud projects delete estetica-por-do-sol
```

---

## 7. Pendência de segurança

O `appsettings.json` continua com credenciais de desenvolvimento em texto puro:

```json
"DefaultConnection": "server=localhost;database=DbEsteticaPorDoSol;user=root;password=root;"
```

Em produção esse valor é sobrescrito pela variável de ambiente vinda do Secret Manager,
então **não afeta o deploy**. Mas é credencial versionada em repositório público. O
ideal é remover o valor do arquivo e manter a connection string local em
`appsettings.Development.json` (fora do controle de versão) ou em *user secrets*:

```powershell
dotnet user-secrets set "ConnectionStrings:DefaultConnection" "server=localhost;..."
```

---

## 8. Problemas comuns

| Sintoma | Causa provável |
|---|---|
| Build falha com `Dockerfile not found` | Nome do arquivo com maiúscula errada (ver 4.1) |
| Navegador entra em loop / `ERR_TOO_MANY_REDIRECTS` | Falta `UseForwardedHeaders` (ver 4.3) |
| Revisão falha com "container failed to start" | Ver logs; geralmente migration com erro ou banco inacessível |
| `Access denied for user` | Senha divergente entre o secret e o usuário no Cloud SQL |
| `Can't connect to local MySQL server through socket` | Falta `--add-cloudsql-instances` no deploy, ou a role `cloudsql.client` |
| Revisão nem inicia, erro de secret | Falta `secretmanager.secretAccessor` na service account (ver 3.4) |
| `NativeCommandError` num comando gcloud que diz `finished successfully` | Ver abaixo |

### `NativeCommandError` em comando gcloud bem-sucedido

Sintoma, ao rodar scripts PowerShell que chamam o gcloud no Windows:

```
python.exe : Operation "operations/acat.p2-..." finished successfully.
    + FullyQualifiedErrorId : NativeCommandError
```

O comando **funcionou** — a mensagem é de sucesso — mas o script aborta.

**Causa:** no PowerShell 5.1, redirecionar o stderr de um executável nativo (`2>$null`)
transforma cada linha de stderr em um `ErrorRecord`. Se `$ErrorActionPreference` estiver
como `"Stop"`, esse registro se torna um erro **fatal**. O gcloud escreve mensagens de
progresso normais em stderr, não apenas erros — então qualquer comando que informe
andamento derruba o script.

**Solução:** não usar `$ErrorActionPreference = "Stop"` em scripts que chamam o gcloud.
Deixe `"Continue"` e verifique `$LASTEXITCODE` explicitamente após cada chamada. Trocar
`gcloud.ps1` por `gcloud.cmd` **não** resolve — ambos falham do mesmo jeito, porque a
causa é a redireção combinada com a preferência, não o wrapper.

O `deploy.ps1` já segue essa abordagem.
