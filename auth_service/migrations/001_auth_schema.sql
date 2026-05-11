create schema if not exists auth;
create extension if not exists pgcrypto;

create table if not exists auth.auth_users (
  id text primary key,
  tenant text not null,
  username text not null,
  email text not null,
  password_hash text not null,
  full_name text,
  birthdate date,
  gender text,
  role text not null default 'user',
  admin_status text not null default 'not_requested',
  status text not null default 'active',
  email_verified boolean not null default false,
  phone text,
  avatar_url text,
  metadata jsonb not null default '{}'::jsonb,
  failed_login_count integer not null default 0,
  locked_until timestamptz,
  last_login_at timestamptz,
  last_seen_at timestamptz,
  admin_requested_at timestamptz,
  admin_reviewed_at timestamptz,
  admin_reviewed_by text,
  admin_request_reason text,
  admin_decision_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint auth_users_role_check check (role in ('user','admin','service','system')),
  constraint auth_users_admin_status_check check (admin_status in ('not_requested','pending','approved','rejected','suspended')),
  constraint auth_users_status_check check (status in ('active','suspended','force_password_reset','deleted')),
  constraint auth_users_gender_check check (gender is null or gender in ('male','female','other','prefer_not_to_say')),
  constraint auth_users_username_per_tenant unique (tenant, username),
  constraint auth_users_email_per_tenant unique (tenant, email)
);

create index if not exists idx_auth_users_tenant_role on auth.auth_users(tenant, role);
create index if not exists idx_auth_users_tenant_admin_status on auth.auth_users(tenant, admin_status);
create index if not exists idx_auth_users_tenant_status on auth.auth_users(tenant, status);
create index if not exists idx_auth_users_created_at on auth.auth_users(created_at desc);

create table if not exists auth.auth_sessions (
  id text primary key,
  tenant text not null,
  user_id text not null references auth.auth_users(id) on delete cascade,
  jti text not null unique,
  refresh_token_hash text not null unique,
  access_token_expires_at timestamptz not null,
  refresh_token_expires_at timestamptz not null,
  revoked_at timestamptz,
  revoked_reason text,
  ip_address text,
  user_agent text,
  device_id text,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz
);

create index if not exists idx_auth_sessions_tenant_user on auth.auth_sessions(tenant, user_id);
create index if not exists idx_auth_sessions_refresh_hash on auth.auth_sessions(refresh_token_hash);
create index if not exists idx_auth_sessions_jti on auth.auth_sessions(jti);
create index if not exists idx_auth_sessions_active on auth.auth_sessions(tenant, user_id, revoked_at);

create table if not exists auth.auth_audit_events (
  id text primary key,
  event_id text not null unique,
  event_type text not null,
  service text not null,
  environment text not null,
  tenant text not null,
  user_id text,
  actor_id text,
  target_user_id text,
  aggregate_type text not null,
  aggregate_id text not null,
  request_id text,
  trace_id text,
  correlation_id text,
  client_ip text,
  user_agent text,
  s3_bucket text,
  s3_object_key text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_auth_audit_tenant_created on auth.auth_audit_events(tenant, created_at desc);
create index if not exists idx_auth_audit_event_type_created on auth.auth_audit_events(event_type, created_at desc);
create index if not exists idx_auth_audit_user_created on auth.auth_audit_events(user_id, created_at desc);
create index if not exists idx_auth_audit_request_id on auth.auth_audit_events(request_id);
create index if not exists idx_auth_audit_trace_id on auth.auth_audit_events(trace_id);

create table if not exists auth.outbox_events (
  id uuid primary key default gen_random_uuid(),
  event_id text not null unique,
  tenant text not null,
  aggregate_type text not null,
  aggregate_id text not null,
  event_type text not null,
  event_version text not null default '1.0',
  topic text not null,
  payload jsonb not null,
  status text not null default 'PENDING',
  attempt_count integer not null default 0,
  last_error text,
  next_retry_at timestamptz,
  request_id text,
  trace_id text,
  correlation_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sent_at timestamptz,
  constraint outbox_events_status_check check (status in ('PENDING','PROCESSING','SENT','FAILED','DEAD_LETTERED'))
);

create index if not exists idx_outbox_pending on auth.outbox_events(status, next_retry_at, created_at);
create index if not exists idx_outbox_event_type on auth.outbox_events(event_type, created_at desc);

create table if not exists auth.kafka_inbox_events (
  id uuid primary key default gen_random_uuid(),
  event_id text not null unique,
  tenant text,
  topic text not null,
  partition integer not null default 0,
  offset_value bigint not null default 0,
  event_type text not null,
  source_service text,
  payload jsonb,
  status text not null default 'RECEIVED',
  processed_at timestamptz,
  error_message text,
  created_at timestamptz not null default now(),
  constraint kafka_inbox_status_check check (status in ('RECEIVED','PROCESSING','PROCESSED','FAILED','IGNORED'))
);

create unique index if not exists idx_kafka_inbox_topic_partition_offset on auth.kafka_inbox_events(topic, partition, offset_value);
create index if not exists idx_kafka_inbox_status_created on auth.kafka_inbox_events(status, created_at);
