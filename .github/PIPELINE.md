# Pipeline CI/CD

Build, validação e deploy automatizados no GitHub Actions, publicando no Cloud Run.

## Estratégia de branches

| Branch      | Papel                                                                 |
| ----------- | --------------------------------------------------------------------- |
| `main`      | Produção. Só recebe código por pull request. Todo push aqui publica.   |
| `dev`       | Integração. Recebe as features e é a origem dos PRs para a `main`.     |
| `feature/*` | Trabalho individual. Vira PR para a `dev`.                            |

Nenhum commit direto na `main`: o que chega lá passou por PR com o CI verde.

## Workflows

### `ci.yml` — validação

Roda em pull request para `main` ou `dev` e em push na `dev`. Três jobs em paralelo:

- **Build e artefatos** — checkout, `dotnet restore`, `dotnet build` em Release,
  `dotnet publish` e upload do artefato (retido por 14 dias). Fecha construindo a
  imagem com o mesmo `Dockerfile` usado no deploy.
- **Qualidade de código** — `dotnet format --verify-no-changes` (lint, bloqueante),
  avisos do compilador registrados no resumo da execução e varredura de
  dependências vulneráveis com `dotnet list package --vulnerable`.
- **CodeQL** — análise estática de segurança. Os alertas aparecem na aba
  _Security_ do repositório.

Qualquer job vermelho interrompe a pipeline e bloqueia o merge.

### `deploy.yml` — publicação

Roda em push na `main` (ou seja, no merge do PR) e também sob demanda pelo
`workflow_dispatch`. Etapas:

1. Autenticação no Google Cloud por Workload Identity Federation.
2. Religa a instância do Cloud SQL se ela estiver parada — a aplicação aplica
   migrations no startup e não sobe sem banco.
3. `gcloud builds submit` constrói a imagem, marcada com o SHA do commit.
4. `gcloud run deploy` publica a revisão com o Cloud SQL anexado e a connection
   string vinda do Secret Manager. O Cloud Run substitui a revisão ativa e
   direciona o tráfego automaticamente.
5. Valida o deploy fazendo uma requisição HTTP no serviço, com até 3 tentativas.
   O job falha se a aplicação não responder 2xx/3xx, mesmo com a revisão no ar.

O `concurrency` impede dois deploys simultâneos: sem isso, um merge mais lento
poderia sobrescrever uma revisão mais nova.

## Configuração (uma vez só)

A pipeline autentica sem chave: o GitHub emite um token OIDC e o Google troca por
credenciais de curta duração. Rode os comandos abaixo com uma conta que tenha
permissão de administrador no projeto.

```powershell
gcloud iam service-accounts create github-actions --project=estetica-por-do-sol --display-name="Deploy via GitHub Actions"

gcloud iam workload-identity-pools create github --project=estetica-por-do-sol --location=global --display-name="GitHub"

gcloud iam workload-identity-pools providers create-oidc github-actions --project=estetica-por-do-sol --location=global --workload-identity-pool=github --display-name="GitHub Actions" --issuer-uri="https://token.actions.githubusercontent.com" --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" --attribute-condition="assertion.repository=='DaviMak/EsteticaPorDoSol'"
```

O `--attribute-condition` é o que impede outro repositório de assumir esta
identidade. Em seguida, autorize o repositório a personificar a service account:

```powershell
gcloud iam service-accounts add-iam-policy-binding github-actions@estetica-por-do-sol.iam.gserviceaccount.com --project=estetica-por-do-sol --role=roles/iam.workloadIdentityUser --member="principalSet://iam.googleapis.com/projects/935668627687/locations/global/workloadIdentityPools/github/attribute.repository/DaviMak/EsteticaPorDoSol"
```

E conceda os papéis que o deploy usa:

```powershell
gcloud projects add-iam-policy-binding estetica-por-do-sol --member="serviceAccount:github-actions@estetica-por-do-sol.iam.gserviceaccount.com" --role=roles/run.admin
gcloud projects add-iam-policy-binding estetica-por-do-sol --member="serviceAccount:github-actions@estetica-por-do-sol.iam.gserviceaccount.com" --role=roles/cloudbuild.builds.editor
gcloud projects add-iam-policy-binding estetica-por-do-sol --member="serviceAccount:github-actions@estetica-por-do-sol.iam.gserviceaccount.com" --role=roles/artifactregistry.writer
gcloud projects add-iam-policy-binding estetica-por-do-sol --member="serviceAccount:github-actions@estetica-por-do-sol.iam.gserviceaccount.com" --role=roles/storage.admin
gcloud projects add-iam-policy-binding estetica-por-do-sol --member="serviceAccount:github-actions@estetica-por-do-sol.iam.gserviceaccount.com" --role=roles/cloudsql.editor
gcloud projects add-iam-policy-binding estetica-por-do-sol --member="serviceAccount:github-actions@estetica-por-do-sol.iam.gserviceaccount.com" --role=roles/iam.serviceAccountUser
```

Por fim, em _Settings → Secrets and variables → Actions_ no GitHub, crie:

| Secret                | Valor                                                                                                   |
| --------------------- | ------------------------------------------------------------------------------------------------------- |
| `WIF_PROVIDER`        | `projects/935668627687/locations/global/workloadIdentityPools/github/providers/github-actions`             |
| `WIF_SERVICE_ACCOUNT` | `github-actions@estetica-por-do-sol.iam.gserviceaccount.com`                                              |

## Evidências

- **Execuções e histórico** — aba _Actions_ do repositório, com duração de cada
  job e de cada etapa.
- **Logs** — abrindo qualquer execução; ficam retidos junto do histórico.
- **Artefatos** — anexados à execução do CI, baixáveis pela página do run.
- **Falhas e sucessos** — o status colorido de cada execução na lista, e o check
  do CI dentro do próprio pull request.
- **Deploy** — o resumo do job de deploy traz URL, imagem publicada, commit e o
  código HTTP da validação.

## Deploy manual

O `deploy.ps1` continua sendo a ferramenta para provisionar ou alterar a
infraestrutura (criar instância, banco, secret, permissões). A pipeline cobre
apenas o ciclo de build e publicação, equivalente a `deploy.ps1 -SomenteApp`.
