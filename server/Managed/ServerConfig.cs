using System.Text.Json;
using NLog;

namespace Cyberverse.Server;

public class FalloffTier
{
    public float MaxDistance { get; set; }
    public int Divisor { get; set; }
}

public class InterestConfig
{
    public float EnterRadius { get; set; } = 425.0f;
    public float ExitRadius { get; set; } = 470.0f;
    public float CellSize { get; set; } = 470.0f;
    public List<FalloffTier> Falloff { get; set; } = DefaultFalloff();

    public static List<FalloffTier> DefaultFalloff() =>
    [
        new FalloffTier { MaxDistance = 100.0f, Divisor = 1 },
        new FalloffTier { MaxDistance = 250.0f, Divisor = 3 },
        new FalloffTier { MaxDistance = 1e9f, Divisor = 5 }
    ];
}

public class CombatConfig
{
    /// <summary>
    /// Upper bound for the damage-per-hit a client may claim for its own weapon.
    ///
    /// The shooter reports this number because only its machine has the weapon's rolled stats
    /// (see PlayerShoot.damagePerHit) — which means a modified client can claim anything. This
    /// cap is the floor of the defence, not the ceiling: it stops "one shot, 99999 damage" but
    /// not a pistol claiming a sniper's damage. A real per-weapon-class limit needs a mapping
    /// from itemIdWeapon to weapon class, which the server does not have and which would have
    /// to be generated from TweakDB — a separate piece of work.
    ///
    /// The default is deliberately generous. A cap set below what a legitimate high-end weapon
    /// rolls would silently weaken honest players, which is worse than letting a cheat through:
    /// the cheat is visible in the log, the nerf is not.
    /// </summary>
    public float MaxDamagePerHit { get; set; } = 1000.0f;
}

public class ServerConfig
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    /// <summary>UDP port to listen on (Vault Hunters co-op: was hardcoded 1337). CLI: --port=N</summary>
    public ushort Port { get; set; } = 1337;

    public InterestConfig Interest { get; set; } = new();
    public CombatConfig Combat { get; set; } = new();

    public static ServerConfig Load(string path)
    {
        ServerConfig? config = null;
        try
        {
            if (File.Exists(path))
            {
                config = JsonSerializer.Deserialize<ServerConfig>(File.ReadAllText(path),
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            }
            else
            {
                Logger.Info("No config.json found at {0}, using defaults", path);
            }
        }
        catch (Exception e)
        {
            Logger.Warn(e, "config.json could not be read, using defaults");
        }

        return Validate(config ?? new ServerConfig());
    }

    private static ServerConfig Validate(ServerConfig config)
    {
        var i = config.Interest;
        if (i.EnterRadius <= 0 || i.ExitRadius <= i.EnterRadius || i.CellSize <= 0)
        {
            Logger.Warn("Invalid interest config (need exitRadius > enterRadius > 0, cellSize > 0) — using defaults");
            config.Interest = new InterestConfig();
        }

        var falloff = config.Interest.Falloff;
        var valid = falloff.Count > 0;
        for (var t = 0; t < falloff.Count && valid; t++)
        {
            if (falloff[t].Divisor < 1 || (t > 0 && falloff[t].MaxDistance <= falloff[t - 1].MaxDistance))
            {
                valid = false;
            }
        }
        if (!valid)
        {
            Logger.Warn("Invalid falloff tiers (need ascending maxDistance, divisor >= 1) — using defaults");
            config.Interest.Falloff = InterestConfig.DefaultFalloff();
        }

        if (!float.IsFinite(config.Combat.MaxDamagePerHit) || config.Combat.MaxDamagePerHit <= 0)
        {
            Logger.Warn("Invalid combat.maxDamagePerHit (need a finite value > 0) — using default");
            config.Combat = new CombatConfig();
        }

        return config;
    }
}
