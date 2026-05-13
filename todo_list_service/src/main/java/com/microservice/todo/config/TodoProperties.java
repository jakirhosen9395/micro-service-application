package com.microservice.todo.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "todo")
public class TodoProperties {
    private String serviceName = "todo_list_service";
    private String serviceVersion = "v1.0.0";
    private String host = "0.0.0.0";
    private int port = 8080;
    private String env = "development";
    private String nodeEnv = "development";
    private String tenant = "dev";
    private String logsLevel = "info";
    private String logFormat = "pretty-json";
    private boolean logstashEnabled = false;
    private String logstashHost = "localhost";
    private int logstashPort = 5000;

    private final Cors cors = new Cors();
    private final Security security = new Security();
    private final Jwt jwt = new Jwt();
    private final Postgres postgres = new Postgres();
    private final Redis redis = new Redis();
    private final Kafka kafka = new Kafka();
    private final S3 s3 = new S3();
    private final Mongo mongo = new Mongo();
    private final Apm apm = new Apm();
    private final HttpDependency elasticsearch = new HttpDependency();
    private final HttpDependency kibana = new HttpDependency();
    private final Health health = new Health();
    private final Defaults defaults = new Defaults();
    private final Outbox outbox = new Outbox();
    private final Validation validation = new Validation();

    public String getServiceName() { return serviceName; }
    public void setServiceName(String serviceName) { this.serviceName = serviceName; }
    public String getServiceVersion() { return serviceVersion; }
    public void setServiceVersion(String serviceVersion) { this.serviceVersion = serviceVersion; }
    public String getHost() { return host; }
    public void setHost(String host) { this.host = host; }
    public int getPort() { return port; }
    public void setPort(int port) { this.port = port; }
    public String getEnv() { return env; }
    public void setEnv(String env) { this.env = env; }
    public String getNodeEnv() { return nodeEnv; }
    public void setNodeEnv(String nodeEnv) { this.nodeEnv = nodeEnv; }
    public String getTenant() { return tenant; }
    public void setTenant(String tenant) { this.tenant = tenant; }
    public String getLogsLevel() { return logsLevel; }
    public void setLogsLevel(String logsLevel) { this.logsLevel = logsLevel; }
    public String getLogFormat() { return logFormat; }
    public void setLogFormat(String logFormat) { this.logFormat = logFormat; }
    public boolean isLogstashEnabled() { return logstashEnabled; }
    public void setLogstashEnabled(boolean logstashEnabled) { this.logstashEnabled = logstashEnabled; }
    public String getLogstashHost() { return logstashHost; }
    public void setLogstashHost(String logstashHost) { this.logstashHost = logstashHost; }
    public int getLogstashPort() { return logstashPort; }
    public void setLogstashPort(int logstashPort) { this.logstashPort = logstashPort; }

    public Cors getCors() { return cors; }
    public Security getSecurity() { return security; }
    public Jwt getJwt() { return jwt; }
    public Postgres getPostgres() { return postgres; }
    public Redis getRedis() { return redis; }
    public Kafka getKafka() { return kafka; }
    public S3 getS3() { return s3; }
    public Mongo getMongo() { return mongo; }
    public Apm getApm() { return apm; }
    public HttpDependency getElasticsearch() { return elasticsearch; }
    public HttpDependency getKibana() { return kibana; }
    public Health getHealth() { return health; }
    public Defaults getDefaults() { return defaults; }
    public Outbox getOutbox() { return outbox; }
    public Validation getValidation() { return validation; }

    public static class Cors {
        private String allowedOrigins = "http://localhost:3000,http://localhost:5173";
        private String allowedMethods = "GET,POST,PUT,PATCH,DELETE,OPTIONS";
        private String allowedHeaders = "Authorization,Content-Type,X-Request-ID,X-Trace-ID,X-Correlation-ID";
        private boolean allowCredentials = true;
        private long maxAgeSeconds = 3600;
        public String getAllowedOrigins() { return allowedOrigins; }
        public void setAllowedOrigins(String allowedOrigins) { this.allowedOrigins = allowedOrigins; }
        public String getAllowedMethods() { return allowedMethods; }
        public void setAllowedMethods(String allowedMethods) { this.allowedMethods = allowedMethods; }
        public String getAllowedHeaders() { return allowedHeaders; }
        public void setAllowedHeaders(String allowedHeaders) { this.allowedHeaders = allowedHeaders; }
        public boolean isAllowCredentials() { return allowCredentials; }
        public void setAllowCredentials(boolean allowCredentials) { this.allowCredentials = allowCredentials; }
        public long getMaxAgeSeconds() { return maxAgeSeconds; }
        public void setMaxAgeSeconds(long maxAgeSeconds) { this.maxAgeSeconds = maxAgeSeconds; }
    }

    public static class Security {
        private boolean requireHttps = false;
        private boolean secureCookies = false;
        private boolean requireTenantMatch = true;
        public boolean isRequireHttps() { return requireHttps; }
        public void setRequireHttps(boolean requireHttps) { this.requireHttps = requireHttps; }
        public boolean isSecureCookies() { return secureCookies; }
        public void setSecureCookies(boolean secureCookies) { this.secureCookies = secureCookies; }
        public boolean isRequireTenantMatch() { return requireTenantMatch; }
        public void setRequireTenantMatch(boolean requireTenantMatch) { this.requireTenantMatch = requireTenantMatch; }
    }

