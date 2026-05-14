using System.Globalization;

namespace AdminService.Api.Configuration;

public sealed class AdminSettings
{
    public string ServiceName { get; init; } = "admin_service";
    public string EnvironmentName { get; init; } = "development";
    public string NodeEnv { get; init; } = "development";
    public string Version { get; init; } = "v1.0.0";
    public string Tenant { get; init; } = "dev";
    public string Host { get; init; } = "0.0.0.0";
    public int Port { get; init; } = 8080;

    public string JwtSecret { get; init; } = string.Empty;
    public string JwtIssuer { get; init; } = "auth";
    public string JwtAudience { get; init; } = "micro-app";
    public string JwtAlgorithm { get; init; } = "HS256";
    public int JwtLeewaySeconds { get; init; } = 5;

    public string PostgresHost { get; init; } = string.Empty;
    public int PostgresPort { get; init; } = 5432;
    public string PostgresUser { get; init; } = string.Empty;
    public string PostgresPassword { get; init; } = string.Empty;
    public string PostgresDb { get; init; } = string.Empty;
    public string PostgresSchema { get; init; } = "admin";
    public int PostgresPoolSize { get; init; } = 10;
    public int PostgresMaxOverflow { get; init; } = 10;
    public string PostgresMigrationMode { get; init; } = "auto";

    public string RedisHost { get; init; } = string.Empty;
    public int RedisPort { get; init; } = 6379;
    public string RedisPassword { get; init; } = string.Empty;
    public int RedisDb { get; init; } = 0;
    public int RedisCacheTtlSeconds { get; init; } = 300;

    public string KafkaBootstrapServers { get; init; } = string.Empty;
    public string KafkaEventsTopic { get; init; } = "admin.events";
    public string KafkaDeadLetterTopic { get; init; } = "admin_service.dead-letter";
    public string KafkaConsumerGroup { get; init; } = "admin_service-development";
    public string[] KafkaConsumeTopics { get; init; } = Array.Empty<string>();
    public bool KafkaAutoCreateTopics { get; init; } = true;

    public string S3Endpoint { get; init; } = string.Empty;
    public string S3AccessKey { get; init; } = string.Empty;
    public string S3SecretKey { get; init; } = string.Empty;
    public string S3Region { get; init; } = "us-east-1";
    public bool S3ForcePathStyle { get; init; } = true;
    public string S3Bucket { get; init; } = "microservice";
    public string S3AuditPrefix { get; init; } = "admin_service/development";
    public string S3ReportPrefix { get; init; } = "report_service/development";

    public string MongoHost { get; init; } = string.Empty;
    public int MongoPort { get; init; } = 27017;
    public string MongoUsername { get; init; } = string.Empty;
    public string MongoPassword { get; init; } = string.Empty;
    public string MongoDatabase { get; init; } = "db_micro_services";
    public string MongoAuthSource { get; init; } = "admin";
    public string MongoLogCollection { get; init; } = "admin_service_development_logs";

    public string ApmServerUrl { get; init; } = string.Empty;
    public string ApmSecretToken { get; init; } = string.Empty;
    public double ApmTransactionSampleRate { get; init; } = 1.0;
    public string ApmCaptureBody { get; init; } = "errors";
    public string ElasticsearchUrl { get; init; } = string.Empty;
    public string ElasticsearchUsername { get; init; } = "elastic";
    public string ElasticsearchPassword { get; init; } = string.Empty;

    public string LogLevel { get; init; } = "info";
    public string LogFormat { get; init; } = "pretty-json";
    public bool LogstashEnabled { get; init; } = false;
    public string LogstashHost { get; init; } = string.Empty;
    public int LogstashPort { get; init; } = 5000;

    public string[] CorsAllowedOrigins { get; init; } = Array.Empty<string>();
    public string[] CorsAllowedMethods { get; init; } = Array.Empty<string>();
    public string[] CorsAllowedHeaders { get; init; } = Array.Empty<string>();
    public bool CorsAllowCredentials { get; init; } = true;
    public int CorsMaxAgeSeconds { get; init; } = 3600;

    public bool SecurityRequireHttps { get; init; } = false;
    public bool SecuritySecureCookies { get; init; } = false;
    public bool SecurityRequireTenantMatch { get; init; } = true;

