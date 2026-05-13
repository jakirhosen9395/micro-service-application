create extension if not exists pgcrypto;
create schema if not exists report;

create or replace function report.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists report.report_requests (
  id uuid primary key default gen_random_uuid(),
  report_id text not null unique,
  tenant text not null,
  requester_user_id text not null,
  target_user_id text not null,
  report_type text not null,
  format text not null,
  status text not null,
  filters jsonb not null default '{}'::jsonb,
  options jsonb not null default '{}'::jsonb,
  date_from date,
  date_to date,
  requested_at timestamptz not null default now(),
  queued_at timestamptz,
  processing_started_at timestamptz,
  completed_at timestamptz,
  failed_at timestamptz,
  cancelled_at timestamptz,
  expired_at timestamptz,
  error_code text,
  error_message text,
  request_id text,
  trace_id text,
  correlation_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint report_requests_status_check check (status in ('QUEUED','PROCESSING','COMPLETED','FAILED','CANCELLED','DELETED','EXPIRED')),
  constraint report_requests_format_check check (format in ('pdf','xlsx','csv','json','html'))
);
create index if not exists idx_report_requests_requester on report.report_requests(tenant, requester_user_id, created_at desc) where deleted_at is null;
create index if not exists idx_report_requests_target on report.report_requests(tenant, target_user_id, created_at desc) where deleted_at is null;
create index if not exists idx_report_requests_status on report.report_requests(status, created_at desc) where deleted_at is null;
drop trigger if exists trg_report_requests_updated_at on report.report_requests;
create trigger trg_report_requests_updated_at before update on report.report_requests for each row execute function report.set_updated_at();

create table if not exists report.report_files (
  id uuid primary key default gen_random_uuid(),
  file_id text not null unique default ('file-' || gen_random_uuid()::text),
  report_id text not null,
  tenant text not null,
  format text not null,
  file_name text not null,
  content_type text not null,
  file_size_bytes bigint not null default 0,
  s3_bucket text not null,
  s3_object_key text not null,
  checksum_sha256 text not null,
  preview_supported boolean not null default false,
  download_count bigint not null default 0,
  last_downloaded_at timestamptz,
  download_expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (tenant, report_id, format)
);
create index if not exists idx_report_files_report_id on report.report_files(tenant, report_id) where deleted_at is null;
drop trigger if exists trg_report_files_updated_at on report.report_files;
create trigger trg_report_files_updated_at before update on report.report_files for each row execute function report.set_updated_at();

create table if not exists report.report_generation_jobs (
  id uuid primary key default gen_random_uuid(),
  job_id text not null unique,
  report_id text not null,
  tenant text not null,
  queue_name text not null,
  status text not null,
  attempt_count integer not null default 0,
  max_attempts integer not null default 1,
  progress_percent integer not null default 0,
  progress_stage text not null default 'queued',
  locked_by text,
  locked_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  duration_ms integer,
  error_code text,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint report_generation_jobs_status_check check (status in ('QUEUED','PROCESSING','COMPLETED','FAILED','CANCELLED')),
  constraint report_generation_jobs_progress_check check (progress_percent between 0 and 100)
);
create index if not exists idx_report_generation_jobs_report on report.report_generation_jobs(tenant, report_id, created_at desc);
create index if not exists idx_report_generation_jobs_status on report.report_generation_jobs(status, created_at desc) where deleted_at is null;
drop trigger if exists trg_report_generation_jobs_updated_at on report.report_generation_jobs;
create trigger trg_report_generation_jobs_updated_at before update on report.report_generation_jobs for each row execute function report.set_updated_at();

create table if not exists report.report_progress_events (
  id uuid primary key default gen_random_uuid(),
  progress_id text not null unique default ('prog-' || gen_random_uuid()::text),
  report_id text not null,
  tenant text not null,
  stage text not null,
  progress_percent integer not null,
  message text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint report_progress_events_percent_check check (progress_percent between 0 and 100)
);
create index if not exists idx_report_progress_events_report on report.report_progress_events(tenant, report_id, created_at desc);

create table if not exists report.report_templates (
  id uuid primary key default gen_random_uuid(),
  template_id text not null unique,
  tenant text not null,
  report_type text not null,
  name text not null,
  description text,
  format text not null,
  template_engine text not null default 'safe-json-template',
  template_content text not null default '{}',
  schema jsonb not null default '{}'::jsonb,
  style jsonb not null default '{}'::jsonb,
  version integer not null default 1,
  status text not null default 'DRAFT',
  created_by text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint report_templates_status_check check (status in ('DRAFT','ACTIVE','INACTIVE')),
  constraint report_templates_format_check check (format in ('pdf','xlsx','csv','json','html'))
);
create index if not exists idx_report_templates_lookup on report.report_templates(tenant, report_type, status, created_at desc) where deleted_at is null;
drop trigger if exists trg_report_templates_updated_at on report.report_templates;
create trigger trg_report_templates_updated_at before update on report.report_templates for each row execute function report.set_updated_at();

