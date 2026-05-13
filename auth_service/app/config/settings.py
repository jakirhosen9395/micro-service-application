from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

ENV_KEY_ORDER = [
    "AUTH_SERVICE_NAME",
    "AUTH_ENV",
    "AUTH_NODE_ENV",
    "AUTH_VERSION",
    "AUTH_TENANT",
    "AUTH_HOST",
    "AUTH_PORT",
    "AUTH_JWT_SECRET",
    "AUTH_JWT_ISSUER",
    "AUTH_JWT_AUDIENCE",
    "AUTH_JWT_ALGORITHM",
    "AUTH_JWT_LEEWAY_SECONDS",
    "AUTH_POSTGRES_HOST",
    "AUTH_POSTGRES_PORT",
    "AUTH_POSTGRES_USER",
    "AUTH_POSTGRES_PASSWORD",
    "AUTH_POSTGRES_DB",
    "AUTH_POSTGRES_SCHEMA",
    "AUTH_POSTGRES_POOL_SIZE",
    "AUTH_POSTGRES_MAX_OVERFLOW",
    "AUTH_POSTGRES_MIGRATION_MODE",
    "AUTH_REDIS_HOST",
    "AUTH_REDIS_PORT",
    "AUTH_REDIS_PASSWORD",
    "AUTH_REDIS_DB",
    "AUTH_REDIS_CACHE_TTL_SECONDS",
    "AUTH_KAFKA_BOOTSTRAP_SERVERS",
    "AUTH_KAFKA_EVENTS_TOPIC",
    "AUTH_KAFKA_DEAD_LETTER_TOPIC",
    "AUTH_KAFKA_CONSUMER_GROUP",
    "AUTH_KAFKA_CONSUME_TOPICS",
    "AUTH_KAFKA_AUTO_CREATE_TOPICS",
    "AUTH_S3_ENDPOINT",
    "AUTH_S3_ACCESS_KEY",
    "AUTH_S3_SECRET_KEY",
    "AUTH_S3_REGION",
    "AUTH_S3_FORCE_PATH_STYLE",
    "AUTH_S3_BUCKET",
    "AUTH_S3_AUDIT_PREFIX",
    "AUTH_S3_REPORT_PREFIX",
    "AUTH_MONGO_HOST",
    "AUTH_MONGO_PORT",
    "AUTH_MONGO_USERNAME",
    "AUTH_MONGO_PASSWORD",
    "AUTH_MONGO_DATABASE",
    "AUTH_MONGO_AUTH_SOURCE",
    "AUTH_MONGO_LOG_COLLECTION",
    "AUTH_APM_SERVER_URL",
    "AUTH_APM_SECRET_TOKEN",
    "AUTH_APM_TRANSACTION_SAMPLE_RATE",
    "AUTH_APM_CAPTURE_BODY",
    "AUTH_ELASTICSEARCH_URL",
    "AUTH_ELASTICSEARCH_USERNAME",
    "AUTH_ELASTICSEARCH_PASSWORD",
    "AUTH_KIBANA_URL",
    "AUTH_KIBANA_USERNAME",
    "AUTH_KIBANA_PASSWORD",
    "AUTH_LOG_LEVEL",
    "AUTH_LOG_FORMAT",
    "AUTH_LOGSTASH_ENABLED",
    "AUTH_LOGSTASH_HOST",
    "AUTH_LOGSTASH_PORT",
    "AUTH_CORS_ALLOWED_ORIGINS",
    "AUTH_CORS_ALLOWED_METHODS",
    "AUTH_CORS_ALLOWED_HEADERS",
    "AUTH_CORS_ALLOW_CREDENTIALS",
    "AUTH_CORS_MAX_AGE_SECONDS",
    "AUTH_SECURITY_REQUIRE_HTTPS",
    "AUTH_SECURITY_SECURE_COOKIES",
    "AUTH_SECURITY_REQUIRE_TENANT_MATCH",
    "AUTH_ACCESS_TOKEN_EXPIRE_MINUTES",
    "AUTH_REFRESH_TOKEN_EXPIRE_DAYS",
    "AUTH_DEFAULT_ADMIN_USERNAME",
    "AUTH_DEFAULT_ADMIN_PASSWORD",
    "AUTH_DEFAULT_ADMIN_EMAIL",
    "AUTH_DEFAULT_ADMIN_FULL_NAME",
    "AUTH_PASSWORD_MIN_LENGTH",
    "AUTH_PASSWORD_REQUIRE_UPPERCASE",
    "AUTH_PASSWORD_REQUIRE_LOWERCASE",
    "AUTH_PASSWORD_REQUIRE_NUMBER",
    "AUTH_PASSWORD_REQUIRE_SPECIAL",
]