    public int AccessGrantDefaultTtlDays { get; init; } = 30;
    public string DefaultAdminSource { get; init; } = "auth_service";

    public string AuthAdminDecisionsTopic => "auth.admin.decisions";
    public string AccessEventsTopic => "access.events";

    public static readonly string[] RequiredKeys =
    {
        "ADMIN_SERVICE_NAME", "ADMIN_ENV", "ADMIN_NODE_ENV", "ADMIN_VERSION", "ADMIN_TENANT",
        "ADMIN_HOST", "ADMIN_PORT",
        "ADMIN_JWT_SECRET", "ADMIN_JWT_ISSUER", "ADMIN_JWT_AUDIENCE", "ADMIN_JWT_ALGORITHM", "ADMIN_JWT_LEEWAY_SECONDS",
        "ADMIN_POSTGRES_HOST", "ADMIN_POSTGRES_PORT", "ADMIN_POSTGRES_USER", "ADMIN_POSTGRES_PASSWORD", "ADMIN_POSTGRES_DB", "ADMIN_POSTGRES_SCHEMA", "ADMIN_POSTGRES_POOL_SIZE", "ADMIN_POSTGRES_MAX_OVERFLOW", "ADMIN_POSTGRES_MIGRATION_MODE",
        "ADMIN_REDIS_HOST", "ADMIN_REDIS_PORT", "ADMIN_REDIS_PASSWORD", "ADMIN_REDIS_DB", "ADMIN_REDIS_CACHE_TTL_SECONDS",
        "ADMIN_KAFKA_BOOTSTRAP_SERVERS", "ADMIN_KAFKA_EVENTS_TOPIC", "ADMIN_KAFKA_DEAD_LETTER_TOPIC", "ADMIN_KAFKA_CONSUMER_GROUP", "ADMIN_KAFKA_CONSUME_TOPICS", "ADMIN_KAFKA_AUTO_CREATE_TOPICS",
        "ADMIN_S3_ENDPOINT", "ADMIN_S3_ACCESS_KEY", "ADMIN_S3_SECRET_KEY", "ADMIN_S3_REGION", "ADMIN_S3_FORCE_PATH_STYLE", "ADMIN_S3_BUCKET", "ADMIN_S3_AUDIT_PREFIX", "ADMIN_S3_REPORT_PREFIX",
        "ADMIN_MONGO_HOST", "ADMIN_MONGO_PORT", "ADMIN_MONGO_USERNAME", "ADMIN_MONGO_PASSWORD", "ADMIN_MONGO_DATABASE", "ADMIN_MONGO_AUTH_SOURCE", "ADMIN_MONGO_LOG_COLLECTION",
        "ADMIN_APM_SERVER_URL", "ADMIN_APM_SECRET_TOKEN", "ADMIN_APM_TRANSACTION_SAMPLE_RATE", "ADMIN_APM_CAPTURE_BODY", "ADMIN_ELASTICSEARCH_URL", "ADMIN_ELASTICSEARCH_USERNAME", "ADMIN_ELASTICSEARCH_PASSWORD",
        "ADMIN_LOG_LEVEL", "ADMIN_LOG_FORMAT", "ADMIN_LOGSTASH_ENABLED", "ADMIN_LOGSTASH_HOST", "ADMIN_LOGSTASH_PORT",
        "ADMIN_CORS_ALLOWED_ORIGINS", "ADMIN_CORS_ALLOWED_METHODS", "ADMIN_CORS_ALLOWED_HEADERS", "ADMIN_CORS_ALLOW_CREDENTIALS", "ADMIN_CORS_MAX_AGE_SECONDS",
        "ADMIN_SECURITY_REQUIRE_HTTPS", "ADMIN_SECURITY_SECURE_COOKIES", "ADMIN_SECURITY_REQUIRE_TENANT_MATCH",
        "ADMIN_ACCESS_GRANT_DEFAULT_TTL_DAYS", "ADMIN_DEFAULT_ADMIN_SOURCE"
    };

