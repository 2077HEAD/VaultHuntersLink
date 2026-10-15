using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using Mono.Nat;

namespace VaultHuntersLauncher;

/// <summary>
/// Hosting: runs the co-op server, asks the router to open the port (UPnP / NAT-PMP, the same
/// thing game consoles do), works out the address friends need and turns it into invite codes.
/// Everything is undone in Stop().
/// </summary>
public sealed class CoopHost : IDisposable
{
    public enum Check { Pending, Ok, Warn, Fail }

    public event Action<string>? Log;
    public event Action? Changed;

    public Check ServerState { get; private set; } = Check.Pending;
    public string ServerText { get; private set; } = "Not started";
    public Check RouterState { get; private set; } = Check.Pending;
    public string RouterText { get; private set; } = "Not started";
    public Check InternetState { get; private set; } = Check.Pending;
    public string InternetText { get; private set; } = "Not started";

    public string InviteCode { get; private set; } = "";
    public string LanCode { get; private set; } = "";
    public bool Running => _server is { HasExited: false };

    private readonly string _gameFolder;
    private readonly int _port;
    private Process? _server;
    private Process? _bots;
    private INatDevice? _router;
    private Mapping? _mapping;
    private CancellationTokenSource? _cts;

    public CoopHost(string gameFolder, int port)
    {
        _gameFolder = gameFolder;
        _port = port;
    }

    private string ServerFolder => Path.Combine(_gameFolder, "VaultHuntersServer");
    public static bool ServerInstalled(string gameFolder) =>
        File.Exists(Path.Combine(gameFolder, "VaultHuntersServer", "Cyberverse.Server.exe"));

    public async Task StartAsync(bool openRouter, bool testBots)
    {
        _cts = new CancellationTokenSource();
        ApplyPendingUpdate();
        StartServer();
        if (testBots) StartBots();

        var lan = LocalAddress();
        LanCode = lan != null ? VaultHuntersLauncher.InviteCode.Encode(lan, _port) : "";
        Changed?.Invoke();

        IPAddress? routerPublic = null;
        if (openRouter)
        {
            routerPublic = await OpenRouterPortAsync(_cts.Token);
        }
        else
        {
            RouterState = Check.Warn;
            RouterText = "Skipped (turned off in Settings). Friends outside your home need UDP port " + _port + " forwarded.";
            Changed?.Invoke();
        }

        var publicIp = await PublicAddressAsync(_cts.Token);
        if (publicIp == null)
        {
            SetInternet(Check.Fail, "Couldn't look up your internet address. Friends at home can still use the home code.");
        }
        else if (routerPublic != null && !routerPublic.Equals(publicIp))
        {
            SetInternet(Check.Fail,
                "Your provider shares one internet address between many homes (carrier-grade NAT), so friends " +
                "outside your home can't reach you directly. Use Tailscale or ZeroTier, or ask your provider for a public IP.");
            InviteCode = "";
        }
        else
        {
            InviteCode = VaultHuntersLauncher.InviteCode.Encode(publicIp, _port);
            SetInternet(RouterState == Check.Ok ? Check.Ok : Check.Warn,
                RouterState == Check.Ok
                    ? $"Ready. Friends anywhere can join with the invite code ({publicIp})."
                    : $"Your address is {publicIp}, but the router port isn't confirmed open - friends outside your home may not get through.");
        }
        Changed?.Invoke();
    }

    private void SetInternet(Check state, string text)
    {
        InternetState = state;
        InternetText = text;
        Changed?.Invoke();
    }

    // ---------- server ----------

    private void ApplyPendingUpdate()
    {
        var update = Path.Combine(ServerFolder, "_update");
        if (!Directory.Exists(update)) return;
        try
        {
            foreach (var file in Directory.GetFiles(update))
            {
                File.Copy(file, Path.Combine(ServerFolder, Path.GetFileName(file)), true);
                File.Delete(file);
            }
            Directory.Delete(update);
            Log?.Invoke("Applied a pending server update.");
        }
        catch (Exception e)
        {
            Log?.Invoke("Couldn't apply the pending server update (" + e.Message + "). Starting the current server.");
        }
    }

    private void StartServer()
    {
        var exe = Path.Combine(ServerFolder, "Cyberverse.Server.exe");
        if (!File.Exists(exe))
        {
            ServerState = Check.Fail;
            ServerText = "The co-op server isn't installed. Unpack VaultHuntersLink-Server.zip into the game folder.";
            Changed?.Invoke();
            return;
        }
        _server = StartHidden(exe, $"--port={_port}", ServerFolder, "server");
        ServerState = _server != null ? Check.Ok : Check.Fail;
        ServerText = _server != null ? $"Running on UDP port {_port}" : "Couldn't start the co-op server.";
        Changed?.Invoke();
    }

    private void StartBots()
    {
        var exe = Path.Combine(ServerFolder, "vh-testbot.exe");
        if (!File.Exists(exe)) return;
        var spot = "0,0,0";
        var spotFile = Path.Combine(_gameFolder, "bin", "x64", "plugins", "cyber_engine_tweaks", "mods", "VaultHunters", "testbot_position.txt");
        try
        {
            if (File.Exists(spotFile)) spot = File.ReadAllText(spotFile).Trim();
        }
        catch
        {
            // keep the default
        }
        _bots = StartHidden(exe,
            $"--server 127.0.0.1 --port {_port} --count 3 --pattern circle --center {spot} --hz 20 --jump-every 8 --vh-class 0 --lobby --follow-host",
            ServerFolder, "test bots");
    }