INFRA_BOOLEAN_GATES = {
    "AUTH_S3_ENABLED",
    "AUTH_KAFKA_ENABLED",
    "AUTH_REDIS_ENABLED",
    "AUTH_POSTGRES_ENABLED",
    "AUTH_MONGO_ENABLED",
    "AUTH_MONGO_LOGS_ENABLED",
    "AUTH_APM_ENABLED",
    "AUTH_SWAGGER_ENABLED",
    "AUTH_POSTGRES_REQUIRED",
    "AUTH_REDIS_REQUIRED",
    "AUTH_KAFKA_REQUIRED",
    "AUTH_S3_REQUIRED",
    "AUTH_MONGO_REQUIRED",
    "AUTH_ELASTICSEARCH_REQUIRED",
    "AUTH_APM_REQUIRED",
}


def project_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _normalize_env_suffix(value: str | None) -> str:
    if not value:
        return "dev"
    value = value.strip().lower()
    return {"development": "dev", "dev": "dev", "stage": "stage", "staging": "stage", "prod": "prod", "production": "prod"}.get(value, value)


def load_env_file(root: Path | None = None, override: bool = False) -> Path | None:
    root = root or project_root()
    explicit = os.getenv("AUTH_ENV_FILE")
    suffix = _normalize_env_suffix(os.getenv("APPLICATION_ENV") or os.getenv("APP_ENV") or os.getenv("ENV"))
    candidate = Path(explicit) if explicit else root / f".env.{suffix}"
    if not candidate.exists():
        return None
    for raw_line in candidate.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if override or key not in os.environ:
            os.environ[key] = value
    return candidate


def parse_env_keys(path: Path) -> list[str]:
    keys: list[str] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        keys.append(line.split("=", 1)[0].strip())
    return keys


def _get(key: str) -> str:
    value = os.getenv(key)
    if value is None or value == "":
        raise RuntimeError(f"Missing required environment key: {key}")
    return value


def _int(key: str) -> int:
    try:
        return int(_get(key))
    except ValueError as exc:
        raise RuntimeError(f"Environment key {key} must be an integer") from exc


def _float(key: str) -> float:
    try:
        return float(_get(key))
    except ValueError as exc:
        raise RuntimeError(f"Environment key {key} must be a float") from exc


def _bool(key: str) -> bool:
    value = _get(key).strip().lower()
    if value in {"true", "1", "yes", "y", "on"}:
        return True
    if value in {"false", "0", "no", "n", "off"}:
        return False
    raise RuntimeError(f"Environment key {key} must be a boolean")


def _csv(key: str) -> list[str]:
    return [item.strip() for item in _get(key).split(",") if item.strip()]


