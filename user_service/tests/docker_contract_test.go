package tests

import (
	"os"
	"strings"
	"testing"
)

func TestDockerfileContract(t *testing.T) {
	b, err := os.ReadFile("../Dockerfile")
	if err != nil {
		t.Fatal(err)
	}
	text := string(b)
	for _, want := range []string{"FROM golang:1.26.3-alpine AS builder", "FROM alpine:3.22", "EXPOSE 8080", "/hello", "USER appuser", "ENTRYPOINT", "rm -f go.sum", "go mod tidy", "go build -mod=mod"} {
		if !strings.Contains(text, want) {
			t.Fatalf("Dockerfile missing %s", want)
		}
	}
	if strings.Contains(text, "COPY .env") {
		t.Fatalf("Dockerfile must not copy env files")
	}
}

func TestCommandScriptContract(t *testing.T) {
	b, err := os.ReadFile("../command.sh")
	if err != nil {
		t.Fatal(err)
	}
	text := string(b)
	for _, want := range []string{"#!/usr/bin/env sh", "docker build --no-cache -t user_service:latest .", "-p 4040:8080", "-p 4041:8080", "-p 4042:8080"} {
		if !strings.Contains(text, want) {
			t.Fatalf("command.sh missing %s", want)
		}
	}
	if strings.Contains(text, "curl ") || strings.Contains(text, "case ") {
		t.Fatalf("command.sh must be fixed script without curl smoke tests or dynamic args")
	}
}
