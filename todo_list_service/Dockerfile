FROM gradle:9.5.0-jdk25 AS build
WORKDIR /workspace
COPY settings.gradle build.gradle ./
COPY gradle ./gradle
COPY gradlew gradlew
COPY src ./src
RUN gradle --no-daemon clean bootJar -x test

FROM eclipse-temurin:25-jre
WORKDIR /app
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system appuser \
    && useradd --system --gid appuser --create-home --home-dir /app --shell /usr/sbin/nologin appuser
COPY --from=build --chown=appuser:appuser /workspace/build/libs/todo_list_service.jar /app/app.jar
ENV TODO_HOST=0.0.0.0
ENV TODO_PORT=8080
EXPOSE 8080
USER appuser
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/hello || exit 1
ENTRYPOINT ["java", "--enable-native-access=ALL-UNNAMED", "--sun-misc-unsafe-memory-access=allow", "-XX:+EnableDynamicAgentLoading", "-Dlogback.statusListenerClass=ch.qos.logback.core.status.NopStatusListener", "-Dspring.main.banner-mode=off", "-jar", "/app/app.jar"]