@dataclass(frozen=True)
class Settings:
    service_name: str
    environment: str
    node_env: str
    version: str
    tenant: str
    host: str
    port: int
    jwt_secret: str
    jwt_issuer: str
    jwt_audience: str
    jwt_algorithm: str
    jwt_leeway_seconds: int
    postgres_host: str
    postgres_port: int
    postgres_user: str
    postgres_password: str
    postgres_db: str
    postgres_schema: str
    postgres_pool_size: int
    postgres_max_overflow: int
    postgres_migration_mode: str
    redis_host: str
    redis_port: int
    redis_password: str
    redis_db: int
    redis_cache_ttl_seconds: int
    kafka_bootstrap_servers: str
    kafka_events_topic: str
    kafka_dead_letter_topic: str
    kafka_consumer_group: str
    kafka_consume_topics: list[str]
    kafka_auto_create_topics: bool
    s3_endpoint: str
    s3_access_key: str
    s3_secret_key: str
    s3_region: str
    s3_force_path_style: bool
    s3_bucket: str
    s3_audit_prefix: str
    s3_report_prefix: str
    mongo_host: str
    mongo_port: int
    mongo_username: str
    mongo_password: str
    mongo_database: str
    mongo_auth_source: str
    mongo_log_collection: str
    apm_server_url: str
    apm_secret_token: str
    apm_transaction_sample_rate: float
    apm_capture_body: str
    elasticsearch_url: str
    elasticsearch_username: str
    elasticsearch_password: str
    kibana_url: str
    kibana_username: str
    kibana_password: str
    log_level: str
    log_format: str
    logstash_enabled: bool
    logstash_host: str
    logstash_port: int
    cors_allowed_origins: list[str]
    cors_allowed_methods: list[str]
    cors_allowed_headers: list[str]
    cors_allow_credentials: bool
    cors_max_age_seconds: int
    security_require_https: bool
    security_secure_cookies: bool
    security_require_tenant_match: bool
    access_token_expire_minutes: int
    refresh_token_expire_days: int
    default_admin_username: str
    default_admin_password: str
    default_admin_email: str
    default_admin_full_name: str
    password_min_length: int
    password_require_uppercase: bool
    password_require_lowercase: bool
    password_require_number: bool
    password_require_special: bool

    @property
    def redis_namespace(self) -> str:
        return f"{self.environment}:{self.service_name}:"

    @property
    def postgres_dsn_safe(self) -> str:
        return f"postgresql://{self.postgres_user}:***@{self.postgres_host}:{self.postgres_port}/{self.postgres_db}"

    @property
    def mongodb_uri(self) -> str:
        return (
            f"mongodb://{self.mongo_username}:{self.mongo_password}@{self.mongo_host}:{self.mongo_port}/"
            f"?authSource={self.mongo_auth_source}"
        )

    @property
    def redis_url(self) -> str:
        return f"redis://:{self.redis_password}@{self.redis_host}:{self.redis_port}/{self.redis_db}"

    @property
    def allowed_roles(self) -> set[str]:
        return {"user", "admin", "service", "system"}

    @property
    def allowed_admin_statuses(self) -> set[str]:
        return {"not_requested", "pending", "approved", "rejected", "suspended"}


