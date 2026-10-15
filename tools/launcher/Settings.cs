using System.Text.Json;

namespace VaultHuntersLauncher;

/// <summary>What the launcher remembers, in %LocalAppData%\VaultHuntersLink\launcher.json.</summary>
public class Settings
{
    public string PlayerName { get; set; } = Environment.UserName;
    public int Port { get; set; } = 1337;
    public string LastJoin { get; set; } = "";
    public bool OpenRouterPort { get; set; } = true;
    public string GameFolder { get; set; } = "";

    public static string DataFolder =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "VaultHuntersLink");

    private static string FilePath => Path.Combine(DataFolder, "launcher.json");

    public static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new Settings();
            }
        }
        catch
        {
            // a broken file just means defaults
        }
        return new Settings();
    }

    public void Save()
    {
        Directory.CreateDirectory(DataFolder);
        File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
    }

    /// <summary>Name as the game gets it: no spaces (the command line splits on them), max 16 characters.</summary>
    public string SafeName()
    {
        var chars = PlayerName.Where(c => char.IsLetterOrDigit(c) || c is '_' or '-' or '.').ToArray();
        var name = new string(chars);
        if (name.Length == 0) name = "VaultHunter";
        return name.Length > 16 ? name[..16] : name;
    }
}
