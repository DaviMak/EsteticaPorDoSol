# Justificativa técnica da escolha do Google Cloud Platform

Documento que responde: **por que o GCP foi escolhido como plataforma de deploy do
EsteticaPorDoSol**, e não Azure, AWS, uma PaaS simplificada ou um servidor próprio.

A argumentação parte das características reais do projeto — não de preferência genérica
por um fornecedor. Cada decisão abaixo é rastreável a uma linha de código ou a uma
restrição concreta do ambiente de desenvolvimento.

---

## 1. O que o projeto exige da plataforma

Antes de comparar provedores, é preciso enunciar os requisitos que a aplicação impõe.
Eles saem diretamente do código:

| Requisito | Origem no projeto |
|---|---|
| Executar **container Linux** | `Dockerfile` multi-stage, base `mcr.microsoft.com/dotnet/aspnet:10.0` |
| Suportar **.NET 10** | `<TargetFramework>net10.0</TargetFramework>` no `.csproj` |
| **MySQL 8** gerenciado | `Pomelo.EntityFrameworkCore.MySql` 9.0.0 + `ServerVersion.Parse("8.0-mysql")` |
| Porta HTTP configurável | `ENV ASPNETCORE_URLS=http://+:8080` |
| **TLS terminado por proxy** | `UseForwardedHeaders` + `UseHttpsRedirection` no `Program.cs` |
| **Injeção de segredo como variável de ambiente** | `ConnectionStrings:DefaultConnection` lido via `IConfiguration` |
| **Build remoto** (sem toolchain local) | Máquina de desenvolvimento não tem .NET SDK nem Docker |
| Custo compatível com projeto acadêmico | Tráfego próximo de zero, uso intermitente |
| **Latência baixa no Brasil** | Aplicação de uso local (estética automotiva, clientes brasileiros) |

O requisito que mais restringe a escolha é o **build remoto**: sem .NET SDK nem Docker na
máquina de desenvolvimento, qualquer plataforma que exija compilar localmente está
descartada de saída.

> **Nota sobre custo.** Este deploy é coberto por **créditos gratuitos do GCP**, então
> preço não foi o critério decisório. Isso na verdade *fortalece* a justificativa: a
> escolha se sustenta em encaixe técnico, e não em ser a opção mais barata. O custo
> aparece neste documento em dois papéis legítimos — **como consumir os créditos mais
> devagar** (seção 3) e **o que acontece quando eles terminarem** (seção 9), que é a
> pergunta que decide se a arquitetura sobrevive ao fim do período gratuito.

---

## 2. Motivo central: o projeto já era um container, e o Cloud Run é o menor
   denominador comum para rodar containers

O projeto entrou no processo de deploy **já containerizado**. Isso descarta
imediatamente a categoria de plataformas que exigem buildpacks proprietários ou
estrutura de projeto específica, e favorece um runtime de containers puro.

O Cloud Run atende com um contrato mínimo, que o `Dockerfile` já satisfaz sem alteração:

1. A imagem escuta em uma porta HTTP definida pela variável de ambiente.
2. O container é *stateless* — nada é persistido em disco local.
3. O processo termina de forma limpa quando recebe `SIGTERM`.

O `Dockerfile` já expõe `8080` e configura `ASPNETCORE_URLS=http://+:8080`
(`Dockerfile:16-17`). O ASP.NET Core trata `SIGTERM` nativamente através do
`IHostApplicationLifetime`. Não há gravação em disco local — assets estáticos vêm do
`wwwroot` embutido na imagem e o estado vive todo no MySQL.

**Consequência prática:** zero código de adaptação à plataforma. Não existe nenhuma
biblioteca do Google no `.csproj` — as duas únicas dependências são
`Microsoft.EntityFrameworkCore.Design` e `Pomelo.EntityFrameworkCore.MySql`. A
aplicação não sabe que está no GCP. Isso é um ponto arquitetural relevante: **não houve
vendor lock-in no nível de código.** A mesma imagem roda em Azure Container Apps, AWS
App Runner ou num Docker local sem recompilar — o que torna a escolha reversível.