def load_settings(load_file: bool = True) -> Settings:
    if load_file:
        load_env_file()
    unknown_gates = sorted(key for key in INFRA_BOOLEAN_GATES if key in os.environ)
    if unknown_gates:
        raise RuntimeError("Infrastructure boolean gates are forbidden: " + ", ".join(unknown_gates))
    missing = [key for key in ENV_KEY_ORDER if not os.getenv(key)]
    if missing:
        raise RuntimeError("Missing required environment keys: " + ", ".join(missing))

    settings = Settings(
        service_name=_get("AUTH_SERVICE_NAME"),
        environment=_get("AUTH_ENV"),
        node_env=_get("AUTH_NODE_ENV"),
        version=_get("AUTH_VERSION"),
        tenant=_get("AUTH_TENANT"),
        host=_get("AUTH_HOST"),
        port=_int("AUTH_PORT"),
        jwt_secret=_get("AUTH_JWT_SECRET"),
        jwt_issuer=_get("AUTH_JWT_ISSUER"),
        jwt_audience=_get("AUTH_JWT_AUDIENCE"),
        jwt_algorithm=_get("AUTH_JWT_ALGORITHM"),
        jwt_leeway_seconds=_int("AUTH_JWT_LEEWAY_SECONDS"),
        postgres_host=_get("AUTH_POSTGRES_HOST"),
        postgres_port=_int("AUTH_POSTGRES_PORT"),
        postgres_user=_get("AUTH_POSTGRES_USER"),
        postgres_password=_get("AUTH_POSTGRES_PASSWORD"),
        postgres_db=_get("AUTH_POSTGRES_DB"),
        postgres_schema=_get("AUTH_POSTGRES_SCHEMA"),
        postgres_pool_size=_int("AUTH_POSTGRES_POOL_SIZE"),
        postgres_max_overflow=_int("AUTH_POSTGRES_MAX_OVERFLOW"),
        postgres_migration_mode=_get("AUTH_POSTGRES_MIGRATION_MODE"),
        redis_host=_get("AUTH_REDIS_HOST"),
        redis_port=_int("AUTH_REDIS_PORT"),
        redis_password=_get("AUTH_REDIS_PASSWORD"),
        redis_db=_int("AUTH_REDIS_DB"),
        redis_cache_ttl_seconds=_int("AUTH_REDIS_CACHE_TTL_SECONDS"),
        kafka_bootstrap_servers=_get("AUTH_KAFKA_BOOTSTRAP_SERVERS"),
        kafka_events_topic=_get("AUTH_KAFKA_EVENTS_TOPIC"),
        kafka_dead_letter_topic=_get("AUTH_KAFKA_DEAD_LETTER_TOPIC"),
        kafka_consumer_group=_get("AUTH_KAFKA_CONSUMER_GROUP"),
        kafka_consume_topics=_csv("AUTH_KAFKA_CONSUME_TOPICS"),
        kafka_auto_create_topics=_bool("AUTH_KAFKA_AUTO_CREATE_TOPICS"),
        s3_endpoint=_get("AUTH_S3_ENDPOINT"),
        s3_access_key=_get("AUTH_S3_ACCESS_KEY"),
        s3_secret_key=_get("AUTH_S3_SECRET_KEY"),
        s3_region=_get("AUTH_S3_REGION"),
        s3_force_path_style=_bool("AUTH_S3_FORCE_PATH_STYLE"),
        s3_bucket=_get("AUTH_S3_BUCKET"),
        s3_audit_prefix=_get("AUTH_S3_AUDIT_PREFIX"),
        s3_report_prefix=_get("AUTH_S3_REPORT_PREFIX"),
        mongo_host=_get("AUTH_MONGO_HOST"),
        mongo_port=_int("AUTH_MONGO_PORT"),
        mongo_username=_get("AUTH_MONGO_USERNAME"),
        mongo_password=_get("AUTH_MONGO_PASSWORD"),
        mongo_database=_get("AUTH_MONGO_DATABASE"),
        mongo_auth_source=_get("AUTH_MONGO_AUTH_SOURCE"),
        mongo_log_collection=_get("AUTH_MONGO_LOG_COLLECTION"),
        apm_server_url=_get("AUTH_APM_SERVER_URL"),
        apm_secret_token=_get("AUTH_APM_SECRET_TOKEN"),
        apm_transaction_sample_rate=_float("AUTH_APM_TRANSACTION_SAMPLE_RATE"),
        apm_capture_body=_get("AUTH_APM_CAPTURE_BODY"),
        elasticsearch_url=_get("AUTH_ELASTICSEARCH_URL"),
        elasticsearch_username=_get("AUTH_ELASTICSEARCH_USERNAME"),
        elasticsearch_password=_get("AUTH_ELASTICSEARCH_PASSWORD"),
        kibana_url=_get("AUTH_KIBANA_URL"),
        kibana_username=_get("AUTH_KIBANA_USERNAME"),
        kibana_password=_get("AUTH_KIBANA_PASSWORD"),
        log_level=_get("AUTH_LOG_LEVEL"),
        log_format=_get("AUTH_LOG_FORMAT"),
        logstash_enabled=_bool("AUTH_LOGSTASH_ENABLED"),
        logstash_host=_get("AUTH_LOGSTASH_HOST"),
        logstash_port=_int("AUTH_LOGSTASH_PORT"),
        cors_allowed_origins=_csv("AUTH_CORS_ALLOWED_ORIGINS"),
        cors_allowed_methods=_csv("AUTH_CORS_ALLOWED_METHODS"),
        cors_allowed_headers=_csv("AUTH_CORS_ALLOWED_HEADERS"),
        cors_allow_credentials=_bool("AUTH_CORS_ALLOW_CREDENTIALS"),
        cors_max_age_seconds=_int("AUTH_CORS_MAX_AGE_SECONDS"),
        security_require_https=_bool("AUTH_SECURITY_REQUIRE_HTTPS"),
        security_secure_cookies=_bool("AUTH_SECURITY_SECURE_COOKIES"),
        security_require_tenant_match=_bool("AUTH_SECURITY_REQUIRE_TENANT_MATCH"),
        access_token_expire_minutes=_int("AUTH_ACCESS_TOKEN_EXPIRE_MINUTES"),
        refresh_token_expire_days=_int("AUTH_REFRESH_TOKEN_EXPIRE_DAYS"),
        default_admin_username=_get("AUTH_DEFAULT_ADMIN_USERNAME"),
        default_admin_password=_get("AUTH_DEFAULT_ADMIN_PASSWORD"),
        default_admin_email=_get("AUTH_DEFAULT_ADMIN_EMAIL"),
        default_admin_full_name=_get("AUTH_DEFAULT_ADMIN_FULL_NAME"),
        password_min_length=_int("AUTH_PASSWORD_MIN_LENGTH"),
        password_require_uppercase=_bool("AUTH_PASSWORD_REQUIRE_UPPERCASE"),
        password_require_lowercase=_bool("AUTH_PASSWORD_REQUIRE_LOWERCASE"),
        password_require_number=_bool("AUTH_PASSWORD_REQUIRE_NUMBER"),
        password_require_special=_bool("AUTH_PASSWORD_REQUIRE_SPECIAL"),
    )
    validate_settings(settings)
    return settings


