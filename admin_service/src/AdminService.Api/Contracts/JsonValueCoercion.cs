using System.Globalization;
using System.Text.Json;

namespace AdminService.Api.Contracts;

/// <summary>
/// Shared JSON value coercion helpers for legacy/cross-language event payloads.
/// Kafka producers in the current application may emit timestamps as ISO strings,
/// unix seconds, or unix milliseconds. Consumers must parse all three safely.
/// </summary>
public static class JsonValueCoercion
{
    public static DateTimeOffset? CoerceDate(JsonElement value)
    {
        try
        {
            if (value.ValueKind == JsonValueKind.String)
            {
                var text = value.GetString();
                if (string.IsNullOrWhiteSpace(text)) return null;

                if (DateTimeOffset.TryParse(
                    text,
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                    out var parsed))
                {
                    return parsed.ToUniversalTime();
                }

                if (long.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var numericText))
                {
                    return FromUnixValue(numericText);
                }
            }

            if (value.ValueKind == JsonValueKind.Number)
            {
                if (value.TryGetInt64(out var integer)) return FromUnixValue(integer);
                if (value.TryGetDouble(out var number)) return FromUnixValue((long)number);
            }
        }
        catch
        {
            return null;
        }

        return null;
    }

    public static DateTimeOffset FromUnixValue(long value)
    {
        if (Math.Abs(value) >= 1_000_000_000_000L)
        {
            return DateTimeOffset.FromUnixTimeMilliseconds(value).ToUniversalTime();
        }

        return DateTimeOffset.FromUnixTimeSeconds(value).ToUniversalTime();
    }
}