    private Process? StartHidden(string exe, string args, string folder, string tag)
    {
        try
        {
            var p = new Process
            {
                StartInfo = new ProcessStartInfo(exe, args)
                {
                    WorkingDirectory = folder,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                },
                EnableRaisingEvents = true,
            };
            p.OutputDataReceived += (_, e) => { if (!string.IsNullOrWhiteSpace(e.Data) && !e.Data.StartsWith("stats:")) Log?.Invoke($"[{tag}] {e.Data}"); };
            p.ErrorDataReceived += (_, e) => { if (!string.IsNullOrWhiteSpace(e.Data)) Log?.Invoke($"[{tag}] {e.Data}"); };
            p.Exited += (_, _) =>
            {
                Log?.Invoke($"[{tag}] stopped");
                if (tag == "server")
                {
                    ServerState = Check.Fail;
                    ServerText = "The co-op server stopped.";
                    Changed?.Invoke();
                }
            };
            p.Start();
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            return p;
        }
        catch (Exception e)
        {
            Log?.Invoke($"[{tag}] couldn't start: {e.Message}");
            return null;
        }
    }

    // ---------- router (UPnP / NAT-PMP) ----------

    private async Task<IPAddress?> OpenRouterPortAsync(CancellationToken ct)
    {
        RouterState = Check.Pending;
        RouterText = "Asking your router to open the port...";
        Changed?.Invoke();

        var found = new TaskCompletionSource<INatDevice>(TaskCreationOptions.RunContinuationsAsynchronously);
        void OnFound(object? s, DeviceEventArgs e) => found.TrySetResult(e.Device);
        NatUtility.DeviceFound += OnFound;
        NatUtility.StartDiscovery();
        try
        {
            var done = await Task.WhenAny(found.Task, Task.Delay(6000, ct));
            if (done != found.Task)
            {
                RouterState = Check.Warn;
                RouterText = "Your router didn't answer. Turn on UPnP in its settings, or forward UDP port " + _port + " to this PC.";
                Changed?.Invoke();
                return null;
            }
            _router = found.Task.Result;
            var mapping = new Mapping(Protocol.Udp, _port, _port, 0, "Vault Hunters co-op");
            try
            {
                await _router.CreatePortMapAsync(mapping);
            }
            catch
            {
                // some routers refuse "forever": ask for two hours instead
                mapping = new Mapping(Protocol.Udp, _port, _port, 7200, "Vault Hunters co-op");
                await _router.CreatePortMapAsync(mapping);
            }
            _mapping = mapping;
            var external = await _router.GetExternalIPAsync();
            RouterState = Check.Ok;
            RouterText = $"Port {_port} opened on your router";
            Changed?.Invoke();
            Log?.Invoke($"Router: UDP {_port} forwarded to this PC, router reports {external}");
            return external;
        }
        catch (Exception e)
        {
            RouterState = Check.Warn;
            RouterText = "Your router refused the request (" + e.Message + "). Forward UDP port " + _port + " to this PC by hand.";
            Changed?.Invoke();
            return null;
        }
        finally
        {
            NatUtility.DeviceFound -= OnFound;
            NatUtility.StopDiscovery();
        }
    }

    // ---------- addresses ----------

    private static async Task<IPAddress?> PublicAddressAsync(CancellationToken ct)
    {
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(6) };
        foreach (var url in new[] { "https://api.ipify.org", "https://icanhazip.com" })
        {
            try
            {
                var text = (await http.GetStringAsync(url, ct)).Trim();
                if (IPAddress.TryParse(text, out var ip) && ip.AddressFamily == AddressFamily.InterNetwork) return ip;
            }
            catch
            {
                // try the next one
            }
        }
        return null;
    }

    /// <summary>This PC's address on the home network (for friends in the same house).</summary>
    public static IPAddress? LocalAddress()
    {
        foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (nic.OperationalStatus != OperationalStatus.Up || nic.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
            var props = nic.GetIPProperties();
            if (props.GatewayAddresses.Count == 0) continue;   // skip VPN / virtual adapters without a route
            foreach (var a in props.UnicastAddresses)
            {
                if (a.Address.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(a.Address)) return a.Address;
            }
        }
        return null;
    }

    // ---------- stopping ----------

    public void Stop()
    {
        _cts?.Cancel();
        TryKill(_bots);
        TryKill(_server);
        _bots = null;
        _server = null;
        if (_router != null && _mapping != null)
        {
            try
            {
                _router.DeletePortMapAsync(_mapping).Wait(3000);
                Log?.Invoke($"Router: UDP {_port} closed again");
            }
            catch
            {
                // the router forgets it eventually (or keeps an open port nothing listens on)
            }
        }
        _mapping = null;
        ServerState = RouterState = InternetState = Check.Pending;
        ServerText = RouterText = InternetText = "Not started";
        InviteCode = LanCode = "";
        Changed?.Invoke();
    }

    private static void TryKill(Process? p)
    {
        try
        {
            if (p is { HasExited: false }) p.Kill(true);
        }
        catch
        {
            // already gone
        }
    }

    public void Dispose() => Stop();
}
