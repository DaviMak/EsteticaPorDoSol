# front-end

Camada de apresentação da aplicação: as telas e os arquivos estáticos.

| Pasta | Conteúdo |
|---|---|
| `Views/` | Telas Razor (`.cshtml`), organizadas por controller |
| `Views/Shared/` | `_Layout.cshtml`, página de erro e partials |
| `wwwroot/css/` | `site.css` — folha de estilos do site |
| `wwwroot/js/` | `site.js` |
| `wwwroot/favicon.ico` | Ícone da aba |

## Como isso é servido

As Views são Razor: quem as renderiza é a aplicação ASP.NET em `../back-end`, no mesmo
processo. Esta pasta não tem servidor, build nem `package.json` próprios — editar um
`.cshtml` ou o `site.css` e recarregar a página é todo o fluxo de trabalho.

O `.csproj` do back-end referencia estes arquivos por caminho relativo; a explicação de
como isso é montado está no `README.md` de lá.

## Cuidados ao mexer

- **Mover ou renomear esta pasta quebra o build** do back-end, que a procura como
  `../front-end`.
- **Arquivos `.cshtml.css` (CSS isolado) não funcionam aqui** — o SDK do ASP.NET só os
  processa dentro da pasta do projeto .NET. Coloque os estilos em `wwwroot/css/site.css`.
- **Bootstrap e jQuery** são referenciados em `_Layout.cshtml` por `~/lib/...`, uma pasta
  que o `.gitignore` não versiona. O CDN da jsDelivr no mesmo arquivo é o que sustenta o
  layout na prática.