---

## 3. Escala a zero: elasticidade de capacidade e consumo lento dos créditos

O Cloud Run cobra por **tempo de CPU e memória efetivamente utilizados durante o
processamento de requisições**, com granularidade de 100 ms, e reduz o número de
instâncias a **zero** quando não há tráfego.

Com os créditos cobrindo a fatura, o benefício aqui não é economizar dinheiro — é
**consumir a cota de créditos lentamente** e ter elasticidade de capacidade sem
reprovisionar nada.

Trata-se de um sistema de gestão para uma estética automotiva com uso pontual: cadastro
de clientes, veículos, serviços e atendimentos. O padrão de tráfego é de dezenas de
requisições por dia, concentradas em poucos minutos. O restante do tempo — mais de 99% —
a aplicação está ociosa. Sob cobrança por hora reservada, esses 99% de ociosidade
queimariam créditos continuamente, encurtando o tempo de vida do ambiente. No Cloud Run,
não consomem praticamente nada.

Comparação dos modelos de cobrança:

| Modelo | Como cobra | Consumo de crédito com tráfego ~0 |
|---|---|---|
| **Cloud Run** (escolhido) | por 100 ms de CPU/memória em uso | ≈ nulo |
| VM / VPS (Compute Engine, EC2, DigitalOcean) | por hora ligada | integral, 24h/dia |
| Azure App Service (plano B1) | por hora do plano reservado | integral, 24h/dia |
| Kubernetes gerenciado (GKE/EKS/AKS) | nós + taxa do control plane | integral + overhead |

Além dos créditos, o Cloud Run tem **nível gratuito permanente** — 2 milhões de
requisições, 360.000 GiB-segundo de memória e 180.000 vCPU-segundo por mês. O consumo
real do projeto fica uma ordem de magnitude abaixo desse limite, o que significa que o
compute permanece gratuito **mesmo depois de os créditos expirarem**. Essa é a diferença
entre um ambiente que sobrevive ao fim do período promocional e um que precisa ser
desmontado.

O outro lado da elasticidade: se a aplicação passasse de uso pontual a uso real de
oficina, com vários atendentes simultâneos, o Cloud Run adiciona instâncias sozinho até o
limite configurado. Não há capacidade a redimensionar nem downtime de migração de plano —
o que numa VM ou num plano App Service reservado seria uma intervenção manual.

### O trade-off honesto: cold start

Escalar a zero tem um preço técnico — a primeira requisição após um período de
inatividade paga o **cold start**: criação da instância, carga do runtime .NET e
inicialização do host.

Esse custo foi **explicitamente considerado e mitigado no código**. A alteração de
`ServerVersion.AutoDetect` para `ServerVersion.Parse("8.0-mysql")` (`Program.cs:9`)
existe por dois motivos, e um deles é exatamente o cold start: o `AutoDetect` **abre uma
conexão com o banco durante a construção do host** apenas para descobrir a versão do
servidor. Isso adiciona um round-trip ao banco em cada inicialização de instância e,
pior, torna o boot dependente de o MySQL estar respondendo naquele instante — qualquer
indisponibilidade momentânea derruba o container antes de ele conseguir escutar na porta,
e o Cloud Run marca a revisão como falha. Declarar a versão de forma literal remove a
dependência e encurta o boot.

Para uma aplicação de gestão interna, uma primeira requisição de alguns segundos é
aceitável. Se deixasse de ser, o Cloud Run permite fixar `--min-instances=1` sem
alteração de código — o parâmetro converte o serviço em always-on ao custo de uma
instância contínua. **A elasticidade da decisão é o ponto:** começa-se no modelo mais
barato e sobe-se quando o requisito mudar.

---

## 4. Cloud Build: deploy sem .NET SDK e sem Docker na máquina local

Este é o requisito que mais estreita a escolha, e é uma restrição factual do ambiente:
a máquina de desenvolvimento **não tem .NET SDK instalado** (`dotnet --list-sdks` não
retorna nada) nem Docker Desktop.

