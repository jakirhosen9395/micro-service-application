# syntax=docker/dockerfile:1

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime-base
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system appuser \
    && useradd --system --gid appuser --create-home appuser

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY src/AdminService.Api/AdminService.Api.csproj src/AdminService.Api/
RUN dotnet restore src/AdminService.Api/AdminService.Api.csproj

COPY . .
RUN dotnet publish src/AdminService.Api/AdminService.Api.csproj \
    -c Release \
    -o /app/publish \
    /p:UseAppHost=false

FROM runtime-base AS final
WORKDIR /app

COPY --from=build --chown=appuser:appuser /app/publish .

ENV ADMIN_HOST=0.0.0.0
ENV ADMIN_PORT=8080
ENV ASPNETCORE_URLS=http://0.0.0.0:8080

EXPOSE 8080

USER appuser

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS -H "X-Forwarded-Proto: https" "http://127.0.0.1:8080/hello" || exit 1

ENTRYPOINT ["dotnet", "AdminService.Api.dll"]