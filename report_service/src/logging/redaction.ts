const SECRET_KEY_PATTERN = /(password|secret|token|authorization|cookie|access[_-]?key|private[_-]?key|refresh|jwt|credential)/i;

export function redactSecrets<T>(value: T, seen = new WeakSet<object>()): T {
  if (value === null || value === undefined) return value;
  if (typeof value !== "object") return value;
  if (value instanceof Date) return value;

  if (seen.has(value as object)) return "[Circular]" as T;
  seen.add(value as object);

  if (Array.isArray(value)) {
    return value.map((item) => redactSecrets(item, seen)) as T;
  }

  const output: Record<string, unknown> = {};
  for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
    if (SECRET_KEY_PATTERN.test(key)) {
      output[key] = "[REDACTED]";
    } else {
      output[key] = redactSecrets(child, seen);
    }
  }
  return output as T;
}