create table if not exists report.report_schedules (
  id uuid primary key default gen_random_uuid(),
  schedule_id text not null unique,
  tenant text not null,
  owner_user_id text not null,
  target_user_id text not null,
  report_type text not null,
  format text not null,
  cron_expression text not null,
  timezone text not null,
  filters jsonb not null default '{}'::jsonb,
  options jsonb not null default '{}'::jsonb,
  status text not null default 'ACTIVE',
  last_run_at timestamptz,
  next_run_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint report_schedules_status_check check (status in ('ACTIVE','PAUSED','DELETED')),
  constraint report_schedules_format_check check (format in ('pdf','xlsx','csv','json','html'))
);
create index if not exists idx_report_schedules_owner on report.report_schedules(tenant, owner_user_id, created_at desc) where deleted_at is null;
create index if not exists idx_report_schedules_status on report.report_schedules(status, next_run_at) where deleted_at is null;
drop trigger if exists trg_report_schedules_updated_at on report.report_schedules;
create trigger trg_report_schedules_updated_at before update on report.report_schedules for each row execute function report.set_updated_at();

create table if not exists report.report_audit_events (
  id uuid primary key default gen_random_uuid(),
  tenant text not null,
  report_id text,
  event_id text not null,
  event_type text not null,
  actor_id text,
  target_user_id text,
  s3_bucket text,
  s3_object_key text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (tenant, event_id)
);
create index if not exists idx_report_audit_events_report on report.report_audit_events(tenant, report_id, created_at desc);
create index if not exists idx_report_audit_events_actor on report.report_audit_events(tenant, actor_id, created_at desc);
drop trigger if exists trg_report_audit_events_updated_at on report.report_audit_events;
create trigger trg_report_audit_events_updated_at before update on report.report_audit_events for each row execute function report.set_updated_at();

create table if not exists report.report_user_projection (
  id uuid primary key default gen_random_uuid(),
  tenant text not null,
  user_id text not null,
  username text,
  email text,
  role text,
  admin_status text,
  status text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (tenant, user_id)
);
create index if not exists idx_report_user_projection_user on report.report_user_projection(tenant, user_id) where deleted_at is null;

create table if not exists report.report_calculation_projection (
  id uuid primary key default gen_random_uuid(),
  tenant text not null,
  calculation_id text not null,
  user_id text not null,
  operation text,
  status text,
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (tenant, calculation_id)
);
create index if not exists idx_report_calculation_projection_user on report.report_calculation_projection(tenant, user_id, occurred_at desc) where deleted_at is null;
create index if not exists idx_report_calculation_projection_operation on report.report_calculation_projection(tenant, operation, occurred_at desc) where deleted_at is null;

create table if not exists report.report_todo_projection (
  id uuid primary key default gen_random_uuid(),
  tenant text not null,
  todo_id text not null,
  user_id text not null,
  status text,
  priority text,
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (tenant, todo_id)
);
create index if not exists idx_report_todo_projection_user on report.report_todo_projection(tenant, user_id, occurred_at desc) where deleted_at is null;
create index if not exists idx_report_todo_projection_status on report.report_todo_projection(tenant, status, priority, occurred_at desc) where deleted_at is null;

create table if not exists report.report_access_grant_projection (
  id uuid primary key default gen_random_uuid(),
  tenant text not null,
  grant_id text,
  requester_user_id text not null,
  target_user_id text not null,
  scope text not null,
  status text not null,
  granted_at timestamptz,
  revoked_at timestamptz,
  expires_at timestamptz,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (tenant, requester_user_id, target_user_id, scope)
);
create index if not exists idx_report_access_grant_active on report.report_access_grant_projection(tenant, requester_user_id, target_user_id, status, expires_at) where deleted_at is null;

create table if not exists report.report_admin_decision_projection (
  id uuid primary key default gen_random_uuid(),
  tenant text not null,
  decision_id text not null,
  actor_id text,
  target_user_id text,
  decision text not null,
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (tenant, decision_id)
);
create index if not exists idx_report_admin_decision_projection_target on report.report_admin_decision_projection(tenant, target_user_id, occurred_at desc) where deleted_at is null;

create table if not exists report.report_activity_projection (
  id uuid primary key default gen_random_uuid(),
  tenant text not null,
  activity_id text not null,
  user_id text not null,
  activity_type text not null,
  source_service text,
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (tenant, activity_id)
);
create index if not exists idx_report_activity_projection_user on report.report_activity_projection(tenant, user_id, occurred_at desc) where deleted_at is null;
create index if not exists idx_report_activity_projection_source on report.report_activity_projection(tenant, source_service, activity_type, occurred_at desc) where deleted_at is null;

create table if not exists report.report_share_links (
  id uuid primary key default gen_random_uuid(),
  share_id text not null unique default ('share-' || gen_random_uuid()::text),
  tenant text not null,
  report_id text not null,
  created_by text not null,
  expires_at timestamptz,
  revoked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists idx_report_share_links_report on report.report_share_links(tenant, report_id, created_at desc) where deleted_at is null;

create table if not exists report.report_dataset_snapshots (
  id uuid primary key default gen_random_uuid(),
  snapshot_id text not null unique default ('snap-' || gen_random_uuid()::text),
  tenant text not null,
  report_id text not null,
  dataset_name text not null,
  row_count integer not null default 0,
  checksum_sha256 text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_report_dataset_snapshots_report on report.report_dataset_snapshots(tenant, report_id, created_at desc);

create table if not exists report.outbox_events (
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
create index if not exists idx_outbox_pending on report.outbox_events(status, next_retry_at, created_at);
drop trigger if exists trg_outbox_events_updated_at on report.outbox_events;
create trigger trg_outbox_events_updated_at before update on report.outbox_events for each row execute function report.set_updated_at();

create table if not exists report.kafka_inbox_events (
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
create unique index if not exists idx_kafka_inbox_topic_partition_offset on report.kafka_inbox_events(topic, partition, offset_value);
create index if not exists idx_kafka_inbox_event_id on report.kafka_inbox_events(event_id);
