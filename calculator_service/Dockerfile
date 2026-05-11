# syntax=docker/dockerfile:1.7

FROM maven:3.9.15-eclipse-temurin-25 AS build
WORKDIR /workspace
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2 mvn -q -DskipTests dependency:go-offline
COPY src ./src
RUN --mount=type=cache,target=/root/.m2 mvn -q -DskipTests package

FROM eclipse-temurin:25-jre AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system appuser \
    && useradd --system --gid appuser --create-home --home-dir /app --shell /usr/sbin/nologin appuser

WORKDIR /app

COPY --from=build --chown=appuser:appuser /workspace/target/calculator-service.jar /app/app.jar

ENV CALC_HOST=0.0.0.0
ENV CALC_PORT=8080

EXPOSE 8080

USER appuser

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/hello || exit 1

ENTRYPOINT ["java", "--enable-native-access=ALL-UNNAMED", "-XX:+EnableDynamicAgentLoading", "-jar", "/app/app.jar"]
