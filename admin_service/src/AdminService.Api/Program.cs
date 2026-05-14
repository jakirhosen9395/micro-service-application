using Amazon;
using Amazon.Runtime;
using Amazon.S3;
using AdminService.Api.Configuration;
using AdminService.Api.Docs;
using AdminService.Api.Endpoints;
using AdminService.Api.Http;
using AdminService.Api.Infrastructure.Audit;
using AdminService.Api.Infrastructure.Health;
using AdminService.Api.Infrastructure.Kafka;
using AdminService.Api.Infrastructure.Logging;
using AdminService.Api.Infrastructure.Observability;
using AdminService.Api.Infrastructure.Redis;
using AdminService.Api.Infrastructure.Startup;
using AdminService.Api.Infrastructure.Storage;
using AdminService.Api.Middleware;
using AdminService.Api.Persistence;
using AdminService.Api.Security;
using Confluent.Kafka;
using Elastic.Apm.NetCoreAll;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;
using MongoDB.Driver;
using StackExchange.Redis;
using System.IdentityModel.Tokens.Jwt;
using System.Text;

DotEnvLoader.Load();
var settings = AdminSettings.Load();
settings.Validate();
ApmTelemetry.ConfigureElasticEnvironment(settings);
JwtSecurityTokenHandler.DefaultMapInboundClaims = false;

var builder = WebApplication.CreateBuilder(args);
builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole(options =>
{
    options.IncludeScopes = true;
    options.TimestampFormat = "O";
});
builder.Logging.SetMinimumLevel(ApmTelemetry.ParseLogLevel(settings.LogLevel));
builder.WebHost.UseUrls($"http://{settings.Host}:{settings.Port}");
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = JsonOptionsFactory.Options.PropertyNamingPolicy;
    options.SerializerOptions.DictionaryKeyPolicy = JsonOptionsFactory.Options.DictionaryKeyPolicy;
    options.SerializerOptions.WriteIndented = true;
    options.SerializerOptions.DefaultIgnoreCondition = JsonOptionsFactory.Options.DefaultIgnoreCondition;
});

builder.Services.AddSingleton(settings);
builder.Services.AddHttpClient();
builder.Services.AddAllElasticApm();
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.WithOrigins(settings.CorsAllowedOrigins)
            .WithMethods(settings.CorsAllowedMethods)
            .WithHeaders(settings.CorsAllowedHeaders)
            .SetPreflightMaxAge(TimeSpan.FromSeconds(settings.CorsMaxAgeSeconds));
        if (settings.CorsAllowCredentials) policy.AllowCredentials();
    });
});

builder.Services.AddDbContextFactory<AdminDbContext>(options =>
{
    options.UseNpgsql(settings.PostgresConnectionString());
    options.EnableSensitiveDataLogging(false);
    options.EnableDetailedErrors(false);
});

builder.Services.AddSingleton<IConnectionMultiplexer>(_ => ConnectionMultiplexer.Connect(settings.RedisConnectionString()));
builder.Services.AddSingleton<IMongoClient>(_ => new MongoClient(settings.MongoConnectionString()));
builder.Services.AddSingleton(sp => new MongoLogWriter(sp.GetRequiredService<IMongoClient>(), settings));
builder.Services.AddSingleton(sp => new AppLogger(settings, sp.GetRequiredService<MongoLogWriter>()));

builder.Services.AddSingleton<IAmazonS3>(_ =>
{
    var config = new AmazonS3Config
    {
        ServiceURL = settings.S3Endpoint,
        ForcePathStyle = settings.S3ForcePathStyle,
        AuthenticationRegion = settings.S3Region,
        UseHttp = settings.S3Endpoint.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
    };
    return new AmazonS3Client(new BasicAWSCredentials(settings.S3AccessKey, settings.S3SecretKey), config);
});

builder.Services.AddSingleton<IProducer<string, string>>(_ => new ProducerBuilder<string, string>(new ProducerConfig
{
    BootstrapServers = settings.KafkaBootstrapServers,
    Acks = Acks.All,
    EnableIdempotence = false,
    MessageSendMaxRetries = 5,
    RetryBackoffMs = 1000
}).Build());

builder.Services.AddSingleton<DatabaseMigrator>();
builder.Services.AddSingleton<KafkaTopicInitializer>();
builder.Services.AddSingleton<S3AuditWriter>();
builder.Services.AddSingleton<AuditService>();
builder.Services.AddSingleton<AdminCache>();
builder.Services.AddSingleton<DependencyHealthService>();
builder.Services.AddSingleton<StartupInitializer>();
builder.Services.AddHostedService<OutboxPublisherBackgroundService>();
builder.Services.AddHostedService<KafkaConsumerBackgroundService>();

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.RequireHttpsMetadata = settings.SecurityRequireHttps;
        options.SaveToken = false;
        options.MapInboundClaims = false;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = settings.JwtIssuer,
            ValidateAudience = true,
            ValidAudience = settings.JwtAudience,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(settings.JwtSecret)),
            ValidateLifetime = true,
            RequireExpirationTime = true,
            RequireSignedTokens = true,
            ClockSkew = TimeSpan.FromSeconds(settings.JwtLeewaySeconds),
            NameClaimType = "username",
            RoleClaimType = "role",
            ValidAlgorithms = new[] { SecurityAlgorithms.HmacSha256 }
        };
        options.Events = new JwtBearerEvents
        {
            OnTokenValidated = context =>
            {
                if (context.SecurityToken is JwtSecurityToken jwt && !string.Equals(jwt.Header.Alg, settings.JwtAlgorithm, StringComparison.Ordinal))
                {
                    context.Fail("invalid token algorithm");
                    return Task.CompletedTask;
                }
                if (!AdminClaims.HasRequiredJwtClaims(context.Principal!))
                {
                    context.Fail("missing required auth_service JWT claims");
                    return Task.CompletedTask;
                }
                return Task.CompletedTask;
            },
            OnChallenge = async context =>
            {
                context.HandleResponse();
                await ApiEnvelope.WriteErrorAsync(context.HttpContext, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Authentication required");
            },
            OnForbidden = context => ApiEnvelope.WriteErrorAsync(context.HttpContext, StatusCodes.Status403Forbidden, "FORBIDDEN", "Approved admin access required")
        };
    });

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy(AdminAuthorization.PolicyName, policy =>
    {
        policy.RequireAuthenticatedUser();
        policy.RequireAssertion(context => AdminAuthorization.IsApprovedAdmin(context.User, settings));
    });
});

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    await scope.ServiceProvider.GetRequiredService<StartupInitializer>().InitializeAsync(app.Lifetime.ApplicationStopping);
}

app.UseMiddleware<RequestContextMiddleware>();
app.UseMiddleware<ExceptionHandlingMiddleware>();
app.UseMiddleware<RequestLoggingMiddleware>();
app.UseCors();
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/hello", () => Results.Json(new
{
    status = "ok",
    message = "admin_service is running",
    service = new { name = settings.ServiceName, env = settings.EnvironmentName, version = settings.Version }
}, JsonOptionsFactory.Options));

app.MapGet("/health", (HttpContext http, DependencyHealthService health) => health.CheckAsync(http));
app.MapGet("/docs", () => OpenApiDocument.SwaggerUi(settings));

app.MapGroup("/v1/admin")
   .RequireAuthorization(AdminAuthorization.PolicyName)
   .MapAdminEndpoints();

await app.RunAsync();
