namespace AdminService.Api.Configuration;

public static class DotEnvLoader
{
    public static void Load()
    {
        var explicitFile = Environment.GetEnvironmentVariable("ADMIN_ENV_FILE");
        if (!string.IsNullOrWhiteSpace(explicitFile))
        {
            LoadFile(explicitFile, overwrite: false);
            return;
        }

        var env = Environment.GetEnvironmentVariable("ADMIN_ENV");
        if (string.IsNullOrWhiteSpace(env))
        {
            LoadFile(".env.dev", overwrite: false);
            return;
        }

        var suffix = env.Trim().ToLowerInvariant() switch
        {
            "development" => "dev",
            "dev" => "dev",
            "stage" => "stage",
            "staging" => "stage",
            "production" => "prod",
            "prod" => "prod",
            _ => "dev"
        };
        LoadFile($".env.{suffix}", overwrite: false);
    }

    private static void LoadFile(string fileName, bool overwrite)
    {
        var candidates = new[]
        {
            Path.GetFullPath(fileName),
            Path.Combine(AppContext.BaseDirectory, fileName),
            Path.Combine(AppContext.BaseDirectory, "..", "..", "..", fileName)
        };

        var path = candidates.FirstOrDefault(File.Exists);
        if (path is null) return;

        foreach (var rawLine in File.ReadAllLines(path))
        {
            var line = rawLine.Trim();
            if (line.Length == 0 || line.StartsWith('#')) continue;
            var idx = line.IndexOf('=');
            if (idx <= 0) continue;
            var key = line[..idx].Trim();
            var value = line[(idx + 1)..].Trim();
            if ((value.StartsWith('"') && value.EndsWith('"')) || (value.StartsWith('\'') && value.EndsWith('\'')))
            {
                value = value[1..^1];
            }
            if (!overwrite && Environment.GetEnvironmentVariable(key) is not null) continue;
            Environment.SetEnvironmentVariable(key, value);
        }
    }
}