def validate_settings(settings: Settings) -> None:
    errors: list[str] = []
    if settings.service_name != "auth_service":
        errors.append("AUTH_SERVICE_NAME must equal auth_service")
    if settings.port != 8080:
        errors.append("AUTH_PORT must equal 8080")
    if settings.postgres_schema != "auth":
        errors.append("AUTH_POSTGRES_SCHEMA must equal auth")
    if settings.s3_bucket != "microservice":
        errors.append("AUTH_S3_BUCKET must equal microservice")
    if settings.jwt_issuer != "auth":
        errors.append("AUTH_JWT_ISSUER must equal auth")
    if settings.jwt_audience != "micro-app":
        errors.append("AUTH_JWT_AUDIENCE must equal micro-app")
    if settings.jwt_algorithm != "HS256":
        errors.append("AUTH_JWT_ALGORITHM must equal HS256")
    if settings.log_format != "pretty-json":
        errors.append("AUTH_LOG_FORMAT must equal pretty-json")
    if settings.logstash_enabled:
        errors.append("AUTH_LOGSTASH_ENABLED must be false")
    if settings.postgres_migration_mode not in {"auto", "manual"}:
        errors.append("AUTH_POSTGRES_MIGRATION_MODE must be auto or manual")
    if len(settings.jwt_secret) < 32:
        errors.append("AUTH_JWT_SECRET must be at least 32 characters")
    if errors:
        raise RuntimeError("; ".join(errors))


def assert_env_files_have_same_keys(paths: Iterable[Path]) -> None:
    parsed = {path.name: parse_env_keys(path) for path in paths}
    first_name, first_keys = next(iter(parsed.items()))
    for name, keys in parsed.items():
        if keys != first_keys:
            raise AssertionError(f"{name} does not match {first_name} key order")
