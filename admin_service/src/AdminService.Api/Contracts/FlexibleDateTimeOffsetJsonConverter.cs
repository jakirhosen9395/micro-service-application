using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AdminService.Api.Contracts;

/// <summary>
/// Accepts canonical ISO-8601 timestamps and legacy numeric epoch timestamps from other services.
/// Some existing Java/Go/Node producers emit timestamp as unix seconds or milliseconds.
/// The admin service must consume those events without sending them to the DLQ or APM error stream.
/// </summary>
public sealed class FlexibleDateTimeOffsetJsonConverter : JsonConverter<DateTimeOffset>
{
    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.String)
        {
            var value = reader.GetString();
            if (string.IsNullOrWhiteSpace(value)) return DateTimeOffset.UtcNow;

            if (DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var parsed))
            {
                return parsed.ToUniversalTime();
            }

            if (long.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var numericString))
            {
                return FromUnixValue(numericString);
            }

            return DateTimeOffset.UtcNow;
        }

        if (reader.TokenType == JsonTokenType.Number)
        {
            if (reader.TryGetInt64(out var integer)) return FromUnixValue(integer);
            if (reader.TryGetDouble(out var number)) return FromUnixValue((long)number);
        }

        if (reader.TokenType == JsonTokenType.Null)
        {
            return DateTimeOffset.UtcNow;
        }

        throw new JsonException($"Cannot convert {reader.TokenType} to DateTimeOffset.");
    }

    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options)
    {
        writer.WriteStringValue(value.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture));
    }

    private static DateTimeOffset FromUnixValue(long value)
    {
        try
        {
            // Values larger than 10^12 are almost certainly milliseconds.
            if (Math.Abs(value) >= 1_000_000_000_000L)
            {
                return DateTimeOffset.FromUnixTimeMilliseconds(value).ToUniversalTime();
            }

            return DateTimeOffset.FromUnixTimeSeconds(value).ToUniversalTime();
        }
        catch (ArgumentOutOfRangeException)
        {
            return DateTimeOffset.UtcNow;
        }
    }
}