    public static AdminSettings Load()
    {
        return new AdminSettings
        {
            ServiceName = Get("ADMIN_SERVICE_NAME"),
            EnvironmentName = Get("ADMIN_ENV"),
            NodeEnv = Get("ADMIN_NODE_ENV"),
            Version = Get("ADMIN_VERSION"),
            Tenant = Get("ADMIN_TENANT"),
            Host = Get("ADMIN_HOST"),
            Port = GetInt("ADMIN_PORT"),
            JwtSecret = Get("ADMIN_JWT_SECRET"),
            JwtIssuer = Get("ADMIN_JWT_ISSUER"),
            JwtAudience = Get("ADMIN_JWT_AUDIENCE"),
            JwtAlgorithm = Get("ADMIN_JWT_ALGORITHM"),
            JwtLeewaySeconds = GetInt("ADMIN_JWT_LEEWAY_SECONDS"),
            PostgresHost = Get("ADMIN_POSTGRES_HOST"),
            PostgresPort = GetInt("ADMIN_POSTGRES_PORT"),
            PostgresUser = Get("ADMIN_POSTGRES_USER"),
            PostgresPassword = Get("ADMIN_POSTGRES_PASSWORD"),
            PostgresDb = Get("ADMIN_POSTGRES_DB"),
            PostgresSchema = Get("ADMIN_POSTGRES_SCHEMA"),
            PostgresPoolSize = GetInt("ADMIN_POSTGRES_POOL_SIZE"),
            PostgresMaxOverflow = GetInt("ADMIN_POSTGRES_MAX_OVERFLOW"),
            PostgresMigrationMode = Get("ADMIN_POSTGRES_MIGRATION_MODE"),
            RedisHost = Get("ADMIN_REDIS_HOST"),
            RedisPort = GetInt("ADMIN_REDIS_PORT"),
            RedisPassword = Get("ADMIN_REDIS_PASSWORD"),
            RedisDb = GetInt("ADMIN_REDIS_DB"),
            RedisCacheTtlSeconds = GetInt("ADMIN_REDIS_CACHE_TTL_SECONDS"),
            KafkaBootstrapServers = Get("ADMIN_KAFKA_BOOTSTRAP_SERVERS"),
            KafkaEventsTopic = Get("ADMIN_KAFKA_EVENTS_TOPIC"),
            KafkaDeadLetterTopic = Get("ADMIN_KAFKA_DEAD_LETTER_TOPIC"),
            KafkaConsumerGroup = Get("ADMIN_KAFKA_CONSUMER_GROUP"),
            KafkaConsumeTopics = SplitCsv(Get("ADMIN_KAFKA_CONSUME_TOPICS")),
            KafkaAutoCreateTopics = GetBool("ADMIN_KAFKA_AUTO_CREATE_TOPICS"),
            S3Endpoint = Get("ADMIN_S3_ENDPOINT"),
            S3AccessKey = Get("ADMIN_S3_ACCESS_KEY"),
            S3SecretKey = Get("ADMIN_S3_SECRET_KEY"),
            S3Region = Get("ADMIN_S3_REGION"),
            S3ForcePathStyle = GetBool("ADMIN_S3_FORCE_PATH_STYLE"),
            S3Bucket = Get("ADMIN_S3_BUCKET"),
            S3AuditPrefix = Get("ADMIN_S3_AUDIT_PREFIX"),
            S3ReportPrefix = Get("ADMIN_S3_REPORT_PREFIX"),
            MongoHost = Get("ADMIN_MONGO_HOST"),
            MongoPort = GetInt("ADMIN_MONGO_PORT"),
            MongoUsername = Get("ADMIN_MONGO_USERNAME"),
            MongoPassword = Get("ADMIN_MONGO_PASSWORD"),
            MongoDatabase = Get("ADMIN_MONGO_DATABASE"),
            MongoAuthSource = Get("ADMIN_MONGO_AUTH_SOURCE"),
            MongoLogCollection = Get("ADMIN_MONGO_LOG_COLLECTION"),
            ApmServerUrl = Get("ADMIN_APM_SERVER_URL"),
            ApmSecretToken = Get("ADMIN_APM_SECRET_TOKEN"),
            ApmTransactionSampleRate = GetDouble("ADMIN_APM_TRANSACTION_SAMPLE_RATE"),
            ApmCaptureBody = Get("ADMIN_APM_CAPTURE_BODY"),
            ElasticsearchUrl = Get("ADMIN_ELASTICSEARCH_URL"),
            ElasticsearchUsername = Get("ADMIN_ELASTICSEARCH_USERNAME"),
            ElasticsearchPassword = Get("ADMIN_ELASTICSEARCH_PASSWORD"),
            LogLevel = Get("ADMIN_LOG_LEVEL"),
            LogFormat = Get("ADMIN_LOG_FORMAT"),
            LogstashEnabled = GetBool("ADMIN_LOGSTASH_ENABLED"),
            LogstashHost = Get("ADMIN_LOGSTASH_HOST"),
            LogstashPort = GetInt("ADMIN_LOGSTASH_PORT"),
            CorsAllowedOrigins = SplitCsv(Get("ADMIN_CORS_ALLOWED_ORIGINS")),
            CorsAllowedMethods = SplitCsv(Get("ADMIN_CORS_ALLOWED_METHODS")),
            CorsAllowedHeaders = SplitCsv(Get("ADMIN_CORS_ALLOWED_HEADERS")),
            CorsAllowCredentials = GetBool("ADMIN_CORS_ALLOW_CREDENTIALS"),
            CorsMaxAgeSeconds = GetInt("ADMIN_CORS_MAX_AGE_SECONDS"),
            SecurityRequireHttps = GetBool("ADMIN_SECURITY_REQUIRE_HTTPS"),
            SecuritySecureCookies = GetBool("ADMIN_SECURITY_SECURE_COOKIES"),
            SecurityRequireTenantMatch = GetBool("ADMIN_SECURITY_REQUIRE_TENANT_MATCH"),
            AccessGrantDefaultTtlDays = GetInt("ADMIN_ACCESS_GRANT_DEFAULT_TTL_DAYS"),
            DefaultAdminSource = Get("ADMIN_DEFAULT_ADMIN_SOURCE")
        };
    }

