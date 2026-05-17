package config

import (
	"bufio"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const Prefix = "USER"

// Config is the canonical user_service runtime configuration. Every field maps to
// a USER_* environment variable from the unified build contract.
type Config struct {
	ServiceName string
	Environment string
	NodeEnv     string
	Version     string
	Tenant      string

	Host string
	Port int

	JWTSecret    string
	JWTIssuer    string
	JWTAudience  string
	JWTAlgorithm string
	JWTLeeway    time.Duration

	PostgresHost          string
	PostgresPort          int
	PostgresUser          string
	PostgresPassword      string
	PostgresDB            string
	PostgresSchema        string
	PostgresPoolSize      int
	PostgresMaxOverflow   int
	PostgresMigrationMode string

	RedisHost            string
	RedisPort            int
	RedisPassword        string
	RedisDB              int
	RedisCacheTTLSeconds int

	KafkaBootstrapServers []string
	KafkaEventsTopic      string
	KafkaDeadLetterTopic  string
	KafkaConsumerGroup    string
	KafkaConsumeTopics    []string
	KafkaAutoCreateTopics bool

	S3Endpoint       string
	S3AccessKey      string
	S3SecretKey      string
	S3Region         string
	S3ForcePathStyle bool
	S3Bucket         string
	S3AuditPrefix    string
	S3ReportPrefix   string

	MongoHost          string
	MongoPort          int
	MongoUsername      string
	MongoPassword      string
	MongoDatabase      string
	MongoAuthSource    string
	MongoLogCollection string

	APMServerURL             string
	APMSecretToken           string
	APMTransactionSampleRate string
	APMCaptureBody           string
	ElasticsearchURL         string
	ElasticsearchUsername    string
	ElasticsearchPassword    string
	KibanaURL                string
	KibanaUsername           string
	KibanaPassword           string

	LogLevel        string
	LogFormat       string
	LogstashEnabled bool
	LogstashHost    string
	LogstashPort    int

	CORSAllowedOrigins   []string
	CORSAllowedMethods   []string
	CORSAllowedHeaders   []string
	CORSAllowCredentials bool
	CORSMaxAgeSeconds    int

	SecurityRequireHTTPS       bool
	SecuritySecureCookies      bool
	SecurityRequireTenantMatch bool

	DefaultTimezone             string
	DefaultLocale               string
	DefaultTheme                string
	AccessRequestDefaultTTLDays int
	AccessRequestMaxTTLDays     int
	ReportDefaultFormat         string
	ReportAllowedFormats        []string
}

func Load() (Config, error) {
	_ = loadDefaultEnvFile()
	cfg := Config{
		ServiceName: getenv("USER_SERVICE_NAME", "user_service"),
		Environment: getenv("USER_ENV", "development"),
		NodeEnv:     getenv("USER_NODE_ENV", "development"),
		Version:     getenv("USER_VERSION", "v1.0.0"),
		Tenant:      getenv("USER_TENANT", "dev"),
		Host:        getenv("USER_HOST", "0.0.0.0"),
		Port:        mustInt("USER_PORT", 8080),

		JWTSecret:    os.Getenv("USER_JWT_SECRET"),
		JWTIssuer:    getenv("USER_JWT_ISSUER", "auth"),
		JWTAudience:  getenv("USER_JWT_AUDIENCE", "micro-app"),
		JWTAlgorithm: strings.ToUpper(getenv("USER_JWT_ALGORITHM", "HS256")),
		JWTLeeway:    time.Duration(mustInt("USER_JWT_LEEWAY_SECONDS", 5)) * time.Second,

		PostgresHost:          getenv("USER_POSTGRES_HOST", "172.31.40.64"),
		PostgresPort:          mustInt("USER_POSTGRES_PORT", 5432),
		PostgresUser:          os.Getenv("USER_POSTGRES_USER"),
		PostgresPassword:      os.Getenv("USER_POSTGRES_PASSWORD"),
		PostgresDB:            os.Getenv("USER_POSTGRES_DB"),
		PostgresSchema:        getenv("USER_POSTGRES_SCHEMA", "user_service"),
		PostgresPoolSize:      mustInt("USER_POSTGRES_POOL_SIZE", 10),
		PostgresMaxOverflow:   mustInt("USER_POSTGRES_MAX_OVERFLOW", 10),
		PostgresMigrationMode: getenv("USER_POSTGRES_MIGRATION_MODE", "auto"),

		RedisHost:            getenv("USER_REDIS_HOST", "172.31.40.64"),
		RedisPort:            mustInt("USER_REDIS_PORT", 6379),
		RedisPassword:        os.Getenv("USER_REDIS_PASSWORD"),
		RedisDB:              mustInt("USER_REDIS_DB", 0),
		RedisCacheTTLSeconds: mustInt("USER_REDIS_CACHE_TTL_SECONDS", 300),

		KafkaBootstrapServers: splitCSV(getenv("USER_KAFKA_BOOTSTRAP_SERVERS", "172.31.40.64:9092")),
		KafkaEventsTopic:      getenv("USER_KAFKA_EVENTS_TOPIC", "user.events"),
		KafkaDeadLetterTopic:  getenv("USER_KAFKA_DEAD_LETTER_TOPIC", "user_service.dead-letter"),
		KafkaConsumerGroup:    getenv("USER_KAFKA_CONSUMER_GROUP", "user_service-development"),
		KafkaConsumeTopics:    splitCSV(getenv("USER_KAFKA_CONSUME_TOPICS", "auth.events,auth.admin.requests,auth.admin.decisions,admin.events,user.events,calculator.events,todo.events,report.events,access.events")),
		KafkaAutoCreateTopics: mustBool("USER_KAFKA_AUTO_CREATE_TOPICS", true),

		S3Endpoint:       getenv("USER_S3_ENDPOINT", "http://172.31.40.64:9000"),
		S3AccessKey:      os.Getenv("USER_S3_ACCESS_KEY"),
		S3SecretKey:      os.Getenv("USER_S3_SECRET_KEY"),
		S3Region:         getenv("USER_S3_REGION", "us-east-1"),
		S3ForcePathStyle: mustBool("USER_S3_FORCE_PATH_STYLE", true),
		S3Bucket:         getenv("USER_S3_BUCKET", "microservice"),
		S3AuditPrefix:    getenv("USER_S3_AUDIT_PREFIX", "user_service/development"),
		S3ReportPrefix:   getenv("USER_S3_REPORT_PREFIX", "report_service/development"),

		MongoHost:          getenv("USER_MONGO_HOST", "172.31.40.64"),
		MongoPort:          mustInt("USER_MONGO_PORT", 27017),
		MongoUsername:      os.Getenv("USER_MONGO_USERNAME"),
		MongoPassword:      os.Getenv("USER_MONGO_PASSWORD"),
		MongoDatabase:      getenv("USER_MONGO_DATABASE", "db_micro_services"),
		MongoAuthSource:    getenv("USER_MONGO_AUTH_SOURCE", "admin"),
		MongoLogCollection: getenv("USER_MONGO_LOG_COLLECTION", "user_service_development_logs"),

		APMServerURL:             getenv("USER_APM_SERVER_URL", "http://172.31.40.64:8200"),
		APMSecretToken:           os.Getenv("USER_APM_SECRET_TOKEN"),
		APMTransactionSampleRate: getenv("USER_APM_TRANSACTION_SAMPLE_RATE", "1.0"),
		APMCaptureBody:           getenv("USER_APM_CAPTURE_BODY", "errors"),
		ElasticsearchURL:         getenv("USER_ELASTICSEARCH_URL", "http://172.31.40.64:9200"),
		ElasticsearchUsername:    getenv("USER_ELASTICSEARCH_USERNAME", "elastic"),
		ElasticsearchPassword:    os.Getenv("USER_ELASTICSEARCH_PASSWORD"),
		KibanaURL:                getenv("USER_KIBANA_URL", "http://172.31.40.64:5601"),
		KibanaUsername:           getenv("USER_KIBANA_USERNAME", "elastic"),
		KibanaPassword:           os.Getenv("USER_KIBANA_PASSWORD"),

		LogLevel:        getenv("USER_LOG_LEVEL", "info"),
		LogFormat:       getenv("USER_LOG_FORMAT", "pretty-json"),
		LogstashEnabled: mustBool("USER_LOGSTASH_ENABLED", false),
		LogstashHost:    getenv("USER_LOGSTASH_HOST", "172.31.40.64"),
		LogstashPort:    mustInt("USER_LOGSTASH_PORT", 5000),

		CORSAllowedOrigins:   splitCSV(getenv("USER_CORS_ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:5173")),
		CORSAllowedMethods:   splitCSV(getenv("USER_CORS_ALLOWED_METHODS", "GET,POST,PUT,PATCH,DELETE,OPTIONS")),
		CORSAllowedHeaders:   splitCSV(getenv("USER_CORS_ALLOWED_HEADERS", "Authorization,Content-Type,X-Request-ID,X-Trace-ID,X-Correlation-ID")),
		CORSAllowCredentials: mustBool("USER_CORS_ALLOW_CREDENTIALS", true),
		CORSMaxAgeSeconds:    mustInt("USER_CORS_MAX_AGE_SECONDS", 3600),

		SecurityRequireHTTPS:       mustBool("USER_SECURITY_REQUIRE_HTTPS", false),
		SecuritySecureCookies:      mustBool("USER_SECURITY_SECURE_COOKIES", false),
		SecurityRequireTenantMatch: mustBool("USER_SECURITY_REQUIRE_TENANT_MATCH", true),

		DefaultTimezone:             getenv("USER_DEFAULT_TIMEZONE", "Asia/Dhaka"),
		DefaultLocale:               getenv("USER_DEFAULT_LOCALE", "en"),
		DefaultTheme:                getenv("USER_DEFAULT_THEME", "dark"),
		AccessRequestDefaultTTLDays: mustInt("USER_ACCESS_REQUEST_DEFAULT_TTL_DAYS", 30),
		AccessRequestMaxTTLDays:     mustInt("USER_ACCESS_REQUEST_MAX_TTL_DAYS", 90),
		ReportDefaultFormat:         getenv("USER_REPORT_DEFAULT_FORMAT", "pdf"),
		ReportAllowedFormats:        splitCSV(getenv("USER_REPORT_ALLOWED_FORMATS", "pdf,csv,json,html,xlsx")),
	}
	return cfg, cfg.Validate()
}

func (c Config) Validate() error {
	for _, key := range ForbiddenKeys() {
		if _, exists := os.LookupEnv(key); exists {
			return fmt.Errorf("forbidden environment key %s is not allowed; infrastructure integrations must not be disabled or replaced", key)
		}
	}
	var missing []string
	for _, key := range RequiredKeys() {
		if strings.TrimSpace(os.Getenv(key)) == "" {
			missing = append(missing, key)
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("missing required environment keys: %s", strings.Join(missing, ", "))
	}
	if c.ServiceName != "user_service" {
		return fmt.Errorf("USER_SERVICE_NAME must be user_service, got %q", c.ServiceName)
	}
	if c.Port != 8080 {
		return fmt.Errorf("USER_PORT must be 8080, got %d", c.Port)
	}
	if c.JWTAlgorithm != "HS256" {
		return fmt.Errorf("only HS256 JWT validation is supported, got %q", c.JWTAlgorithm)
	}
	if c.S3Bucket != "microservice" {
		return fmt.Errorf("USER_S3_BUCKET must be microservice, got %q", c.S3Bucket)
	}
	if c.PostgresSchema != "user_service" {
		return fmt.Errorf("USER_POSTGRES_SCHEMA must be user_service, got %q", c.PostgresSchema)
	}
	if c.LogstashEnabled {
		return errors.New("USER_LOGSTASH_ENABLED must remain false in this build")
	}
	if !contains(c.ReportAllowedFormats, c.ReportDefaultFormat) {
		return fmt.Errorf("USER_REPORT_DEFAULT_FORMAT %q is not listed in USER_REPORT_ALLOWED_FORMATS", c.ReportDefaultFormat)
	}
	return nil
}

func ForbiddenKeys() []string {
	return []string{
		"USER_SWAGGER_ENABLED",
		"USER_OPENAPI_SERVER_URL",
		"USER_PUBLIC_BASE_URL",
		"USER_HTTP_PRETTY_JSON",
		"USER_STORE_BACKEND",
		"USER_POSTGRES_FALLBACK_TO_FILE",
		"USER_LOCAL_DATA_DIR",
		"USER_POSTGRES_AUTO_CREATE_TABLES",
		"USER_POSTGRES_AUTO_UPGRADE_SCHEMA",
		"USER_KAFKA_ENABLED",
		"USER_KAFKA_CONSUMER_ENABLED",
		"USER_KAFKA_LOCAL_FALLBACK",
		"USER_MONGO_LOGS_ENABLED",
		"USER_PROJECTION_CALCULATOR_ENABLED",
		"USER_PROJECTION_TODO_ENABLED",
		"USER_PROJECTION_REPORT_ENABLED",
		"USER_PROJECTION_ACCESS_ENABLED",
		"USER_SECURITY_ALLOW_DEV_TOKEN",
		"USER_S3_ENABLED",
		"USER_REDIS_ENABLED",
		"USER_POSTGRES_ENABLED",
		"USER_MONGO_ENABLED",
		"USER_APM_ENABLED",
		"USER_POSTGRES_REQUIRED",
		"USER_REDIS_REQUIRED",
		"USER_KAFKA_REQUIRED",
		"USER_S3_REQUIRED",
		"USER_MONGO_REQUIRED",
		"USER_APM_REQUIRED",
	}
}

func RequiredKeys() []string {
	return []string{
		"USER_SERVICE_NAME", "USER_ENV", "USER_NODE_ENV", "USER_VERSION", "USER_TENANT",
		"USER_HOST", "USER_PORT",
		"USER_JWT_SECRET", "USER_JWT_ISSUER", "USER_JWT_AUDIENCE", "USER_JWT_ALGORITHM", "USER_JWT_LEEWAY_SECONDS",
		"USER_POSTGRES_HOST", "USER_POSTGRES_PORT", "USER_POSTGRES_USER", "USER_POSTGRES_PASSWORD", "USER_POSTGRES_DB", "USER_POSTGRES_SCHEMA", "USER_POSTGRES_POOL_SIZE", "USER_POSTGRES_MAX_OVERFLOW", "USER_POSTGRES_MIGRATION_MODE",
		"USER_REDIS_HOST", "USER_REDIS_PORT", "USER_REDIS_PASSWORD", "USER_REDIS_DB", "USER_REDIS_CACHE_TTL_SECONDS",
		"USER_KAFKA_BOOTSTRAP_SERVERS", "USER_KAFKA_EVENTS_TOPIC", "USER_KAFKA_DEAD_LETTER_TOPIC", "USER_KAFKA_CONSUMER_GROUP", "USER_KAFKA_CONSUME_TOPICS", "USER_KAFKA_AUTO_CREATE_TOPICS",
		"USER_S3_ENDPOINT", "USER_S3_ACCESS_KEY", "USER_S3_SECRET_KEY", "USER_S3_REGION", "USER_S3_FORCE_PATH_STYLE", "USER_S3_BUCKET", "USER_S3_AUDIT_PREFIX", "USER_S3_REPORT_PREFIX",
		"USER_MONGO_HOST", "USER_MONGO_PORT", "USER_MONGO_USERNAME", "USER_MONGO_PASSWORD", "USER_MONGO_DATABASE", "USER_MONGO_AUTH_SOURCE", "USER_MONGO_LOG_COLLECTION",
		"USER_APM_SERVER_URL", "USER_APM_SECRET_TOKEN", "USER_APM_TRANSACTION_SAMPLE_RATE", "USER_APM_CAPTURE_BODY", "USER_ELASTICSEARCH_URL", "USER_ELASTICSEARCH_USERNAME", "USER_ELASTICSEARCH_PASSWORD", "USER_KIBANA_URL", "USER_KIBANA_USERNAME", "USER_KIBANA_PASSWORD",
		"USER_LOG_LEVEL", "USER_LOG_FORMAT", "USER_LOGSTASH_ENABLED", "USER_LOGSTASH_HOST", "USER_LOGSTASH_PORT",
		"USER_CORS_ALLOWED_ORIGINS", "USER_CORS_ALLOWED_METHODS", "USER_CORS_ALLOWED_HEADERS", "USER_CORS_ALLOW_CREDENTIALS", "USER_CORS_MAX_AGE_SECONDS",
		"USER_SECURITY_REQUIRE_HTTPS", "USER_SECURITY_SECURE_COOKIES", "USER_SECURITY_REQUIRE_TENANT_MATCH",
		"USER_DEFAULT_TIMEZONE", "USER_DEFAULT_LOCALE", "USER_DEFAULT_THEME", "USER_ACCESS_REQUEST_DEFAULT_TTL_DAYS", "USER_ACCESS_REQUEST_MAX_TTL_DAYS", "USER_REPORT_DEFAULT_FORMAT", "USER_REPORT_ALLOWED_FORMATS",
	}
}

func (c Config) Address() string { return fmt.Sprintf("%s:%d", c.Host, c.Port) }

func (c Config) PostgresDSN() string {
	q := url.Values{}
	q.Set("sslmode", "disable")
	q.Set("search_path", c.PostgresSchema)
	return fmt.Sprintf("postgres://%s:%s@%s:%d/%s?%s", url.QueryEscape(c.PostgresUser), url.QueryEscape(c.PostgresPassword), c.PostgresHost, c.PostgresPort, c.PostgresDB, q.Encode())
}

func (c Config) MongoURI() string {
	q := url.Values{}
	q.Set("authSource", c.MongoAuthSource)
	return fmt.Sprintf("mongodb://%s:%s@%s:%d/%s?%s", url.QueryEscape(c.MongoUsername), url.QueryEscape(c.MongoPassword), c.MongoHost, c.MongoPort, c.MongoDatabase, q.Encode())
}

func (c Config) RedisAddress() string {
	return fmt.Sprintf("%s:%d", c.RedisHost, c.RedisPort)
}

func (c Config) CacheTTL() time.Duration {
	return time.Duration(c.RedisCacheTTLSeconds) * time.Second
}

func (c Config) RedisKey(parts ...string) string {
	cleaned := []string{c.Environment, c.ServiceName}
	for _, p := range parts {
		p = strings.Trim(strings.ReplaceAll(p, " ", "_"), ":")
		if p != "" {
			cleaned = append(cleaned, p)
		}
	}
	return strings.Join(cleaned, ":")
}

func (c Config) AllowedReportFormat(format string) bool {
	return contains(c.ReportAllowedFormats, strings.ToLower(format))
}

func (c Config) ConfigureElasticAPMEnv() {
	_ = os.Setenv("ELASTIC_APM_SERVICE_NAME", c.ServiceName)
	_ = os.Setenv("ELASTIC_APM_SERVICE_VERSION", strings.TrimPrefix(strings.TrimPrefix(c.Version, "v"), "V"))
	_ = os.Setenv("ELASTIC_APM_ENVIRONMENT", c.Environment)
	_ = os.Setenv("ELASTIC_APM_SERVER_URL", c.APMServerURL)
	_ = os.Setenv("ELASTIC_APM_SECRET_TOKEN", c.APMSecretToken)
	_ = os.Setenv("ELASTIC_APM_TRANSACTION_SAMPLE_RATE", c.APMTransactionSampleRate)
	_ = os.Setenv("ELASTIC_APM_CAPTURE_BODY", c.APMCaptureBody)
	_ = os.Setenv("ELASTIC_APM_CAPTURE_HEADERS", "true")
	_ = os.Setenv("ELASTIC_APM_CENTRAL_CONFIG", "true")
	_ = os.Setenv("ELASTIC_APM_METRICS_INTERVAL", "30s")
	_ = os.Setenv("ELASTIC_APM_GLOBAL_LABELS", "tenant="+c.Tenant+",service="+c.ServiceName)
}

func loadDefaultEnvFile() error {
	if file := os.Getenv("USER_ENV_FILE"); file != "" {
		return loadEnvFile(file)
	}
	candidates := []string{}
	if env := os.Getenv("USER_ENV"); env != "" {
		candidates = append(candidates, ".env."+envSuffix(env))
	}
	candidates = append(candidates, ".env.dev", ".env")
	for _, name := range candidates {
		if _, err := os.Stat(name); err == nil {
			return loadEnvFile(name)
		}
		if exe, err := os.Executable(); err == nil {
			path := filepath.Join(filepath.Dir(exe), name)
			if _, err := os.Stat(path); err == nil {
				return loadEnvFile(path)
			}
		}
	}
	return nil
}

func loadEnvFile(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	s := bufio.NewScanner(f)
	for s.Scan() {
		line := strings.TrimSpace(s.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		idx := strings.Index(line, "=")
		if idx <= 0 {
			continue
		}
		key := strings.TrimSpace(line[:idx])
		value := strings.TrimSpace(line[idx+1:])
		value = strings.Trim(value, "\"'")
		if _, exists := os.LookupEnv(key); !exists {
			_ = os.Setenv(key, value)
		}
	}
	return s.Err()
}

func envSuffix(env string) string {
	switch strings.ToLower(env) {
	case "development":
		return "dev"
	case "production":
		return "prod"
	default:
		return strings.ToLower(env)
	}
}

func getenv(key, fallback string) string {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return fallback
	}
	return v
}

func mustInt(key string, fallback int) int {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return n
}

func mustBool(key string, fallback bool) bool {
	v := strings.TrimSpace(strings.ToLower(os.Getenv(key)))
	if v == "" {
		return fallback
	}
	b, err := strconv.ParseBool(v)
	if err != nil {
		return fallback
	}
	return b
}

func splitCSV(value string) []string {
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func contains(values []string, candidate string) bool {
	candidate = strings.ToLower(strings.TrimSpace(candidate))
	for _, v := range values {
		if strings.ToLower(strings.TrimSpace(v)) == candidate {
			return true
		}
	}
	return false
}
