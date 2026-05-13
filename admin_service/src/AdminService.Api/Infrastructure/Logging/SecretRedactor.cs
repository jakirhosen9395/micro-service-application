using System.Text.RegularExpressions;

namespace AdminService.Api.Infrastructure.Logging;

public static partial class SecretRedactor
{
    private static readonly string[] SensitiveKeys =
    {
        "password", "secret", "token", "authorization", "jwt", "access_key", "secret_key", "apikey", "api_key", "connectionstring"
    };

    public static object? RedactValue(string key, object? value)
    {
        return SensitiveKeys.Any(s => key.Contains(s, StringComparison.OrdinalIgnoreCase)) ? "[REDACTED]" : value;
    }

    public static string SafeExceptionMessage(Exception exception)
    {
        var message = exception.Message;
        message = SecretPattern().Replace(message, "$1=[REDACTED]");
        message = BearerPattern().Replace(message, "Bearer [REDACTED]");
        return message;
    }

    public static IReadOnlyDictionary<string, object?> RedactDictionary(IDictionary<string, object?> input)
    {
        return input.ToDictionary(pair => pair.Key, pair => RedactValue(pair.Key, pair.Value));
    }

    [GeneratedRegex("(?i)(password|secret|token|authorization|access_key|secret_key|jwt)=([^;\\s]+)")]
    private static partial Regex SecretPattern();

    [GeneratedRegex("(?i)Bearer\\s+[A-Za-z0-9._~+\\-/]+=*")]
    private static partial Regex BearerPattern();
}
