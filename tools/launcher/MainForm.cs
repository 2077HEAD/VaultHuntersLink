using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace VaultHuntersLauncher;

/// <summary>
/// The launcher window: a WebView2 showing ui/index.html. The page sends {id, cmd, args};
/// we answer {id, ok, data | error}, and push {event, ...} for live status and log lines.
/// </summary>
public sealed class MainForm : Form
{
    private readonly WebView2 _web = new() { Dock = DockStyle.Fill, DefaultBackgroundColor = Color.FromArgb(22, 18, 46) };
    private readonly Settings _settings = Settings.Load();
    private CoopHost? _host;
    private readonly string _gameFolder;

    public MainForm()
    {
        Text = "Vault Hunters Link";
        ClientSize = new Size(1180, 720);
        MinimumSize = new Size(900, 600);
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.FromArgb(22, 18, 46);
        try
        {
            Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!);
        }
        catch
        {
            // default icon
        }
        Controls.Add(_web);
        _gameFolder = FindGameFolder();
        Load += async (_, _) => await InitAsync();
        FormClosing += OnClosing;
    }

    // The launcher lives in the Cyberpunk 2077 folder (next to bin\ and r6\). A folder set in
    // Settings wins, so it also works from elsewhere.
    private string FindGameFolder()
    {
        if (!string.IsNullOrEmpty(_settings.GameFolder) && GameExe(_settings.GameFolder) != null) return _settings.GameFolder;
        var dir = AppContext.BaseDirectory;
        for (var i = 0; i < 4 && dir != null; i++)
        {
            if (GameExe(dir) != null) return dir;
            dir = Path.GetDirectoryName(dir.TrimEnd(Path.DirectorySeparatorChar));
        }
        return AppContext.BaseDirectory;
    }

    private static string? GameExe(string folder)
    {
        var exe = Path.Combine(folder, "bin", "x64", "Cyberpunk2077.exe");
        return File.Exists(exe) ? exe : null;
    }

    private async Task InitAsync()
    {
        try
        {
            var env = await CoreWebView2Environment.CreateAsync(null, Path.Combine(Settings.DataFolder, "WebView2"));
            await _web.EnsureCoreWebView2Async(env);
        }
        catch (Exception e)
        {
            MessageBox.Show(this,
                "The launcher needs Microsoft Edge WebView2, which comes with Windows 11 and most Windows 10 PCs.\n\n" +
                "Install the \"Evergreen\" runtime from Microsoft, then start the launcher again.\n\n" + e.Message,
                "Vault Hunters Link", MessageBoxButtons.OK, MessageBoxIcon.Error);
            Close();
            return;
        }
        var core = _web.CoreWebView2;
        core.Settings.AreDevToolsEnabled = false;
        core.Settings.IsZoomControlEnabled = false;
        core.Settings.AreDefaultContextMenusEnabled = false;
        core.WebMessageReceived += OnMessage;
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("index.html")!;
        using var reader = new StreamReader(stream);
        core.NavigateToString(reader.ReadToEnd());
    }

    private void Push(object payload)
    {
        if (IsDisposed) return;
        var json = JsonSerializer.Serialize(payload);
        if (InvokeRequired)
        {
            BeginInvoke(() => _web.CoreWebView2?.PostWebMessageAsJson(json));
        }
        else
        {
            _web.CoreWebView2?.PostWebMessageAsJson(json);
        }
    }

    private void PushHostState()
    {
        var h = _host;
        Push(new
        {
            @event = "host",
            running = h?.Running ?? false,
            server = new { state = (h?.ServerState ?? CoopHost.Check.Pending).ToString().ToLowerInvariant(), text = h?.ServerText ?? "Not started" },
            router = new { state = (h?.RouterState ?? CoopHost.Check.Pending).ToString().ToLowerInvariant(), text = h?.RouterText ?? "Not started" },
            internet = new { state = (h?.InternetState ?? CoopHost.Check.Pending).ToString().ToLowerInvariant(), text = h?.InternetText ?? "Not started" },
            invite = h?.InviteCode ?? "",
            lan = h?.LanCode ?? "",
            tailscale = h?.TailscaleCode ?? "",
        });
    }

    private async void OnMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        JsonNode? msg;
        try
        {
            msg = JsonNode.Parse(e.WebMessageAsJson);
        }
        catch
        {
            return;
        }
        var id = msg?["id"]?.GetValue<int>() ?? 0;
        var cmd = msg?["cmd"]?.GetValue<string>() ?? "";
        var args = msg?["args"];
        try
        {
            var data = await Handle(cmd, args);
            Push(new { id, ok = true, data });
        }
        catch (Exception ex)
        {
            Push(new { id, ok = false, error = ex.Message });
        }
    }

    private async Task<object?> Handle(string cmd, JsonNode? args)
    {
        switch (cmd)
        {
            case "state":
                return new
                {
                    name = _settings.PlayerName,
                    port = _settings.Port,
                    lastJoin = _settings.LastJoin,
                    openRouter = _settings.OpenRouterPort,
                    gameFolder = _gameFolder,
                    gameFound = GameExe(_gameFolder) != null,
                    serverInstalled = CoopHost.ServerInstalled(_gameFolder),
                    botsInstalled = File.Exists(Path.Combine(_gameFolder, "VaultHuntersServer", "vh-testbot.exe")),
                    version = Application.ProductVersion,
                };

            case "saveSettings":
                _settings.PlayerName = args?["name"]?.GetValue<string>() ?? _settings.PlayerName;
                _settings.Port = Math.Clamp(args?["port"]?.GetValue<int>() ?? _settings.Port, 1024, 65535);
                _settings.OpenRouterPort = args?["openRouter"]?.GetValue<bool>() ?? _settings.OpenRouterPort;
                _settings.Save();
                return new { name = _settings.SafeName() };

            case "hostStart":
                if (_host is { Running: true }) return null;
                _host?.Dispose();
                _host = new CoopHost(_gameFolder, _settings.Port);
                _host.Log += line => Push(new { @event = "log", line });
                _host.Changed += PushHostState;
                PushHostState();
                await _host.StartAsync(_settings.OpenRouterPort, args?["bots"]?.GetValue<bool>() ?? false);
                return null;

            case "hostStop":
                _host?.Stop();
                _host = null;
                PushHostState();
                return null;

            case "decode":
                var decoded = InviteCode.Decode(args?["code"]?.GetValue<string>(), _settings.Port);
                return decoded == null ? null : new { host = decoded.Value.Host, port = decoded.Value.Port };

            case "launch":
                return Launch(args?["mode"]?.GetValue<string>() ?? "host", args?["code"]?.GetValue<string>());

            case "copy":
                Clipboard.SetText(args?["text"]?.GetValue<string>() ?? "");
                return null;

            case "mods":
                return RunModsTool(args?["action"]?.GetValue<string>() ?? "check");

            case "openFolder":
                Process.Start(new ProcessStartInfo("explorer.exe", $"\"{_gameFolder}\"") { UseShellExecute = true });
                return null;
        }
        throw new InvalidOperationException("Unknown command " + cmd);
    }

    // The mod cleanup tool (VH-ModCleanup.ps1 via its .bat files, which ask for admin rights
    // themselves). Opens in its own window so people can read what it did.
    private object? RunModsTool(string action)
    {
        var bat = action switch
        {
            "aside" => "VH Clean Up Mods.bat",
            "restore" => "VH Restore Disabled Mods.bat",
            _ => "VH Check Install.bat",
        };
        var path = Path.Combine(_gameFolder, bat);
        if (!File.Exists(path)) throw new InvalidOperationException(bat + " isn't in your game folder. Unpack VaultHuntersLink-Client.zip there again.");
        if (action != "check" && Process.GetProcessesByName("Cyberpunk2077").Length > 0)
            throw new InvalidOperationException("Close Cyberpunk 2077 first.");
        Process.Start(new ProcessStartInfo(path) { UseShellExecute = true, WorkingDirectory = _gameFolder });
        return null;
    }

    private object Launch(string mode, string? code)
    {
        var exe = GameExe(_gameFolder) ?? throw new InvalidOperationException(
            "Cyberpunk2077.exe wasn't found. Put the launcher in your Cyberpunk 2077 folder (next to bin and r6).");
        string host;
        int port;
        if (mode == "join")
        {
            var target = InviteCode.Decode(code, _settings.Port) ?? throw new InvalidOperationException(
                "That code doesn't look right. It should look like VH-7K2Q9-XMD4A, or an address like 100.64.1.2:1337.");
            (host, port) = target;
            _settings.LastJoin = code!.Trim();
            _settings.Save();
        }
        else
        {
            if (_host is not { Running: true }) throw new InvalidOperationException("Start hosting first.");
            host = "127.0.0.1";
            port = _settings.Port;
        }
        Process.Start(new ProcessStartInfo(exe,
            $"--cyberverse-server-address={host} --cyberverse-server-port={port} --cyberverse-name={_settings.SafeName()}")
        {
            WorkingDirectory = Path.GetDirectoryName(exe)!,
            UseShellExecute = false,
        });
        return new { host, port };
    }

    private void OnClosing(object? sender, FormClosingEventArgs e)
    {
        if (_host is { Running: true })
        {
            var answer = MessageBox.Show(this,
                "You're hosting. Closing the launcher ends the co-op session for everyone and closes the router port.\n\nClose anyway?",
                "Vault Hunters Link", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
            if (answer != DialogResult.Yes)
            {
                e.Cancel = true;
                return;
            }
        }
        _host?.Dispose();
    }
}
