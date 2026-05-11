using AdminService.Api.Configuration;
using AdminService.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace AdminService.Api.Persistence;

public sealed class AdminDbContext : DbContext
{
    private readonly AdminSettings _settings;

    public AdminDbContext(DbContextOptions<AdminDbContext> options, AdminSettings settings) : base(options)
    {
        _settings = settings;
    }

    public DbSet<AdminProfile> AdminProfiles => Set<AdminProfile>();
    public DbSet<AdminRegistrationRequest> AdminRegistrationRequests => Set<AdminRegistrationRequest>();
    public DbSet<AdminAccessRequest> AdminAccessRequests => Set<AdminAccessRequest>();
    public DbSet<AdminAccessGrant> AdminAccessGrants => Set<AdminAccessGrant>();
    public DbSet<AdminUserProjection> AdminUserProjections => Set<AdminUserProjection>();
    public DbSet<AdminCalculationProjection> AdminCalculationProjections => Set<AdminCalculationProjection>();
    public DbSet<AdminTodoProjection> AdminTodoProjections => Set<AdminTodoProjection>();
    public DbSet<AdminReportProjection> AdminReportProjections => Set<AdminReportProjection>();
    public DbSet<AdminAuditEvent> AdminAuditEvents => Set<AdminAuditEvent>();
    public DbSet<OutboxEvent> OutboxEvents => Set<OutboxEvent>();
    public DbSet<KafkaInboxEvent> KafkaInboxEvents => Set<KafkaInboxEvent>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema(_settings.PostgresSchema);

        modelBuilder.Entity<AdminProfile>(entity =>
        {
            entity.ToTable("admin_profiles");
            entity.HasIndex(x => new { x.Tenant, x.AdminUserId }).IsUnique();
            entity.HasIndex(x => new { x.Tenant, x.Email }).IsUnique();
        });

        modelBuilder.Entity<AdminRegistrationRequest>(entity =>
        {
            entity.ToTable("admin_registration_requests");
            entity.HasIndex(x => new { x.Tenant, x.RequestId }).IsUnique();
            entity.HasIndex(x => new { x.Tenant, x.UserId });
            entity.Property(x => x.Birthdate).HasColumnType("date");
        });

        modelBuilder.Entity<AdminAccessRequest>(entity =>
        {
            entity.ToTable("admin_access_requests");
            entity.HasIndex(x => new { x.Tenant, x.RequestId }).IsUnique();
            entity.HasIndex(x => new { x.Tenant, x.TargetUserId });
            entity.HasIndex(x => new { x.Tenant, x.RequesterUserId });
        });

        modelBuilder.Entity<AdminAccessGrant>(entity =>
        {
            entity.ToTable("admin_access_grants");
            entity.HasIndex(x => new { x.Tenant, x.GrantId }).IsUnique();
            entity.HasIndex(x => new { x.Tenant, x.RequestId }).IsUnique();
            entity.HasIndex(x => new { x.Tenant, x.TargetUserId, x.Status });
            entity.HasIndex(x => new { x.Tenant, x.RequesterUserId, x.Status });
        });

        modelBuilder.Entity<AdminUserProjection>(entity =>
        {
            entity.ToTable("admin_user_projection");
            entity.HasIndex(x => new { x.Tenant, x.UserId }).IsUnique();
            entity.Property(x => x.Payload).HasColumnType("jsonb");
        });

        modelBuilder.Entity<AdminCalculationProjection>(entity =>
        {
            entity.ToTable("admin_calculation_projection");
            entity.HasIndex(x => new { x.Tenant, x.CalculationId }).IsUnique();
            entity.HasIndex(x => new { x.Tenant, x.UserId, x.OccurredAt });
            entity.Property(x => x.Payload).HasColumnType("jsonb");
        });

        modelBuilder.Entity<AdminTodoProjection>(entity =>
        {
            entity.ToTable("admin_todo_projection");
            entity.HasIndex(x => new { x.Tenant, x.TodoId }).IsUnique();
            entity.HasIndex(x => new { x.Tenant, x.UserId, x.OccurredAt });
            entity.Property(x => x.Payload).HasColumnType("jsonb");
        });

        modelBuilder.Entity<AdminReportProjection>(entity =>
        {
            entity.ToTable("admin_report_projection");
            entity.HasIndex(x => new { x.Tenant, x.ReportId }).IsUnique();
            entity.HasIndex(x => new { x.Tenant, x.UserId, x.RequestedAt });
            entity.Property(x => x.Payload).HasColumnType("jsonb");
        });

        modelBuilder.Entity<AdminAuditEvent>(entity =>
        {
            entity.ToTable("admin_audit_events");
            entity.HasIndex(x => new { x.Tenant, x.EventId }).IsUnique();
            entity.HasIndex(x => new { x.Tenant, x.AdminUserId, x.CreatedAt });
            entity.HasIndex(x => new { x.Tenant, x.TargetUserId, x.CreatedAt });
            entity.Property(x => x.Payload).HasColumnType("jsonb");
        });

        modelBuilder.Entity<OutboxEvent>(entity =>
        {
            entity.ToTable("outbox_events");
            entity.HasIndex(x => x.EventId).IsUnique();
            entity.HasIndex(x => new { x.Status, x.NextRetryAt, x.CreatedAt }).HasDatabaseName("idx_outbox_pending");
            entity.Property(x => x.Payload).HasColumnType("jsonb");
        });

        modelBuilder.Entity<KafkaInboxEvent>(entity =>
        {
            entity.ToTable("kafka_inbox_events");
            entity.HasIndex(x => x.EventId).IsUnique();
            entity.HasIndex(x => new { x.Topic, x.Partition, x.OffsetValue }).IsUnique().HasDatabaseName("idx_kafka_inbox_topic_partition_offset");
            entity.Property(x => x.Payload).HasColumnType("jsonb");
        });
    }

    public override Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var entry in ChangeTracker.Entries<EntityBase>())
        {
            if (entry.State == EntityState.Added)
            {
                entry.Entity.CreatedAt = now;
                entry.Entity.UpdatedAt = now;
            }
            if (entry.State == EntityState.Modified)
            {
                entry.Entity.UpdatedAt = now;
            }
        }
        foreach (var entry in ChangeTracker.Entries<OutboxEvent>())
        {
            if (entry.State is EntityState.Added or EntityState.Modified)
            {
                entry.Entity.UpdatedAt = now;
            }
        }
        return base.SaveChangesAsync(cancellationToken);
    }
}