    public static class Jwt {
        private String secret = "";
        private String issuer = "auth";
        private String audience = "micro-app";
        private String algorithm = "HS256";
        private int leewaySeconds = 5;
        public String getSecret() { return secret; }
        public void setSecret(String secret) { this.secret = secret; }
        public String getIssuer() { return issuer; }
        public void setIssuer(String issuer) { this.issuer = issuer; }
        public String getAudience() { return audience; }
        public void setAudience(String audience) { this.audience = audience; }
        public String getAlgorithm() { return algorithm; }
        public void setAlgorithm(String algorithm) { this.algorithm = algorithm; }
        public int getLeewaySeconds() { return leewaySeconds; }
        public void setLeewaySeconds(int leewaySeconds) { this.leewaySeconds = Math.max(0, leewaySeconds); }
    }

    public static class Postgres {
        private String host = "localhost";
        private int port = 5432;
        private String user = "user_micro_services";
        private String password = "";
        private String db = "db_micro_services";
        private String schema = "todo";
        private int poolSize = 10;
        private int maxOverflow = 10;
        private String migrationMode = "auto";
        public String getHost() { return host; }
        public void setHost(String host) { this.host = host; }
        public int getPort() { return port; }
        public void setPort(int port) { this.port = port; }
        public String getUser() { return user; }
        public void setUser(String user) { this.user = user; }
        public String getPassword() { return password; }
        public void setPassword(String password) { this.password = password; }
        public String getDb() { return db; }
        public void setDb(String db) { this.db = db; }
        public String getSchema() { return schema; }
        public void setSchema(String schema) { this.schema = schema; }
        public int getPoolSize() { return poolSize; }
        public void setPoolSize(int poolSize) { this.poolSize = poolSize; }
        public int getMaxOverflow() { return maxOverflow; }
        public void setMaxOverflow(int maxOverflow) { this.maxOverflow = maxOverflow; }
        public String getMigrationMode() { return migrationMode; }
        public void setMigrationMode(String migrationMode) { this.migrationMode = migrationMode; }
    }

    public static class Redis {
        private String host = "localhost";
        private int port = 6379;
        private String password = "";
        private int db = 0;
        private long cacheTtlSeconds = 300;
        public String getHost() { return host; }
        public void setHost(String host) { this.host = host; }
        public int getPort() { return port; }
        public void setPort(int port) { this.port = port; }
        public String getPassword() { return password; }
        public void setPassword(String password) { this.password = password; }
        public int getDb() { return db; }
        public void setDb(int db) { this.db = db; }
        public long getCacheTtlSeconds() { return cacheTtlSeconds; }
        public void setCacheTtlSeconds(long cacheTtlSeconds) { this.cacheTtlSeconds = cacheTtlSeconds; }
    }

    public static class Kafka {
        private String bootstrapServers = "localhost:9092";
        private String eventsTopic = "todo.events";
        private String deadLetterTopic = "todo.dead-letter";
        private String consumerGroup = "todo_list_service-development";
        private String consumeTopics = "auth.events,auth.admin.requests,auth.admin.decisions,admin.events,user.events,calculator.events,todo.events,report.events,access.events";
        private int retries = 3;
        private int topicPartitions = 3;
        private short topicReplicationFactor = 1;
        private boolean autoCreateTopics = true;
        public String getBootstrapServers() { return bootstrapServers; }
        public void setBootstrapServers(String bootstrapServers) { this.bootstrapServers = bootstrapServers; }
        public String getEventsTopic() { return eventsTopic; }
        public void setEventsTopic(String eventsTopic) { this.eventsTopic = eventsTopic; }
        public String getDeadLetterTopic() { return deadLetterTopic; }
        public void setDeadLetterTopic(String deadLetterTopic) { this.deadLetterTopic = deadLetterTopic; }
        public String getConsumerGroup() { return consumerGroup; }
        public void setConsumerGroup(String consumerGroup) { this.consumerGroup = consumerGroup; }
        public String getConsumerGroupId() { return consumerGroup; }
        public String getConsumeTopics() { return consumeTopics; }
        public void setConsumeTopics(String consumeTopics) { this.consumeTopics = consumeTopics; }
        public int getRetries() { return retries; }
        public void setRetries(int retries) { this.retries = retries; }
        public int getTopicPartitions() { return topicPartitions; }
        public void setTopicPartitions(int topicPartitions) { this.topicPartitions = topicPartitions; }
        public short getTopicReplicationFactor() { return topicReplicationFactor; }
        public void setTopicReplicationFactor(short topicReplicationFactor) { this.topicReplicationFactor = topicReplicationFactor; }
        public boolean isAutoCreateTopics() { return autoCreateTopics; }
        public void setAutoCreateTopics(boolean autoCreateTopics) { this.autoCreateTopics = autoCreateTopics; }
    }

