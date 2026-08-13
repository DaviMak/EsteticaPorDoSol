# back-end

Aplicação ASP.NET Core MVC (.NET 10) com Entity Framework Core e MySQL.

| Pasta | Conteúdo |
|---|---|
| `Controllers/` | Ações que respondem às rotas e devolvem as Views |
| `Models/` | Entidades mapeadas pelo EF Core |
| `Data/` | `ApplicationDbContext` |
| `Migrations/` | Histórico de alterações do banco |
| `Properties/` | `launchSettings.json` (perfis de execução local) |

As telas ficam em `../front-end/`. Só o código C# mora aqui.

## Rodar localmente

```powershell
dotnet run
```

Precisa de um MySQL acessível pela connection string do `appsettings.json`. Para subir
o banco junto com a aplicação em containers, use o `docker compose up` da raiz.

## Como as duas pastas se encaixam

O `.csproj` alcança o front-end por dois caminhos:

- **Views** — entram como `Content` apontando para `../front-end/Views`, com
  `LinkBase="Views"`. O Razor compila cada `.cshtml` dentro da DLL usando esse caminho
  lógico, então o MVC continua achando as telas normalmente.
- **wwwroot** — entra como `None` com `CopyToPublishDirectory`, que copia os arquivos
  para `wwwroot/` ao lado do binário no publish. Não podem ser `Content`: aí o SDK os
  trataria como *static web assets*, e esse pipeline assume que o `wwwroot` fica dentro
  da pasta do projeto — o app quebraria no startup procurando `back-end\wwwroot`.

O `Program.cs` fecha o ciclo escolhendo o `WebRootPath`: o `wwwroot` publicado quando
ele existe, senão `../front-end/wwwroot` (o caso do `dotnet run`).

Um efeito colateral dessa divisão: o **CSS isolado** (`.cshtml.css`) deixou de funcionar,
porque o SDK exige que esses arquivos estejam dentro da pasta do projeto. O único
existente era o boilerplate do template, cujas regras não casavam com nenhum elemento do
`_Layout.cshtml` — desligá-lo não mudou a aparência do site. Estilos novos vão em
`front-end/wwwroot/css/site.css`.
