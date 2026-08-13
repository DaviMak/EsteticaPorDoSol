# Estética Pôr do Sol

Sistema de controle de atendimentos de uma estética automotiva: clientes, veículos,
serviços e o histórico de entradas e saídas.

ASP.NET Core MVC (.NET 10) + Entity Framework Core + MySQL.

## Estrutura

```
.
├── docker-compose.yml     ambiente completo (aplicação + MySQL)
├── cloudbuild.yaml        build da imagem no Google Cloud Build
├── back-end/              código C#: controllers, models, EF Core, Dockerfile
├── front-end/             telas Razor e arquivos estáticos
└── infra/                 scripts de provisionamento das VMs no GCP
```

As duas pastas formam **uma única aplicação**: o ASP.NET renderiza as Views do front-end
no próprio processo. Os READMEs de cada pasta explicam como elas se conectam.

## Subir o ambiente local

```powershell
docker compose up -d --build
```

Aplicação em http://localhost:8080. O MySQL sobe junto, com volume persistente, e a
aplicação espera o banco ficar saudável antes de aplicar as migrations.

Para mudar portas ou senha, copie `.env.example` para `.env` e ajuste — útil quando a
porta 3306 já está ocupada por um MySQL instalado na máquina:

```powershell
Copy-Item .env.example .env
```

Encerrar (o `-v` também apaga os dados do banco):

```powershell
docker compose down
```

## Rodar sem containers

```powershell
cd back-end
dotnet run
```

Exige um MySQL acessível pela connection string do `appsettings.json`.

## Deploy

A aplicação roda no Cloud Run. O processo, os comandos e as decisões de arquitetura
estão em [DEPLOY.md](DEPLOY.md); o push na `main` dispara o deploy automático pelo
workflow `.github/workflows/deploy.yml`.