O `gcloud builds submit` resolve isso de forma direta: empacota o código-fonte, envia
para o Cloud Build, executa o `Dockerfile` em uma máquina Linux gerenciada e publica a
imagem no Artifact Registry. Um único comando, sem toolchain local:

```powershell
gcloud builds submit `
  --tag southamerica-east1-docker.pkg.dev/estetica-por-do-sol/apps/estetica:v1
```

O build real levou **1m03s**. O estágio 1 do `Dockerfile` (`sdk:10.0`) baixa o SDK
dentro do build remoto — ou seja, o SDK existe, apenas não na máquina do desenvolvedor.

Duas consequências importantes:

1. **Build reprodutível em Linux.** O container é construído no mesmo sistema
   operacional em que roda em produção. Isso não é detalhe: o arquivo estava nomeado
   `DockerFile` com F maiúsculo, e o Windows — case-insensitive — nunca reclamou. O
   Cloud Build, em Linux, falharia com `Dockerfile not found`. Fazer o build remoto
   **expôs um bug latente** que um build local no Windows jamais mostraria.

2. **Migrations sem `dotnet ef`.** Sem SDK, não há `dotnet-ef`, então o caminho usual
   (`dotnet ef database update` através do Cloud SQL Auth Proxy) estava indisponível. A
   solução foi aplicar as migrations no startup (`Program.cs:28-32`), o que funciona com
   segurança razoável porque o EF Core usa uma *lock table* no banco
   (`__DbEsteticaPorDoSol_EFMigrationsLock`) — duas instâncias subindo simultaneamente
   não corrompem o schema, a segunda aguarda a primeira. As três migrations
   (`CriacaoInicial`, `AdicionarCamposAtendimento`, `TelefoneOpcional`) foram aplicadas
   automaticamente na primeira revisão, confirmado nos logs.

   *Ressalva registrada:* migração automática no boot não é prática ideal para produção
   crítica — uma migration com erro impede a aplicação de subir. Para este escopo a
   simplicidade compensa, e o caminho controlado (`dotnet ef migrations script
   --idempotent`) fica documentado para quando houver SDK disponível.

---

## 5. Integração Cloud Run ↔ Cloud SQL: conexão sem exposição de rede

A aplicação precisa de MySQL 8. O ponto que diferencia o GCP aqui não é o MySQL
gerenciado em si — todo provedor tem um — mas **como o container alcança o banco**.

O Cloud Run monta um **socket Unix** dentro do container, no caminho
`/cloudsql/<instance-connection-name>`, quando o deploy inclui:

```powershell
--add-cloudsql-instances=estetica-por-do-sol:southamerica-east1:estetica-mysql
```

E o `MySqlConnector` (usado internamente pelo Pomelo) interpreta um valor de `Server`
que começa com `/` como **caminho de socket**, não como host de rede:

```
Server=/cloudsql/estetica-por-do-sol:southamerica-east1:estetica-mysql;Database=DbEsteticaPorDoSol;User Id=estetica_app;Password=…
```

As implicações de segurança são concretas:

- **A instância MySQL não tem IP público liberado.** Não existe regra de firewall
  autorizando faixas de endereços, porque não há tráfego TCP vindo da internet.
- **A autorização é feita por IAM**, não por rede. A service account do Cloud Run recebe
  `roles/cloudsql.client`; sem essa role, o container sobe mas falha ao conectar. A
  identidade é o perímetro de segurança, não o endereço IP.
- **Não há credencial de conexão gerenciada pela aplicação além da senha do usuário
  MySQL** — o transporte já é autenticado pela plataforma.

Isso elimina uma classe inteira de erro de configuração: o clássico "liberei
`0.0.0.0/0` no firewall do banco porque o IP da aplicação é dinâmico". Em um runtime
serverless, onde o IP de saída **é** dinâmico por definição, um banco que autoriza por
IP praticamente força essa má configuração. O socket via IAM contorna o problema na raiz.

---

## 6. Secret Manager: segredo injetado sem código de integração

A connection string de produção — que contém a senha do banco — não está em nenhum
arquivo do repositório. Ela vive no Secret Manager e é injetada assim:

```powershell
--set-secrets="ConnectionStrings__DefaultConnection=estetica-db-connection:latest"
```

O detalhe técnico que torna isso elegante: **o duplo underscore é a convenção do
ASP.NET Core para hierarquia de configuração**. A variável de ambiente
`ConnectionStrings__DefaultConnection` sobrescreve automaticamente o valor de
`ConnectionStrings:DefaultConnection` do `appsettings.json`, porque o
`WebApplication.CreateBuilder` já registra o *environment variables provider* com
precedência sobre os arquivos JSON.

**Resultado: zero linhas de código para ler o segredo.** Não há SDK do Secret Manager no
`.csproj`, não há chamada de API, não há cliente para autenticar. O
`builder.Configuration.GetConnectionString("DefaultConnection")` (`Program.cs:8`)
funciona igual em desenvolvimento (lendo o `appsettings.json`) e em produção (lendo o
segredo). É a convenção do framework encaixando na convenção da plataforma.

O mesmo mecanismo em Azure Key Vault ou AWS Secrets Manager tipicamente exige um pacote
NuGet e uma linha de configuração de provider. Menos código é menos superfície de erro.

Cuidados operacionais adotados no processo:

- A senha foi **gerada aleatoriamente** (28 caracteres, via `RandomNumberGenerator`),
  nunca digitada nem escolhida por humano.
- O valor foi enviado ao Secret Manager por **arquivo** (`--data-file`) e não como
  argumento de linha de comando, para não ficar registrado no histórico do PowerShell.
- O arquivo temporário ficou **fora do diretório do projeto**, sem risco de commit
  acidental.

---

## 7. Região `southamerica-east1` (São Paulo)

A aplicação atende uma estética automotiva no Brasil — os usuários são locais. O GCP
oferece região em São Paulo, e **tanto o Cloud Run quanto o Cloud SQL foram provisionados
nela**.

Dois efeitos:

- **Latência de usuário final** na casa de dezenas de milissegundos, contra 120–200 ms
  se a aplicação estivesse hospedada nos Estados Unidos.
- **Colocalização aplicação-banco.** Este é o ponto mais relevante em termos de
  performance. Uma aplicação MVC com Entity Framework faz múltiplas queries por
  requisição (listar atendimentos com seus serviços associados, via `Atendimento` →
  `AtendimentoServico` → `Servico`). Se o banco estivesse em outra região, cada query
  pagaria a latência inter-regional, e o efeito se multiplicaria pelo número de
  round-trips. Estando ambos em `southamerica-east1`, a latência de rede até o banco é
  sub-milissegundo.

Vale registrar que a região de São Paulo não é exclusividade do GCP — Azure e AWS também
têm presença no Brasil. Este critério **não é diferencial competitivo**, mas é um
requisito que o GCP atende, e que descartaria plataformas PaaS menores cujas regiões
disponíveis são só EUA e Europa.

---

## 8. Comparação com as alternativas consideradas

Como os créditos cobrem a fatura, **preço deixa de ser o critério de desempate** — e os
concorrentes também oferecem crédito promocional. A comparação abaixo pesa, portanto,
critérios técnicos: atrito de configuração, modelo de conexão ao banco, viabilidade do
build remoto e o que sobra funcionando quando o crédito acabar.

### 8.1 Azure App Service / Container Apps

**A favor:** integração natural com .NET, deploy direto do Visual Studio, familiaridade
maior no ecossistema Microsoft.

**Contra, no caso deste projeto:**

- O **Azure App Service** no plano Basic (B1) cobra por hora reservada,
  independentemente de uso — consome crédito 24h/dia para servir dezenas de requisições
  por dia, e **não tem nível gratuito permanente equivalente**: quando o crédito
  terminar, o serviço para ou vira fatura. O plano Free (F1) existe, mas tem cota de CPU
  diária e não suporta *always-on* adequadamente para container Linux customizado.
- O **Container Apps** escala a zero e é o competidor mais próximo do Cloud Run, mas é
  construído sobre KEDA/Dapr e expõe um modelo conceitualmente mais pesado
  (*environment*, *revision*, *scale rules*) para um único container HTTP. O Cloud Run é
  o abstração mais fina para exatamente este caso.
- **MySQL no Azure** existe (Azure Database for MySQL), mas a integração de rede é por
  *private endpoint* / VNet ou firewall por IP — não há equivalente direto do socket
  Unix com autorização por IAM. Em serverless com IP de saída dinâmico, isso adiciona
  configuração de VNet ao escopo.

### 8.2 AWS (App Runner / ECS Fargate + RDS)

**A favor:** maior maturidade e amplitude de serviços; ecossistema mais rico.

**Contra:**

- **App Runner** não escala a zero — mantém uma instância provisionada em modo
  reduzido, com custo contínuo.
- **ECS Fargate** escala a zero, mas exige montar VPC, subnets, security groups, task
  definition, cluster e Application Load Balancer para expor HTTPS. São ~10 recursos
  interdependentes contra 4 no GCP — e o ALB é um componente cobrado por hora, que
  consome crédito continuamente e não desaparece quando o container escala a zero. Para
  um único container HTTP, é complexidade de configuração desproporcional.
- O **RDS MySQL** com conexão a partir de serverless recai no mesmo problema de
  autorização por rede.
- A complexidade operacional é significativamente maior: o deploy no GCP são **6
  comandos `gcloud`**; o equivalente na AWS envolveria dezenas de recursos ou uma
  ferramenta de IaC.

### 8.3 PaaS simplificadas (Render, Railway, Fly.io, Heroku)

**A favor:** setup mais rápido ainda, git-push-to-deploy, curva de aprendizado quase
nula.

**Contra:**

- No tier gratuito, tipicamente **hibernam com cold start de dezenas de segundos** —
  bem pior que o do Cloud Run.
- **MySQL gerenciado é limitado ou pago à parte**; vários oferecem só PostgreSQL no
  plano free, o que exigiria trocar o provider do EF e reescrever as migrations. E como
  os créditos disponíveis são do GCP, um banco pago nessas plataformas sairia do bolso —
  enquanto o Cloud SQL está coberto.
- **Regiões disponíveis raramente incluem o Brasil**, o que quebra tanto a latência do
  usuário quanto a colocalização com o banco.
- Valor educacional menor: o objetivo do trabalho inclui entender **IAM, segredos,
  registry de imagens e rede gerenciada**. Uma PaaS que abstrai tudo isso entrega o
  deploy funcionando, mas não os conceitos.

### 8.4 VPS / servidor próprio

**A favor:** custo previsível, controle total.

**Contra:** exige administrar o sistema operacional, instalar e atualizar o runtime
.NET, configurar Nginx como reverse proxy, obter e renovar certificado TLS
(Let's Encrypt + cron), instalar e fazer backup do MySQL, e monitorar tudo. É o oposto
do requisito do projeto: nem .NET SDK nem Docker existem localmente, exatamente porque a
intenção era **não** gerenciar infraestrutura.

O Cloud Run entrega gratuitamente o que o VPS exigiria configurar à mão: HTTPS com
certificado gerenciado e renovado automaticamente, domínio `*.run.app` já provisionado,
balanceamento, health checks, logging centralizado e rollback por revisão.

### 8.5 Quadro consolidado

| Critério | Cloud Run | Azure App Service | ECS Fargate | Render / Railway | VPS |
|---|---|---|---|---|---|
| Escala a zero | ✅ | ❌ (B1) | ✅ | parcial | ❌ |
| Consumo de crédito ocioso | ≈ nulo | contínuo | contínuo (ALB) | — | contínuo |
| Compute segue grátis após os créditos | ✅ nível gratuito perene | ❌ | ❌ | c/ hibernação lenta | ❌ |
| Build remoto sem SDK local | ✅ Cloud Build | parcial | ❌ | ✅ | ❌ |
| MySQL gerenciado no plano viável | ✅ | ✅ (pago) | ✅ (pago) | limitado | manual |
| Conexão ao banco por identidade (IAM) | ✅ socket Unix | ❌ rede/IP | ❌ rede/IP | ❌ | ❌ |
| Região no Brasil | ✅ | ✅ | ✅ | raramente | depende |
| HTTPS gerenciado automático | ✅ | ✅ | via ALB | ✅ | manual |
| Nº de recursos a configurar | 4 | ~3 | ~10+ | 2 | tudo |
| Segredo sem código de integração | ✅ (`__`) | requer pacote | requer SDK | env var simples | manual |

---

## 9. Benefícios operacionais concretos obtidos

Não são promessas de marketing — são capacidades usadas e verificadas neste deploy.

**Versionamento por revisão e rollback em um comando.** Cada deploy cria uma revisão
imutável. Voltar atrás não requer rebuild:

```powershell
gcloud run services update-traffic estetica --to-revisions=estetica-00001-qh8=100
```

**Configuração persistente entre deploys.** O segundo deploy não precisa repetir
`--add-cloudsql-instances` nem `--set-secrets`; o serviço preserva o que não foi
informado. Publicar uma nova versão são dois comandos.

**Deploy idempotente e automatizado.** O `deploy.ps1` do projeto executa quantas vezes
for necessário: na primeira, provisiona a infraestrutura inteira; nas seguintes, só
reconstrói a imagem e publica uma revisão (`-SomenteApp`). Ele até religa a instância do
Cloud SQL se estiver desligada, porque a aplicação aplica migrations no startup e falharia
sem o banco. Essa idempotência só é viável porque os comandos `gcloud` são declarativos.

**Logs sem infraestrutura adicional.** O stdout do container vai automaticamente para o
Cloud Logging; foi por ali que se confirmou a aplicação das três migrations.

**Controle explícito do consumo de créditos.** Este ambiente é custeado por **créditos
gratuitos do GCP**, então não há desembolso — mas crédito é um orçamento finito, e vale
saber onde ele é gasto. O ponto dominante **não é o Cloud Run**, que escala a zero: é o
**Cloud SQL**, cobrado por hora ligada independentemente de uso (`db-f1-micro`, faixa de
R$ 50–90 equivalentes por mês rodando 24h). Como a aplicação é usada esporadicamente, a
instância pode ser desligada entre os usos, preservando os dados:

```powershell
# desligar — mantém os dados, paga-se só o armazenamento
gcloud sql instances patch estetica-mysql --activation-policy=NEVER

