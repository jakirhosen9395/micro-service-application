-- V1__todo_list_service_schema.sql
-- Canonical first-run schema for todo_list_service.

create extension if not exists pgcrypto;
create schema if not exists todo;
set search_path to todo;

create table if not exists todos (
  id text primary key,
  tenant text not null,
  user_id text not null,
  username text,
  email text,
  title text not null,
  description text,
  status text not null default 'PENDING',
  priority text not null default 'MEDIUM',
  due_date timestamptz,
  completed_at timestamptz,
  archived_at timestamptz,
  archived boolean not null default false,
  tags jsonb not null default '[]'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  request_id text,
  trace_id text,
  correlation_id text,
  client_ip text,
  user_agent text,
  s3_object_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint todos_status_check check (status in ('PENDING','IN_PROGRESS','COMPLETED','CANCELLED','ARCHIVED')),
  constraint todos_priority_check check (priority in ('LOW','MEDIUM','HIGH','URGENT')),
  constraint todos_tags_json_array_check check (jsonb_typeof(tags) = 'array'),
  constraint todos_metadata_json_object_check check (jsonb_typeof(metadata) = 'object')
);

create table if not exists todo_history (
  id text primary key,
  todo_id text not null references todos(id) on delete cascade,
  user_id text not null,
  actor_id text,
  actor_role text,
  tenant text not null,
  event_type text not null,
  action text not null,
  event_id text not null unique,
  old_status text,
  new_status text,
  old_value text,
  new_value text,
  changes jsonb not null default '{}'::jsonb,
  reason text,
  payload jsonb not null default '{}'::jsonb,
  request_id text,
  trace_id text,
  correlation_id text,
  client_ip text,
  user_agent text,
  created_at timestamptz not null default now()
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

create table if not exists access_grant_projections (
  grant_id text primary key,
  tenant text not null,
  target_user_id text not null,
  grantee_user_id text not null,
  scope text not null,
  status text not null,
  expires_at timestamptz,
  revoked_at timestamptz,
  source_event_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint access_grant_status_check
    check (status in ('APPROVED','ACTIVE','REVOKED','EXPIRED','REJECTED','CANCELLED'))
);

create index if not exists idx_todos_tenant_user_created
  on todos(tenant, user_id, created_at desc);
create index if not exists idx_todos_tenant_status
  on todos(tenant, status);
create index if not exists idx_todos_tenant_priority
  on todos(tenant, priority);
create index if not exists idx_todos_due_date
  on todos(due_date);
create index if not exists idx_todos_deleted_at
  on todos(deleted_at);
create index if not exists idx_todos_archived
  on todos(archived);
create index if not exists idx_todos_tags
  on todos using gin(tags);
create index if not exists idx_todo_history_todo_created
  on todo_history(todo_id, created_at desc);
create index if not exists idx_todo_history_user_created
  on todo_history(user_id, created_at desc);
create index if not exists idx_todo_history_event_id
  on todo_history(event_id);
create index if not exists idx_access_grants_lookup
  on access_grant_projections(tenant, target_user_id, grantee_user_id, scope, status, expires_at);
create index if not exists idx_access_grants_source_event
  on access_grant_projections(source_event_id);
create index if not exists idx_access_grants_grantee
  on access_grant_projections(tenant, grantee_user_id, status, expires_at);
