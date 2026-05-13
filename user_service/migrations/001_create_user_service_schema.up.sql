create extension if not exists pgcrypto;
create schema if not exists user_service;
set search_path to user_service;

create table if not exists user_profiles (
  id text not null default gen_random_uuid()::text unique,
  tenant text not null,
  user_id text not null,
  username text not null default '',
  email text not null default '',
  full_name text not null default '',
  display_name text not null default '',
  bio text not null default '',
  birthdate date,
  gender text,
  role text not null default 'user',
  admin_status text not null default 'not_requested',
  status text not null default 'active',
  timezone text not null default 'Asia/Dhaka',
  locale text not null default 'en',
  avatar_url text,
  phone text,
  source_event_id text,
  last_seen_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (tenant, user_id),
  constraint user_profiles_role_check check (role in ('user','admin','service','system')),
  constraint user_profiles_admin_status_check check (admin_status in ('not_requested','pending','approved','rejected','suspended'))
);

create table if not exists user_preferences (
  tenant text not null,
  user_id text not null,
  timezone text not null default 'Asia/Dhaka',
  locale text not null default 'en',
  theme text not null default 'dark',
  notifications_enabled boolean not null default true,
  notification_settings jsonb not null default '{}'::jsonb,
  dashboard_settings jsonb not null default '{}'::jsonb,
  report_settings jsonb not null default '{}'::jsonb,
  privacy_settings jsonb not null default '{}'::jsonb,
  access_request_settings jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (tenant, user_id)
);

create table if not exists user_activity_events (
  id text primary key,
  event_id text unique,
  tenant text not null,
  user_id text not null,
  actor_id text not null,
  target_user_id text,
  event_type text not null,
  resource_type text,
  resource_id text,
  source_service text,
  aggregate_type text not null,
  aggregate_id text not null,
  summary text not null default '',
  payload jsonb not null default '{}'::jsonb,
  request_id text,
  trace_id text,
  correlation_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists idx_user_activity_user_time on user_activity_events(tenant, user_id, created_at desc);
create index if not exists idx_user_activity_type_time on user_activity_events(event_type, created_at desc);

create table if not exists user_calculation_projections (
  tenant text not null,
  calculation_id text not null,
  user_id text not null,
  operation text,
  expression text,
  operands jsonb not null default '[]'::jsonb,
  result text,
  status text not null default 'COMPLETED',
  error_message text,
  source_event_id text,
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  s3_object_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (tenant, calculation_id)
);
create index if not exists idx_user_calc_user_time on user_calculation_projections(tenant, user_id, occurred_at desc);

create table if not exists user_todo_projections (
  tenant text not null,
  todo_id text not null,
  user_id text not null,
  title text not null default '',
  description text,
  status text not null default 'PENDING',
  priority text not null default 'MEDIUM',
  due_date timestamptz,
  tags jsonb not null default '[]'::jsonb,
  completed_at timestamptz,
  archived_at timestamptz,
  source_event_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (tenant, todo_id)
);
create index if not exists idx_user_todo_user_status on user_todo_projections(tenant, user_id, status, updated_at desc);
create index if not exists idx_user_todo_due on user_todo_projections(tenant, user_id, due_date);

create table if not exists user_access_requests (
  tenant text not null,
  request_id text not null,
  requester_user_id text not null,
  target_user_id text not null,
  resource_type text not null,
  scope text not null,
  reason text not null,
  status text not null default 'PENDING',
  expires_at timestamptz not null,
  decision_reason text,
  decided_by text,
  decided_at timestamptz,
  cancelled_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (tenant, request_id),
  constraint user_access_requests_status_check check (status in ('PENDING','APPROVED','REJECTED','CANCELLED','EXPIRED'))
);
create index if not exists idx_user_access_requests_requester on user_access_requests(tenant, requester_user_id, created_at desc);
create index if not exists idx_user_access_requests_target on user_access_requests(tenant, target_user_id, created_at desc);

create table if not exists user_access_grants (
  tenant text not null,
  grant_id text not null,
  request_id text,
  requester_user_id text not null,
  target_user_id text not null,
  resource_type text not null,
  scope text not null,
  status text not null default 'ACTIVE',
  approved_by text,
  revoked_by text,
  reason text,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (tenant, grant_id),
  constraint user_access_grants_status_check check (status in ('ACTIVE','REVOKED','EXPIRED'))
);
create index if not exists idx_user_access_grants_actor_target on user_access_grants(tenant, requester_user_id, target_user_id, resource_type, status, expires_at);
create index if not exists idx_user_access_grants_visible on user_access_grants(tenant, requester_user_id, target_user_id, created_at desc);

create table if not exists user_report_requests (
  tenant text not null,
  report_id text not null,
  requester_user_id text not null,
  target_user_id text not null,
  report_type text not null,
  format text not null,
  date_from date,
  date_to date,
  filters jsonb not null default '{}'::jsonb,
  options jsonb not null default '{}'::jsonb,
  status text not null default 'QUEUED',
  file_name text,
  s3_object_key text,
  download_url text,
  error_message text,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (tenant, report_id),
  constraint user_report_requests_format_check check (format in ('pdf','csv','json','html','xlsx'))
);
create index if not exists idx_user_report_requests_requester_target on user_report_requests(tenant, requester_user_id, target_user_id, created_at desc);
create index if not exists idx_user_report_requests_status on user_report_requests(tenant, status, created_at desc);

create table if not exists user_report_projections (
  tenant text not null,
  report_id text not null,
  requester_user_id text not null,
  target_user_id text not null,
  report_type text not null default '',
  format text not null default 'pdf',
  status text not null,
  file_name text,
  s3_object_key text,
  download_url text,
  error_message text,
  progress jsonb not null default '{}'::jsonb,
  expires_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  source_event_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (tenant, report_id)
);
create index if not exists idx_user_report_projection_target on user_report_projections(tenant, target_user_id, created_at desc);

create table if not exists user_service_state (
  tenant text not null,
  state_key text not null,
  state_value jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (tenant, state_key)
);

create table if not exists user_rbac_policies (
  tenant text not null,
  policy_id text not null,
  subject_user_id text,
  role text,
  resource_type text not null,
  scope text not null,
  effect text not null default 'ALLOW',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (tenant, policy_id)
);

create table if not exists user_permission_snapshots (
  tenant text not null,
  user_id text not null,
  permissions jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (tenant, user_id)
);

create table if not exists user_dashboard_snapshots (
  tenant text not null,
  user_id text not null,
  snapshot jsonb not null default '{}'::jsonb,
  generated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (tenant, user_id)
);

create table if not exists outbox_events (
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
  on outbox_events(status, next_retry_at, created_at);

create table if not exists kafka_inbox_events (
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
  on kafka_inbox_events(topic, partition, offset_value);