# religar antes de usar
gcloud sql instances patch estetica-mysql --activation-policy=ALWAYS
```

Com a instância desligada, os dados permanecem e o consumo cai para o armazenamento
apenas — o que estende os créditos de poucos meses para bem mais. O `deploy.ps1` já
contempla isso: ele **religa a instância automaticamente** se estiver desligada, porque a
aplicação aplica migrations no startup e falharia sem banco.

**Cenário pós-créditos.** Quando os créditos expirarem, o compute continua no nível
gratuito permanente do Cloud Run — a fatura restante é essencialmente o Cloud SQL, que
pode ser mantido desligado, migrado para uma instância menor, ou substituído. A aplicação
não precisa ser desmontada. Em plataformas de plano reservado, o fim do crédito significa
o fim do ambiente.

E o projeto inteiro pode ser apagado de uma vez (`gcloud projects delete`), zerando o
consumo — motivo pelo qual foi criado um **projeto GCP dedicado** em lugar de reaproveitar
outro: isola recursos, permissões, faturamento e ciclo de vida, e permite medir exatamente
quanto de crédito esta aplicação consumiu.

---

## 10. O que o GCP resolveu, e o que continuou sendo responsabilidade do código

Vale a honestidade de separar as duas coisas — a plataforma não resolve tudo.

**Resolvido pela plataforma:** HTTPS e certificado, escalabilidade horizontal, domínio
público, provisionamento e backup do MySQL, armazenamento de segredos, registry de
imagens, build em Linux, logging, health check, rollback.

**Continuou por conta do código, e exigiu quatro ajustes:**

1. `DockerFile` → `Dockerfile` — case sensitivity do Linux.
2. `ServerVersion.AutoDetect` → `Parse` — não depender do banco durante o boot.
3. `UseForwardedHeaders` — sem ele, `UseHttpsRedirection` entra em **loop infinito de
   redirecionamento** atrás do proxy que termina TLS. O container recebe HTTP,
   `Request.IsHttps` é `false`, o middleware responde 307 para HTTPS, o navegador volta
   ao proxy, o proxy repassa HTTP — e o ciclo recomeça. Os `Clear()` em
   `KnownNetworks`/`KnownProxies` são necessários porque o IP do proxy do Cloud Run não é
   fixo, e são seguros aqui porque o container só recebe tráfego através desse proxy.
4. `db.Database.Migrate()` no startup — contornar a ausência de .NET SDK local.

Nenhum desses ajustes é específico do GCP: os quatro seriam necessários em qualquer
runtime de container atrás de um proxy TLS gerenciado. É evidência adicional de que a
escolha **não introduziu acoplamento à plataforma** — apenas exigiu que a aplicação se
comportasse corretamente como container.

---

## 11. Conclusão

O GCP foi escolhido porque o **Cloud Run** é a plataforma cujo modelo de execução se
encaixa com menor atrito nas restrições reais deste projeto. Vale destacar que **o custo
não foi o critério decisório** — o ambiente é coberto por créditos gratuitos do GCP, e os
concorrentes também oferecem crédito promocional. A decisão se sustenta em encaixe
técnico:

1. **O projeto já era um container** — o Cloud Run roda a imagem como está, sem
   buildpack, sem SDK proprietário, sem dependência do Google no `.csproj`.
2. **Cloud Build compila sem toolchain local** — requisito eliminatório, dado que a
   máquina não tem .NET SDK nem Docker. E build em Linux revelou um bug que o Windows
   escondia.
3. **Escala a zero** — o padrão de tráfego é intermitente. Como o ambiente é custeado por
   créditos gratuitos, o ganho não é economia imediata, e sim **não queimar crédito
   durante os 99% do tempo em que a aplicação está ociosa**, além de absorver picos sem
   reprovisionar capacidade. E o nível gratuito permanente do Cloud Run cobre o compute
   deste projeto com folga, então a aplicação **continua no ar depois de os créditos
   expirarem** — o que não é verdade num plano de hora reservada.
4. **A integração Cloud Run ↔ Cloud SQL por socket Unix com autorização IAM** dispensa
   expor o banco à internet ou liberar faixas de IP — o problema exato que um runtime
   com IP de saída dinâmico cria nos concorrentes.
5. **O Secret Manager injeta o segredo como variável de ambiente** que a convenção de
   duplo underscore do ASP.NET Core consome sem uma linha de código adicional.
6. **Região em São Paulo** para aplicação e banco, garantindo latência baixa ao usuário
   e colocalização com o banco — crítico em MVC com múltiplas queries por requisição.
7. **Superfície operacional pequena**: 4 recursos, 6 comandos, um script de deploy
   idempotente, rollback em um comando.

A decisão também é **reversível**. Como a aplicação não carrega nenhuma dependência do
GCP em código, a mesma imagem pode migrar para outro runtime de containers trocando
apenas a origem da connection string. Escolher a plataforma que melhor serve hoje, sem
fechar a porta de amanhã, é o resultado que essa arquitetura entrega.

---

## Referências no repositório

- [`DEPLOY.md`](DEPLOY.md) — comandos executados, arquitetura e operação do dia a dia
- [`Dockerfile`](Dockerfile) — build multi-stage, porta 8080
- [`Program.cs`](Program.cs) — forwarded headers, `ServerVersion.Parse`, migrations no startup
- [`deploy.ps1`](deploy.ps1) — automação idempotente do provisionamento e deploy
- [`EsteticaPorDoSol.csproj`](EsteticaPorDoSol.csproj) — .NET 10, ausência de dependências do GCP
