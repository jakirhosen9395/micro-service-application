package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"user_service/internal/cache"
	"user_service/internal/config"
	"user_service/internal/health"
	"user_service/internal/httpapi"
	"user_service/internal/kafka"
	"user_service/internal/logging"
	"user_service/internal/mongolog"
	"user_service/internal/persistence"
	"user_service/internal/s3audit"

	"go.elastic.co/apm/module/apmhttp/v2"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load()
	if err != nil {
		fallback := logging.New(config.Config{ServiceName: "user_service", Environment: "unknown", Version: "v1.0.0", Tenant: "unknown"})
		fallback.Error("config.validation.failed", "configuration validation failed", nil, err)
		os.Exit(1)
	}
	cfg.ConfigureElasticAPMEnv()
	log := logging.New(cfg)
	log.Info("application.starting", "starting user_service", map[string]any{"service": cfg.ServiceName, "environment": cfg.Environment})

	startupCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	repo, err := persistence.NewPostgres(startupCtx, cfg)
	if err != nil {
		log.Error("postgres.connect.failed", "failed to connect to PostgreSQL", map[string]any{"dependency": "postgres"}, err)
		os.Exit(1)
	}
	defer repo.Close()

	if err := repo.Migrate(startupCtx, migrationsDir()); err != nil {
		log.Error("postgres.migration.failed", "failed to apply PostgreSQL migrations", map[string]any{"dependency": "postgres"}, err)
		os.Exit(1)
	}
	log.Info("postgres.migration.succeeded", "PostgreSQL migrations applied", map[string]any{"dependency": "postgres"})

	redisClient, err := cache.New(startupCtx, cfg)
	if err != nil {
		log.Error("redis.connect.failed", "failed to connect to Redis", map[string]any{"dependency": "redis"}, err)
		os.Exit(1)
	}
	defer redisClient.Close()

	auditWriter, err := s3audit.New(startupCtx, cfg)
	if err != nil {
		log.Error("s3.connect.failed", "failed to initialize S3 audit writer", map[string]any{"dependency": "s3"}, err)
		os.Exit(1)
	}

	mongoWriter, err := mongolog.New(startupCtx, cfg)
	if err != nil {
		log.Error("mongodb.connect.failed", "failed to initialize MongoDB structured logging", map[string]any{"dependency": "mongodb"}, err)
		os.Exit(1)
	}
	defer mongoWriter.Close(context.Background())
	log.AttachMongoSink(mongoWriter)

	bus, err := kafka.New(startupCtx, cfg, log, repo)
	if err != nil {
		log.Error("kafka.connect.failed", "failed to initialize Kafka", map[string]any{"dependency": "kafka"}, err)
		os.Exit(1)
	}
	defer bus.Close()
	bus.Start(ctx)

	checker := health.New(cfg, repo, redisClient, bus, auditWriter, mongoWriter)
	router := httpapi.New(cfg, log, repo, redisClient, auditWriter, checker)
	server := &http.Server{Addr: cfg.Address(), Handler: apmhttp.Wrap(router), ReadHeaderTimeout: 10 * time.Second, ReadTimeout: 30 * time.Second, WriteTimeout: 60 * time.Second, IdleTimeout: 120 * time.Second}

	go func() {
		log.Info("application.started", "user_service started", map[string]any{"host": cfg.Host, "port": cfg.Port, "environment": cfg.Environment})
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("http.server.failed", "HTTP server failed", nil, err)
			stop()
		}
	}()

	<-ctx.Done()
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer shutdownCancel()
	log.Info("application.stopping", "stopping user_service", nil)
	_ = server.Shutdown(shutdownCtx)
	log.Info("application.stopped", "user_service stopped", nil)
}

func migrationsDir() string {
	if v := os.Getenv("USER_MIGRATIONS_DIR"); v != "" {
		return v
	}
	candidates := []string{"migrations", "/app/migrations"}
	if exe, err := os.Executable(); err == nil {
		candidates = append(candidates, filepath.Join(filepath.Dir(exe), "migrations"))
	}
	for _, c := range candidates {
		if stat, err := os.Stat(c); err == nil && stat.IsDir() {
			return c
		}
	}
	return "migrations"
}
