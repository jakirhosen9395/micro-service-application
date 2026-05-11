create extension if not exists pgcrypto;
create schema if not exists {{schema}};

create table if not exists {{schema}}.admin_profiles (
  id uuid primary key default gen_random_uuid(),
  tenant text not null,
  admin_user_id text not null,
  username text not null,
  email text not null,
  full_name text not null default '',
  role text not null default 'admin',
  admin_status text not null default 'approved',
  status text not null default 'active',
  source text not null default 'auth_service',
  is_super_admin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz null
);
create unique index if not exists ux_admin_profiles_tenant_admin_user_id on {{schema}}.admin_profiles(tenant, admin_user_id);
create unique index if not exists ux_admin_profiles_tenant_email on {{schema}}.admin_profiles(tenant, email);

create table if not exists {{schema}}.admin_registration_requests (
  id uuid primary key default gen_random_uuid(),
  tenant text not null,
  request_id text not null,
  user_id text not null,
  username text not null,
  email text not null,
  full_name text not null default '',
  birthdate date null,
  gender text null,
  reason text not null default '',
  status text not null default 'pending',
  requested_at timestamptz not null default now(),
  reviewed_by text null,
  reviewed_at timestamptz null,
  decision_reason text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz null
);
create unique index if not exists ux_admin_registration_requests_tenant_request_id on {{schema}}.admin_registration_requests(tenant, request_id);
create index if not exists idx_admin_registration_requests_tenant_user_id on {{schema}}.admin_registration_requests(tenant, user_id);
create index if not exists idx_admin_registration_requests_tenant_status on {{schema}}.admin_registration_requests(tenant, status, requested_at desc);

create table if not exists {{schema}}.admin_access_requests (
  id uuid primary key default gen_random_uuid(),
  tenant text not null,
  request_id text not null,
  requester_user_id text not null,
  target_user_id text not null,
  resource_type text not null,
  scope text not null,
  reason text not null default '',
  status text not null default 'pending',
  requested_at timestamptz not null default now(),
  requested_by text null,
  reviewed_by text null,
  reviewed_at timestamptz null,
  decision_reason text null,
  expires_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz null
);
create unique index if not exists ux_admin_access_requests_tenant_request_id on {{schema}}.admin_access_requests(tenant, request_id);
create index if not exists idx_admin_access_requests_target on {{schema}}.admin_access_requests(tenant, target_user_id, status);
create index if not exists idx_admin_access_requests_requester on {{schema}}.admin_access_requests(tenant, requester_user_id, status);

create table if not exists {{schema}}.admin_access_grants (
  id uuid primary key default gen_random_uuid(),
  tenant text not null,
  grant_id text not null,
  request_id text not null,
  requester_user_id text not null,
  target_user_id text not null,
  resource_type text not null,
  scope text not null,
  status text not null default 'active',
  approved_by text not null,
  approved_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_by text null,
  revoked_at timestamptz null,
  revoke_reason text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz null
);
create unique index if not exists ux_admin_access_grants_tenant_grant_id on {{schema}}.admin_access_grants(tenant, grant_id);
create unique index if not exists ux_admin_access_grants_tenant_request_id on {{schema}}.admin_access_grants(tenant, request_id);
create index if not exists idx_admin_access_grants_target on {{schema}}.admin_access_grants(tenant, target_user_id, status);
create index if not exists idx_admin_access_grants_requester on {{schema}}.admin_access_grants(tenant, requester_user_id, status);

create table if not exists {{schema}}.admin_user_projection (
  id uuid primary key default gen_random_uuid(),
  tenant text not null,
  user_id text not null,
  username text not null default '',
  email text not null default '',
  full_name text not null default '',
  role text not null default 'user',
  admin_status text not null default 'not_requested',
  status text not null default 'active',
  last_seen_at timestamptz null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz null
);
create unique index if not exists ux_admin_user_projection_tenant_user_id on {{schema}}.admin_user_projection(tenant, user_id);
create index if not exists idx_admin_user_projection_tenant_status on {{schema}}.admin_user_projection(tenant, status);

create table if not exists {{schema}}.admin_calculation_projection (
  id uuid primary key default gen_random_uuid(),
  tenant text not null,
  calculation_id text not null,
  user_id text not null,
  status text not null default '',
  operation text not null default '',
  occurred_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz null
);
create unique index if not exists ux_admin_calculation_projection_tenant_calculation_id on {{schema}}.admin_calculation_projection(tenant, calculation_id);
create index if not exists idx_admin_calculation_projection_user on {{schema}}.admin_calculation_projection(tenant, user_id, occurred_at desc);

create table if not exists {{schema}}.admin_todo_projection (
  id uuid primary key default gen_random_uuid(),
  tenant text not null,
  todo_id text not null,
  user_id text not null,
  status text not null default '',
  title text not null default '',
  occurred_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz null
);
create unique index if not exists ux_admin_todo_projection_tenant_todo_id on {{schema}}.admin_todo_projection(tenant, todo_id);
create index if not exists idx_admin_todo_projection_user on {{schema}}.admin_todo_projection(tenant, user_id, occurred_at desc);

create table if not exists {{schema}}.admin_report_projection (
  id uuid primary key default gen_random_uuid(),
  tenant text not null,
  report_id text not null,
  user_id text not null,
  report_type text not null default '',
  format text not null default '',
  status text not null default '',
  requested_by text not null default '',
  requested_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz null
);
create unique index if not exists ux_admin_report_projection_tenant_report_id on {{schema}}.admin_report_projection(tenant, report_id);
create index if not exists idx_admin_report_projection_user on {{schema}}.admin_report_projection(tenant, user_id, requested_at desc);

create table if not exists {{schema}}.admin_audit_events (
  id uuid primary key default gen_random_uuid(),
  event_id text not null,
  tenant text not null,
  admin_user_id text not null,
  target_user_id text null,
  event_type text not null,
  resource_type text not null,
  resource_id text not null,
  request_id text not null,
  trace_id text not null,
  correlation_id text not null,
  client_ip text null,
  user_agent text null,
  payload jsonb not null default '{}'::jsonb,
  s3_object_key text null,
  created_at timestamptz not null default now()
);
create unique index if not exists ux_admin_audit_events_tenant_event_id on {{schema}}.admin_audit_events(tenant, event_id);
create index if not exists idx_admin_audit_events_admin on {{schema}}.admin_audit_events(tenant, admin_user_id, created_at desc);
create index if not exists idx_admin_audit_events_target on {{schema}}.admin_audit_events(tenant, target_user_id, created_at desc);

create table if not exists {{schema}}.outbox_events (
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
  constraint outbox_events_status_check
    check (status in ('PENDING','PROCESSING','SENT','FAILED','DEAD_LETTERED'))
);
create index if not exists idx_outbox_pending
  on {{schema}}.outbox_events(status, next_retry_at, created_at);

create table if not exists {{schema}}.kafka_inbox_events (
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
  constraint kafka_inbox_status_check
    check (status in ('RECEIVED','PROCESSING','PROCESSED','FAILED','IGNORED'))
);
create unique index if not exists idx_kafka_inbox_topic_partition_offset
  on {{schema}}.kafka_inbox_events(topic, partition, offset_value);
