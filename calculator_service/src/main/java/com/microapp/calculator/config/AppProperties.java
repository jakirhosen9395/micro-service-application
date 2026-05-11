package com.microapp.calculator.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.util.Arrays;
import java.util.List;

@ConfigurationProperties(prefix = "calc")
public class AppProperties {
    private String serviceName;
    private String environment;
    private String nodeEnv;
    private String version;
    private String tenant;
    private String host;
    private int port;
    private String logLevel;
    private String logFormat;
    private boolean logstashEnabled;
    private String logstashHost;
    private int logstashPort;
    private int maxExpressionLength;
    private int historyDefaultLimit;
    private int historyMaxLimit;
    private long redisCacheTtlSeconds;
    private boolean securityRequireTenantMatch;
    private Jwt jwt = new Jwt();
    private Postgres postgres = new Postgres();
    private Redis redis = new Redis();
    private Kafka kafka = new Kafka();
    private S3 s3 = new S3();
    private Mongo mongo = new Mongo();
    private Apm apm = new Apm();
    private Elasticsearch elasticsearch = new Elasticsearch();
    private Kibana kibana = new Kibana();
    private Cors cors = new Cors();

    public String getServiceName() { return serviceName; }
    public void setServiceName(String serviceName) { this.serviceName = serviceName; }
    public String getEnvironment() { return environment; }
    public void setEnvironment(String environment) { this.environment = environment; }
    public String getNodeEnv() { return nodeEnv; }
    public void setNodeEnv(String nodeEnv) { this.nodeEnv = nodeEnv; }
    public String getVersion() { return version; }
    public void setVersion(String version) { this.version = version; }
    public String getTenant() { return tenant; }
    public void setTenant(String tenant) { this.tenant = tenant; }
    public String getHost() { return host; }
    public void setHost(String host) { this.host = host; }
    public int getPort() { return port; }
    public void setPort(int port) { this.port = port; }
    public String getLogLevel() { return logLevel; }
    public void setLogLevel(String logLevel) { this.logLevel = logLevel; }
    public String getLogFormat() { return logFormat; }
    public void setLogFormat(String logFormat) { this.logFormat = logFormat; }
    public boolean isLogstashEnabled() { return logstashEnabled; }
    public void setLogstashEnabled(boolean logstashEnabled) { this.logstashEnabled = logstashEnabled; }
    public String getLogstashHost() { return logstashHost; }
    public void setLogstashHost(String logstashHost) { this.logstashHost = logstashHost; }
    public int getLogstashPort() { return logstashPort; }
    public void setLogstashPort(int logstashPort) { this.logstashPort = logstashPort; }
    public int getMaxExpressionLength() { return maxExpressionLength; }
    public void setMaxExpressionLength(int maxExpressionLength) { this.maxExpressionLength = maxExpressionLength; }
    public int getHistoryDefaultLimit() { return historyDefaultLimit; }
    public void setHistoryDefaultLimit(int historyDefaultLimit) { this.historyDefaultLimit = historyDefaultLimit; }
    public int getHistoryMaxLimit() { return historyMaxLimit; }
    public void setHistoryMaxLimit(int historyMaxLimit) { this.historyMaxLimit = historyMaxLimit; }
    public long getRedisCacheTtlSeconds() { return redisCacheTtlSeconds; }
    public void setRedisCacheTtlSeconds(long redisCacheTtlSeconds) { this.redisCacheTtlSeconds = redisCacheTtlSeconds; }
    public boolean isSecurityRequireTenantMatch() { return securityRequireTenantMatch; }
    public void setSecurityRequireTenantMatch(boolean securityRequireTenantMatch) { this.securityRequireTenantMatch = securityRequireTenantMatch; }
    public Jwt getJwt() { return jwt; }
    public void setJwt(Jwt jwt) { this.jwt = jwt; }
    public Postgres getPostgres() { return postgres; }
    public void setPostgres(Postgres postgres) { this.postgres = postgres; }
    public Redis getRedis() { return redis; }
    public void setRedis(Redis redis) { this.redis = redis; }
    public Kafka getKafka() { return kafka; }
    public void setKafka(Kafka kafka) { this.kafka = kafka; }
    public S3 getS3() { return s3; }
    public void setS3(S3 s3) { this.s3 = s3; }
    public Mongo getMongo() { return mongo; }
    public void setMongo(Mongo mongo) { this.mongo = mongo; }
    public Apm getApm() { return apm; }
    public void setApm(Apm apm) { this.apm = apm; }
    public Elasticsearch getElasticsearch() { return elasticsearch; }
    public void setElasticsearch(Elasticsearch elasticsearch) { this.elasticsearch = elasticsearch; }
    public Kibana getKibana() { return kibana; }
    public void setKibana(Kibana kibana) { this.kibana = kibana; }
    public Cors getCors() { return cors; }
    public void setCors(Cors cors) { this.cors = cors; }

