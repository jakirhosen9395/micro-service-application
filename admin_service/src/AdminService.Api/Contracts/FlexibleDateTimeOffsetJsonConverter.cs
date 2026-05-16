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
                return JsonValueCoercion.FromUnixValue(numericString);
            }

            return DateTimeOffset.UtcNow;
        }

        if (reader.TokenType == JsonTokenType.Number)
        {
            if (reader.TryGetInt64(out var integer)) return JsonValueCoercion.FromUnixValue(integer);
            if (reader.TryGetDouble(out var number)) return JsonValueCoercion.FromUnixValue((long)number);
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

}
