# Estética Pôr do Sol

Sistema de controle de atendimentos de uma estética automotiva: clientes, veículos,
serviços e o histórico de entradas e saídas.

ASP.NET Core MVC (.NET 10) + Entity Framework Core + MySQL.

## Estrutura

```
.
├── docker-compose.yml     ambiente completo (aplicação + MySQL)
├── back-end/              código C#: controllers, models, EF Core, Dockerfile
├── front-end/             telas Razor e arquivos estáticos
├── tests/                 testes de unidade (xUnit)
└── docs/                  site de documentação (MkDocs)
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

Exige um MySQL acessível pela connection string do `appsettings.json`. Em vez dela, a
variável de ambiente `DB_CONNECTION_STRING` tem prioridade quando está definida — é por
ela que o ambiente publicado recebe a connection string.

## Testes

```powershell
dotnet test
```

## Branches

Esta é a `back-end`: além do código C#, ela carrega o `front-end/` porque o build
precisa das Views — o `.csproj` as compila dentro da própria DLL. A branch `front-end`
tem apenas as telas, como base do trabalho de separá-las em uma aplicação própria.

Os scripts e a documentação de deploy e de infraestrutura ficam na `main`.