    public static class Jwt {
        private String secret;
        private String issuer;
        private String audience;
        private String algorithm;
        private long leewaySeconds;
        public String getSecret() { return secret; }
        public void setSecret(String secret) { this.secret = secret; }
        public String getIssuer() { return issuer; }
        public void setIssuer(String issuer) { this.issuer = issuer; }
        public String getAudience() { return audience; }
        public void setAudience(String audience) { this.audience = audience; }
        public String getAlgorithm() { return algorithm; }
        public void setAlgorithm(String algorithm) { this.algorithm = algorithm; }
        public long getLeewaySeconds() { return leewaySeconds; }
        public void setLeewaySeconds(long leewaySeconds) { this.leewaySeconds = leewaySeconds; }
    }

    public static class Postgres {
        private String host;
        private int port;
        private String user;
        private String database;
        private String schema;
        private String migrationMode;
        public String getHost() { return host; }
        public void setHost(String host) { this.host = host; }
        public int getPort() { return port; }
        public void setPort(int port) { this.port = port; }
        public String getUser() { return user; }
        public void setUser(String user) { this.user = user; }
        public String getDatabase() { return database; }
        public void setDatabase(String database) { this.database = database; }
        public String getSchema() { return schema; }
        public void setSchema(String schema) { this.schema = schema; }
        public String getMigrationMode() { return migrationMode; }
        public void setMigrationMode(String migrationMode) { this.migrationMode = migrationMode; }
    }

    public static class Redis {
        private String host;
        private int port;
        private int database;
        public String getHost() { return host; }
        public void setHost(String host) { this.host = host; }
        public int getPort() { return port; }
        public void setPort(int port) { this.port = port; }
        public int getDatabase() { return database; }
        public void setDatabase(int database) { this.database = database; }
    }

    public static class Kafka {
        private String bootstrapServers;
        private String eventsTopic;
        private String deadLetterTopic;
        private String consumerGroup;
        private String consumeTopics;
        private boolean autoCreateTopics;
        public String getBootstrapServers() { return bootstrapServers; }
        public void setBootstrapServers(String bootstrapServers) { this.bootstrapServers = bootstrapServers; }
        public String getEventsTopic() { return eventsTopic; }
        public void setEventsTopic(String eventsTopic) { this.eventsTopic = eventsTopic; }
        public String getDeadLetterTopic() { return deadLetterTopic; }
        public void setDeadLetterTopic(String deadLetterTopic) { this.deadLetterTopic = deadLetterTopic; }
        public String getConsumerGroup() { return consumerGroup; }
        public void setConsumerGroup(String consumerGroup) { this.consumerGroup = consumerGroup; }
        public String getConsumeTopics() { return consumeTopics; }
        public void setConsumeTopics(String consumeTopics) { this.consumeTopics = consumeTopics; }
        public boolean isAutoCreateTopics() { return autoCreateTopics; }
        public void setAutoCreateTopics(boolean autoCreateTopics) { this.autoCreateTopics = autoCreateTopics; }
        public List<String> consumeTopicList() {
            return Arrays.stream((consumeTopics == null ? "" : consumeTopics).split(","))
                    .map(String::trim)
                    .filter(s -> !s.isEmpty())
                    .distinct()
                    .toList();
        }
    }

    public static class S3 {
        private String endpoint;
        private String accessKey;
        private String secretKey;
        private String region;
        private boolean forcePathStyle;
        private String bucket;
        private String auditPrefix;
        private String reportPrefix;
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
        private String host;
        private int port;
        private String username;
        private String password;
        private String database;
        private String authSource;
        private String logCollection;
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
        private String serverUrl;
        private String secretToken;
        private String transactionSampleRate;
        private String captureBody;
        public String getServerUrl() { return serverUrl; }
        public void setServerUrl(String serverUrl) { this.serverUrl = serverUrl; }
        public String getSecretToken() { return secretToken; }
        public void setSecretToken(String secretToken) { this.secretToken = secretToken; }
        public String getTransactionSampleRate() { return transactionSampleRate; }
        public void setTransactionSampleRate(String transactionSampleRate) { this.transactionSampleRate = transactionSampleRate; }
        public String getCaptureBody() { return captureBody; }
        public void setCaptureBody(String captureBody) { this.captureBody = captureBody; }
    }

    public static class Elasticsearch {
        private String url;
        private String username;
        private String password;
        public String getUrl() { return url; }
        public void setUrl(String url) { this.url = url; }
        public String getUsername() { return username; }
        public void setUsername(String username) { this.username = username; }
        public String getPassword() { return password; }
        public void setPassword(String password) { this.password = password; }
    }

    public static class Kibana {
        private String url;
        private String username;
        private String password;
        public String getUrl() { return url; }
        public void setUrl(String url) { this.url = url; }
        public String getUsername() { return username; }
        public void setUsername(String username) { this.username = username; }
        public String getPassword() { return password; }
        public void setPassword(String password) { this.password = password; }
    }

    public static class Cors {
        private String allowedOrigins;
        private String allowedMethods;
        private String allowedHeaders;
        private boolean allowCredentials;
        private long maxAgeSeconds;
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
        public List<String> allowedOriginList() { return split(allowedOrigins); }
        public List<String> allowedMethodList() { return split(allowedMethods); }
        public List<String> allowedHeaderList() { return split(allowedHeaders); }
        private static List<String> split(String value) {
            return Arrays.stream((value == null ? "" : value).split(","))
                    .map(String::trim)
                    .filter(s -> !s.isEmpty())
                    .toList();
        }
    }
}