    public void Validate()
    {
        var missing = RequiredKeys.Where(k => string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(k))).ToArray();
        if (missing.Length > 0) throw new InvalidOperationException($"Missing required environment keys: {string.Join(", ", missing)}");
        if (ServiceName != "admin_service") throw new InvalidOperationException("ADMIN_SERVICE_NAME must be admin_service.");
        if (Port != 8080) throw new InvalidOperationException("ADMIN_PORT must be 8080.");
        if (PostgresSchema != "admin") throw new InvalidOperationException("ADMIN_POSTGRES_SCHEMA must be admin.");
        if (S3Bucket != "microservice") throw new InvalidOperationException("ADMIN_S3_BUCKET must be microservice.");
        if (JwtAlgorithm != "HS256") throw new InvalidOperationException("Only HS256 is supported by this build.");
        if (JwtSecret.Length < 32) throw new InvalidOperationException("ADMIN_JWT_SECRET is too short.");
        if (LogstashEnabled) throw new InvalidOperationException("ADMIN_LOGSTASH_ENABLED must remain false for this build contract.");
    }

    public string PostgresConnectionString()
    {
        var maxPool = PostgresPoolSize + PostgresMaxOverflow;
        return $"Host={PostgresHost};Port={PostgresPort};Username={PostgresUser};Password={PostgresPassword};Database={PostgresDb};Search Path={PostgresSchema};Pooling=true;Maximum Pool Size={maxPool};Include Error Detail=false";
    }

    public string RedisConnectionString()
    {
        return $"{RedisHost}:{RedisPort},password={RedisPassword},defaultDatabase={RedisDb},abortConnect=true,connectTimeout=5000,syncTimeout=5000";
    }

    public string MongoConnectionString()
    {
        var username = Uri.EscapeDataString(MongoUsername);
        var password = Uri.EscapeDataString(MongoPassword);
        return $"mongodb://{username}:{password}@{MongoHost}:{MongoPort}/?authSource={Uri.EscapeDataString(MongoAuthSource)}";
    }

    private static string Get(string key) => Environment.GetEnvironmentVariable(key) ?? string.Empty;
    private static int GetInt(string key) => int.Parse(Get(key), CultureInfo.InvariantCulture);
    private static double GetDouble(string key) => double.Parse(Get(key), CultureInfo.InvariantCulture);
    private static bool GetBool(string key) => bool.TryParse(Get(key), out var parsed) && parsed;
    private static string[] SplitCsv(string value) => value.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
}
