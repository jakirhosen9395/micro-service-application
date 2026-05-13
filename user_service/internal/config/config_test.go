package config

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestEnvFilesHaveIdenticalKeysInOrder(t *testing.T) {
	root := filepath.Join("..", "..")
	baseline := keys(t, filepath.Join(root, ".env.dev"))
	for _, name := range []string{".env.stage", ".env.prod", ".env.example"} {
		got := keys(t, filepath.Join(root, name))
		if len(got) != len(baseline) {
			t.Fatalf("%s key count=%d want %d", name, len(got), len(baseline))
		}
		for i := range baseline {
			if got[i] != baseline[i] {
				t.Fatalf("%s key[%d]=%s want %s", name, i, got[i], baseline[i])
			}
		}
	}
}

func keys(t *testing.T, path string) []string {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	var out []string
	s := bufio.NewScanner(f)
	for s.Scan() {
		line := strings.TrimSpace(s.Text())
		if line == "" || strings.HasPrefix(line, "#") || !strings.Contains(line, "=") {
			continue
		}
		out = append(out, strings.SplitN(line, "=", 2)[0])
	}
	if err := s.Err(); err != nil {
		t.Fatal(err)
	}
	return out
}

func TestForbiddenEnvKeysRejected(t *testing.T) {
	t.Setenv("USER_KAFKA_ENABLED", "false")
	cfg := Config{ServiceName: "user_service", Port: 8080, JWTAlgorithm: "HS256", S3Bucket: "microservice", PostgresSchema: "user_service", ReportAllowedFormats: []string{"pdf"}, ReportDefaultFormat: "pdf"}
	if err := cfg.Validate(); err == nil || !strings.Contains(err.Error(), "forbidden environment key") {
		t.Fatalf("expected forbidden key error, got %v", err)
	}
}

func TestGoModAndGoSumContract(t *testing.T) {
	root := filepath.Join("..", "..")
	gomod, err := os.ReadFile(filepath.Join(root, "go.mod"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(gomod)
	for _, want := range []string{"go 1.26", "toolchain go1.26.3"} {
		if !strings.Contains(text, want) {
			t.Fatalf("go.mod missing %s", want)
		}
	}
	if _, err := os.Stat(filepath.Join(root, "go.sum")); err != nil {
		t.Fatalf("go.sum must exist: %v", err)
	}
}
