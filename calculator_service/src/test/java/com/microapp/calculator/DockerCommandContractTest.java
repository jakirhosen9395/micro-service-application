package com.microapp.calculator;

import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class DockerCommandContractTest {
    @Test
    void dockerfileUsesJava25NonRootPort8080AndHelloHealthcheck() throws Exception {
        String dockerfile = Files.readString(Path.of("Dockerfile"));
        assertTrue(dockerfile.contains("maven:3.9.15-eclipse-temurin-25"));
        assertTrue(dockerfile.contains("eclipse-temurin:25-jre"));
        assertTrue(dockerfile.contains("EXPOSE 8080"));
        assertFalse(dockerfile.contains("EXPOSE 2020"));
        assertTrue(dockerfile.contains("USER appuser"));
        assertTrue(dockerfile.indexOf("RUN apt-get update") < dockerfile.indexOf("WORKDIR /app"));
        assertTrue(dockerfile.indexOf("RUN apt-get update") < dockerfile.indexOf("COPY --from=build"));
        assertTrue(dockerfile.contains("http://127.0.0.1:8080/hello"));
        assertTrue(dockerfile.contains("/app/app.jar"));
        assertTrue(dockerfile.contains("--enable-native-access=ALL-UNNAMED"));
        assertTrue(dockerfile.contains("-XX:+EnableDynamicAgentLoading"));
        assertFalse(dockerfile.contains("COPY .env"));
    }

    @Test
    void commandScriptUsesShAndRunsDevStageProdOnExpectedPorts() throws Exception {
        String command = Files.readString(Path.of("command.sh"));
        assertTrue(command.startsWith("#!/usr/bin/env sh\nset -eu"));
        assertFalse(command.contains("bash"));
        assertFalse(command.contains("case "));
        assertFalse(command.contains("curl "));
        assertTrue(command.contains("docker build --no-cache -t calculator_service:latest ."));
        assertTrue(command.contains("docker build -t calculator_service:dev ."));
        assertTrue(command.contains("docker build -t calculator_service:stage ."));
        assertTrue(command.contains("docker build -t calculator_service:prod ."));
        assertTrue(command.contains("--env-file .env.dev -p 2020:8080"));
        assertTrue(command.contains("--env-file .env.stage -p 2021:8080"));
        assertTrue(command.contains("--env-file .env.prod -p 2022:8080"));
    }
}
