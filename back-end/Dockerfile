# O contexto de build e a raiz do repositorio, porque a imagem precisa das duas
# pastas: o codigo C# em back-end/ e as Views + estaticos em front-end/.

# Etapa 1 — Build da aplicacao
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# O restore vem antes do resto do codigo para aproveitar o cache de camadas do Docker:
# so refaz o download dos pacotes quando o .csproj muda.
COPY back-end/*.csproj back-end/
RUN dotnet restore back-end/EsteticaPorDoSol.csproj

COPY back-end/ back-end/
COPY front-end/ front-end/
RUN dotnet publish back-end/EsteticaPorDoSol.csproj -c Release -o /app/publish

# Etapa 2 — Imagem final
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

# O publish ja traz as Views compiladas dentro da DLL e os estaticos do front-end
# copiados para ./wwwroot, entao a imagem final nao precisa das pastas de origem.
COPY --from=build /app/publish .

EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080

ENTRYPOINT ["dotnet", "EsteticaPorDoSol.dll"]