    public static class S3 {
        private String endpoint = "";
        private String accessKey = "";
        private String secretKey = "";
        private String region = "us-east-1";
        private boolean forcePathStyle = true;
        private String bucket = "microservice";
        private String auditPrefix = "todo_list_service/development";
        private String reportPrefix = "report_service/development";
        public String getEndpoint() { return endpoint; }
        public void setEndpoint(String endpoint) { this.endpoint = endpoint; }
        public String getAccessKey() { return accessKey; }
        public void setAccessKey(String accessKey) { this.accessKey = accessKey; }
        public String getSecretKey() { return secretKey; }
        public void setSecretKey(String secretKey) { this.secretKey = secretKey; }
        public String getRegion() { return region; }
        public void setRegion(String region) { this.region = region; }
        public boolean isForcePathStyle() { return forcePathStyle; }
        public void setForcePathStyle(boolean forcePathStyle) { this.forcePathStyle = forcePathStyle; }
        public String getBucket() { return bucket; }
        public void setBucket(String bucket) { this.bucket = bucket; }
        public String getAuditPrefix() { return auditPrefix; }
        public void setAuditPrefix(String auditPrefix) { this.auditPrefix = auditPrefix; }
        public String getReportPrefix() { return reportPrefix; }
        public void setReportPrefix(String reportPrefix) { this.reportPrefix = reportPrefix; }
    }

    public static class Mongo {
        private String host = "localhost";
        private int port = 27017;
        private String username = "";
        private String password = "";
        private String database = "db_micro_services";
        private String authSource = "admin";
        private String logCollection = "todo_list_service_development_logs";
        public String getHost() { return host; }
        public void setHost(String host) { this.host = host; }
        public int getPort() { return port; }
        public void setPort(int port) { this.port = port; }
        public String getUsername() { return username; }
        public void setUsername(String username) { this.username = username; }
        public String getPassword() { return password; }
        public void setPassword(String password) { this.password = password; }
        public String getDatabase() { return database; }
        public void setDatabase(String database) { this.database = database; }
        public String getAuthSource() { return authSource; }
        public void setAuthSource(String authSource) { this.authSource = authSource; }
        public String getLogCollection() { return logCollection; }
        public void setLogCollection(String logCollection) { this.logCollection = logCollection; }
    }

    public static class Apm {
        private String serverUrl = "";
        private String secretToken = "";
        private String transactionSampleRate = "1.0";
        private String captureBody = "errors";
        public String getServerUrl() { return serverUrl; }
        public void setServerUrl(String serverUrl) { this.serverUrl = serverUrl; }
        public String getSecretToken() { return secretToken; }
        public void setSecretToken(String secretToken) { this.secretToken = secretToken; }
        public String getTransactionSampleRate() { return transactionSampleRate; }
        public void setTransactionSampleRate(String transactionSampleRate) { this.transactionSampleRate = transactionSampleRate; }
        public String getCaptureBody() { return captureBody; }
        public void setCaptureBody(String captureBody) { this.captureBody = captureBody; }
    }

    public static class HttpDependency {
        private String url = "";
        private String username = "";
        private String password = "";
        public String getUrl() { return url; }
        public void setUrl(String url) { this.url = url; }
        public String getUsername() { return username; }
        public void setUsername(String username) { this.username = username; }
        public String getPassword() { return password; }
        public void setPassword(String password) { this.password = password; }
    }

    public static class Health {
        private int timeoutSeconds = 3;
        public int getTimeoutSeconds() { return timeoutSeconds; }
        public void setTimeoutSeconds(int timeoutSeconds) { this.timeoutSeconds = timeoutSeconds; }
    }

    public static class Defaults {
        private int pageSize = 20;
        private int maxPageSize = 100;
        public int getPageSize() { return pageSize; }
        public void setPageSize(int pageSize) { this.pageSize = pageSize; }
        public int getMaxPageSize() { return maxPageSize; }
        public void setMaxPageSize(int maxPageSize) { this.maxPageSize = maxPageSize; }
    }

    public static class Outbox {
        private long retryDelayMs = 30000;
        public long getRetryDelayMs() { return retryDelayMs; }
        public void setRetryDelayMs(long retryDelayMs) { this.retryDelayMs = retryDelayMs; }
    }

    public static class Validation {
        private int titleMaxLength = 255;
        private int descriptionMaxLength = 5000;
        private int maxTags = 20;
        private int tagMaxLength = 50;
        public int getTitleMaxLength() { return titleMaxLength; }
        public void setTitleMaxLength(int titleMaxLength) { this.titleMaxLength = titleMaxLength; }
        public int getDescriptionMaxLength() { return descriptionMaxLength; }
        public void setDescriptionMaxLength(int descriptionMaxLength) { this.descriptionMaxLength = descriptionMaxLength; }
        public int getMaxTags() { return maxTags; }
        public void setMaxTags(int maxTags) { this.maxTags = maxTags; }
        public int getTagMaxLength() { return tagMaxLength; }
        public void setTagMaxLength(int tagMaxLength) { this.tagMaxLength = tagMaxLength; }
    }
}
