import Cyberverse.Network.Managers.*
//import Codeware.*

// Vault Hunters Link: the client used to load the last checkpoint as soon as the server accepted
// the login, skipping the main menu. Removed: the main menu now hosts the co-op lobby (Vault
// Hunters mod, Coop/Lobby.reds), where the host starts the session for everyone at once.

@wrapMethod(PlayerPuppet)
protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
    wrappedMethod(action, consumer);
    let name = ListenerAction.GetName(action);
    let type = ListenerAction.GetType(action);
    let value = ListenerAction.GetValue(action);

    GameInstance.GetNetworkGameSystem().playerActionTracker.RecordPlayerAction(name, type, value);

    // if (StrCmp(NameToString(name), "Jump") == 0 && StrCmp(EnumValueToString("gameinputActionType", Cast(EnumInt(type))), "BUTTON_RELEASED") == 0) {
    //     let npcSpec = new DynamicEntitySpec();
    //     //npcSpec.recordID = t"Character.spr_animals_bouncer1_ranged1_omaha_mb";
    //     npcSpec.recordID = t"Character.Panam";
    //     npcSpec.appearanceName = n"random";

    //     // base\characters\entities\main_npc\panam.ent
    //     //npcSpec.recordID = t"Vehicle.v_sport2_quadra_type66";
    //     //npcSpec.appearanceName = n"quadra_type66__basic_bulleat";
    //     npcSpec.appearanceName = n"random";
    //     npcSpec.position = this.GetWorldPosition();//(4.0, -45.0);
    //     npcSpec.orientation = this.GetWorldOrientation();//(-40.0);
    //     npcSpec.persistState = false;
    //     npcSpec.persistSpawn = false;
    //     npcSpec.tags = [n"MyMod"];

    //     GameInstance.GetDynamicEntitySystem().CreateEntity(npcSpec);
    // }
}

@wrapMethod(PlayerPuppet)
protected cb func OnMountingEvent(evt: ref<MountingEvent>) -> Bool {
    let result = wrappedMethod(evt);
    GameInstance.GetNetworkGameSystem().playerActionTracker.OnMounting(evt);
    return result;
}

@wrapMethod(PlayerPuppet)
protected cb func OnUnmountingEvent(evt: ref<UnmountingEvent>) -> Bool {
    let result = wrappedMethod(evt);
    GameInstance.GetNetworkGameSystem().playerActionTracker.OnUnmounting(evt);
    return result;
}

// Draw detection (choomlink-e9eg): fires on EVERY draw, including quick-drawing the same
// weapon again — the slot listener below misses those, because holstering never removes
// the item from its attachment slot (69 equip / 0 unequip slot events over a whole
// two-client session, 2026-07-31). Queued by the equipment PSM's equip cycle
// (equipment.script:195-198).
@wrapMethod(PlayerPuppet)
protected cb func OnWeaponEquipEvent(evt: ref<WeaponEquipEvent>) -> Bool {
    let result = wrappedMethod(evt);
    if IsDefined(evt.item) {
        let itemId = evt.item.GetItemID();
        let isWeapon = RPGManager.IsItemWeapon(itemId)
            || RPGManager.IsItemTypeCyberwareWeapon(RPGManager.GetItemType(itemId));
        GameInstance.GetNetworkGameSystem().playerActionTracker
            .OnItemEquipped(EquipmentSystem.GetPlacementSlot(itemId), itemId, isWeapon);
    }
    return result;
}

// Holster detection (choomlink-e9eg): the unequip PSM cycle keeps the item in its slot, so
// slot listeners never see holstering. An @addMethod event callback for UnequipEnd on
// PlayerPuppet never fired (verified live 2026-07-31) — wrap the PSM state class that
// queues the event instead (equipment.script:944ff), which is guaranteed to run.
@wrapMethod(UnequipCycleEvents)
protected func OnExit(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
    wrappedMethod(stateContext, scriptInterface);
    let item = this.GetItemIDFromParam(this.stateMachineInstanceData, stateContext);
    if !ItemID.IsValid(item) {
        return;
    }
    // Right hand only — the cycle also runs for left-hand gadgets/consumables.
    if NotEquals(EquipmentSystem.GetPlacementSlot(item), t"AttachmentSlots.WeaponRight") {
        return;
    }
    let isWeapon = RPGManager.IsItemWeapon(item)
        || RPGManager.IsItemTypeCyberwareWeapon(RPGManager.GetItemType(item));
    GameInstance.GetNetworkGameSystem().playerActionTracker
        .OnItemUnequipped(t"AttachmentSlots.WeaponRight", item, isWeapon);
}

@wrapMethod(PlayerPuppet)
public final func OnItemEquipped(slot: TweakDBID, item: ItemID) -> Void {
    // Cyberware weapons (mantis blades & co.) are category Cyberware, not Weapon — but they
    // land in AttachmentSlots.WeaponRight like any gun (vanilla prereqs.script:454), so the
    // flag must cover both. The pipeline itself never filters on isWeapon.
    let isWeapon = RPGManager.IsItemWeapon(item)
        || RPGManager.IsItemTypeCyberwareWeapon(RPGManager.GetItemType(item));
    GameInstance.GetNetworkGameSystem().playerActionTracker.OnItemEquipped(slot, item, isWeapon);
}

@wrapMethod(PlayerPuppet)
public final func OnItemUnequipped(slot: TweakDBID, item: ItemID) -> Void {
    let isWeapon = RPGManager.IsItemWeapon(item)
        || RPGManager.IsItemTypeCyberwareWeapon(RPGManager.GetItemType(item));
    GameInstance.GetNetworkGameSystem().playerActionTracker.OnItemUnequipped(slot, item, isWeapon);
}

// Shot detection (choomlink-77e8): the player state machine's shoot state fires for EVERY
// player ranged attack, including hitscan weapons — `BaseProjectile.OnShoot` only sees
// scripted projectiles and stayed silent for normal ammo through a whole live session
// (2026-07-31). This PSM runs exclusively for the local player (NPCs use behavior trees),
// so remote-puppet fire can never echo back through it.
@wrapMethod(ShootEvents)
protected final func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
    wrappedMethod(stateContext, scriptInterface);
    let weapon = this.GetWeaponObject(scriptInterface);
    if IsDefined(weapon) {
        // Den Schadenswert HIER lesen, nicht beim Empfaenger: nur auf dem Rechner des Schuetzen
        // ist das eine echte Waffe mit ausgewuerfelten Stats. Beim Empfaenger haengt dieselbe
        // Waffe an einem NPC-Puppet und meldet 0 (gemessen 2026-08-03) — das war die Ursache,
        // dass jeder Treffer landete und sich zu null rechnete.
        // Stat-Quelle wie in damageSystem.script:2606.
        let stats = GameInstance.GetStatsSystem(weapon.GetGame());
        let dmg = stats.GetStatValue(Cast<StatsObjectID>(weapon.GetEntityID()),
                                     gamedataStatType.EffectiveDamagePerHit);
        // Zielpunkt mitschicken statt nur der Blickrichtung (2026-08-07). Beim Empfaenger wurde
        // der Punkt bisher als "Koerpermitte des Puppets + Richtung * 50 m" rekonstruiert; die
        // Kugel verlaesst aber die Muendung daneben, sodass die Schusslinie parallel versetzt
        // lief — rund 23 cm seitlich auf 3,7 m. Eine Richtung laesst sich nicht in den
        // urspruenglichen Strahl zurueckverwandeln, solange der Ursprung ein anderer ist.
        //
        // GetLookAtObject ist die Auswahl, die das Spiel selbst fuer den Spieler trifft
        // (gameObject.script:2324 nutzt sie genauso). Trifft der Blick nichts, bleibt der Punkt
        // null und der Empfaenger faellt auf die alte Naeherung zurueck — fuer PvP ist der
        // interessante Fall ohnehin der, in dem jemand auf einen Mitspieler zielt.
        let aimPoint: Vector4;
        let lookedAt = GameInstance.GetTargetingSystem(weapon.GetGame())
            .GetLookAtObject(scriptInterface.executionOwner, true, true);
        if IsDefined(lookedAt) {
            aimPoint = lookedAt.GetWorldPosition();
            // Fusspunkt anheben: GetWorldPosition eines Puppets liegt am Boden, ein Schuss
            // dorthin geht unter dem Ziel durch.
            aimPoint.Z += 1.0;
        }
        GameInstance.GetNetworkGameSystem().playerActionTracker
            .OnPlayerShoot(weapon.GetItemID(), scriptInterface.executionOwner.GetWorldPosition(), dmg, aimPoint);
    }
}

@wrapMethod(BaseProjectile)
protected cb func OnShootTarget(eventData: ref<gameprojectileShootTargetEvent>) -> Bool {
    wrappedMethod(eventData);
    FTLog("Shoot Target");
}

// @wrapMethod(GameObject)
// protected cb func OnHit(evt: ref<gameHitEvent>) -> Bool {
//     wrappedMethod(evt);
//     FTLog("OnHit");
//     GameInstance.GetNetworkGameSystem().playerActionTracker.OnHit(this, evt);
// }

// Health reporting (choomlink-2hum). Hooked to the stat pool itself, not to a damage event:
// health also changes through healing, regeneration, inhalers, fall damage and quest scripts, and
// "health agrees on both clients" has to hold for all of those, not just for gunfights. There is
// no HealthChangeEvent in the game — this listener class is the mechanism (vanilla
// entityHealthBar.script:40-46 registers it exactly like this).
public class ChoomLinkPlayerHealthListener extends ScriptStatPoolsListener {
    private let m_player: wref<PlayerPuppet>;
    // Rate limit: the pool ticks continuously during regeneration, and every tick would otherwise
    // become a packet. Half a percent is below what any observer can see on a health bar.
    // (Separate flag rather than a negative sentinel: redscript rejects negative field defaults.)
    private let m_lastReported: Float;
    private let m_hasReported: Bool;

    public func SetPlayer(player: ref<PlayerPuppet>) -> Void {
        this.m_player = player;
    }

    public func OnStatPoolValueChanged(oldValue: Float, newValue: Float, percToPoints: Float) -> Void {
        // Zweitherz-Stat auffrischen. Er geht im Wiederbelebungspfad verloren (gemessen
        // 2026-08-07), und weil AddModifier verzoegert wirkt, muss das lange vor dem
        // naechsten Tod passieren. Dieser Listener ist dafuer die richtige Stelle: er feuert
        // bei jeder Gesundheitsaenderung, also auch waehrend der Regeneration nach dem
        // Respawn — Sekunden bevor der Stat wieder gebraucht wird.
        if IsDefined(this.m_player) {
            let stats = GameInstance.GetStatsSystem(this.m_player.GetGame());
            let objId = Cast<StatsObjectID>(this.m_player.GetEntityID());
            if stats.GetStatValue(objId, gamedataStatType.HasSecondHeart) <= 0.0 {
                ChoomLinkRespawn.GrantSecondHeart(this.m_player);
            }
        }

        if this.m_hasReported && AbsF(newValue - this.m_lastReported) < 0.5 && newValue > 0.0 {
            return;
        }
        this.m_lastReported = newValue;
        this.m_hasReported = true;
        // Der Tod wird NICHT mehr aus dieser Zahl abgeleitet: mit aktivem Zweitherz klemmt
        // die Engine die Gesundheit bei 1 % fest (statPoolsManager.script:309-314), der Wert
        // erreicht also nie 0. Die Todesmeldung haengt jetzt an DeathEvents.OnEnter.
        GameInstance.GetNetworkGameSystem().playerActionTracker.OnPlayerHealthChanged(newValue, false);
    }
}

@addField(PlayerPuppet)
let choomlink_healthListener: ref<ChoomLinkPlayerHealthListener>;

@wrapMethod(PlayerPuppet)
protected cb func OnGameAttached() -> Bool {
    let result = wrappedMethod();
    let listener = new ChoomLinkPlayerHealthListener();
    listener.SetPlayer(this);
    this.choomlink_healthListener = listener;
    GameInstance.GetStatPoolsSystem(this.GetGame())
        .RequestRegisteringListener(Cast<StatsObjectID>(this.GetEntityID()), gamedataStatPoolType.Health, listener);
    ChoomLinkRespawn.GrantSecondHeart(this);
    return result;
}

// Respawn statt Todesmenue (choomlink-2hum). Ohne das endet ein Tod im Einzelspieler-
// Bildschirm "FLATLINED / LOAD LAST CHECKPOINT" — in-game belegt 2026-08-03 — und wirft den
// Spieler aus der Sitzung.
//
// Das Spiel bringt den Mechanismus selbst mit: das Zweitherz-Cyberware. Entscheidend ist dabei
// der STAT gamedataStatType.HasSecondHeart, nicht der gleichnamige Statuseffekt — eine
// Verwechslung, die den ersten Anlauf lahmlegte. Die Kette in Vanilla:
//
//   HasSecondHeart > 0
//     -> SecondHeartStatListener schaltet God-Mode Immortal ein
//        (playerListeners.script:557-570)
//     -> Immortal klemmt die Gesundheit bei 1 % fest (statPoolsManager.script:309-314)
//     -> DeathDecisions loest den Tod stattdessen bei <= 1,10 % aus
//        (highLevelTransitions.script:505-509)
//     -> SetIsResurrectionAllowedBasedOnState erlaubt die Wiederbelebung und setzt das
//        Todesmenue-Blackboard gar nicht erst (:169-183)
//     -> ResurrectEvents.OnEnter legt BaseStatusEffect.SecondHeart als ABKLINGZEIT an (:598),
//        ResurrectDecisions wartet auf deren Ablauf (:583). Dieser Effekt enthaelt laut
//        TweakDB (zur Laufzeit ausgelesen 2026-08-07) genau ein Paket mit genau einem
//        Modifikator: IsInvulnerable, additiv +1. Er ruehrt HasSecondHeart NICHT an und ist
//        fuer unseren Fall folgenlos — er macht nur kurz unverwundbar.
//     -> PlayerPuppet.OnResurrected ist bereits mehrspielerbewusst: 20 % statt 100 %
//        bei IsMultiplayer (player.script:5177-5190)
//
// CDPR hat den PvP-Respawn also selbst vorgesehen; wir muessen nur den Stat setzen.
//
// DESIGNENTSCHEIDUNG, bewusst minimal gehalten: Wiederbelebung an Ort und Stelle. Ein
// Spawnpunkt-System gibt es im Spiel nicht (recherchiert), das waere ein eigenes Vorhaben —
// ebenso die Frage, ob ein Respawn Verzoegerung oder Kosten haben soll.
public class ChoomLinkRespawn {
    public static func GrantSecondHeart(player: ref<PlayerPuppet>) -> Void {
        let stats = GameInstance.GetStatsSystem(player.GetGame());
        let objId = Cast<StatsObjectID>(player.GetEntityID());
        // Nur setzen, wenn der Stat noch nicht anliegt — sonst wuerde eine getragene
        // Zweitherz-Cyberware faelschlich unserem Code zugeschrieben (genau diese Verwechslung
        // hat am 2026-08-07 drei Testlaeufe wertlos gemacht, siehe choomlink-2hum).
        if stats.GetStatValue(objId, gamedataStatType.HasSecondHeart) <= 0.0 {
            // ForceModifier statt AddModifier. Ein per AddModifier gesetzter Modifikator
            // ueberlebt die Wiederbelebung nicht: am 2026-08-07 stand der Stat beim zweiten
            // Tod wieder auf 0, und ein erneutes AddModifier holte ihn ueber sechs Sekunden
            // nicht zurueck, obwohl derselbe Aufruf beim Anhaengen des Puppets sofort wirkt.
            //
            // AddSavedModifier waere die andere Moeglichkeit, scheidet aber aus: "saved"
            // heisst in den Spielstand geschrieben, und ein Mehrspieler-Detail hat im
            // Einzelspieler-Save des Nutzers nichts verloren. ForceModifier wirkt nur zur
            // Laufzeit — genau die Reichweite, die wir wollen.
            stats.ForceModifier(objId, RPGManager.CreateStatModifier(
                gamedataStatType.HasSecondHeart, gameStatModifierType.Additive, 1.0));
        }
    }
}

// Todesmeldung. Sitzt am Zustandsautomaten statt an der Gesundheitszahl, weil die mit
// Zweitherz nie 0 erreicht.
//
// Den Zweitherz-Stat HIER nachzuziehen wuerde zu spaet kommen: StatsSystem.AddModifier wirkt
// nicht sofort (gemessen 2026-08-07 — unmittelbar nach dem Aufruf las der Stat immer noch 0).
// Das Auffrischen sitzt stattdessen im Gesundheits-Listener, wo Zeit dafuer ist.
@wrapMethod(DeathEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
    GameInstance.GetNetworkGameSystem().playerActionTracker.OnPlayerHealthChanged(0.0, true);
    wrappedMethod(stateContext, scriptInterface);
}

@wrapMethod(PlayerPuppet)
protected func OnResurrected() -> Void {
    wrappedMethod();
    let health = GameInstance.GetStatPoolsSystem(this.GetGame())
        .GetStatPoolValue(Cast<StatsObjectID>(this.GetEntityID()), gamedataStatPoolType.Health, true);

    // BaseStatusEffect.SecondHeart bleibt bewusst LIEGEN. Er wurde hier zeitweise abgeraeumt,
    // in der Annahme, er sperre den naechsten Respawn — das war falsch, und das Abraeumen war
    // schaedlich:
    //
    // Der Datensatz enthaelt laut TweakDB (zur Laufzeit ausgelesen 2026-08-07) genau ein Paket
    // mit genau einem Modifikator: IsInvulnerable, additiv +1. Er ist damit der SPAWNSCHUTZ
    // nach der Wiederbelebung, nicht die Sperre dagegen. DeathDecisions.EnterCondition steigt
    // bei aktiver Invulnerable-Gottheit sofort aus (highLevelTransitions.script:506-508) —
    // genau das gibt dem Spieler die Sekunden, um nach dem Respawn wegzukommen.
    //
    // Ohne ihn steht der Spieler unter Dauerfeuer in einer Todesschleife: sterben, wiederbelebt
    // werden, im selben Atemzug wieder sterben. Vom Nutzer am 2026-08-07 im Spiel gesehen
    // ("ich sehe den revive jetzt die ganze Zeit"), und im Log mit 275 Gesundheitsmeldungen in
    // 45 Sekunden wiedergefunden.
    //
    // Den zweiten Respawn sperrte in Wahrheit der verlorene HasSecondHeart-Stat; dafuer ist
    // ForceModifier zustaendig, nicht das Entfernen dieses Effekts.
    GameInstance.GetNetworkGameSystem().playerActionTracker.OnPlayerHealthChanged(health, false);
}

@wrapMethod(PlayerPuppet)
protected cb func OnDetach() -> Bool {
    if IsDefined(this.choomlink_healthListener) {
        GameInstance.GetStatPoolsSystem(this.GetGame())
            .RequestUnregisteringListener(Cast<StatsObjectID>(this.GetEntityID()), gamedataStatPoolType.Health,
                                          this.choomlink_healthListener);
        this.choomlink_healthListener = null;
    }
    return wrappedMethod();
}

// OnDamageReceived (not OnHit) is where we read a relayed shot's outcome: it only fires once
// the damage system has fully processed the hit and the total is greater than zero
// (damageSystem.script:1309-1314). OnHit fires unconditionally, including for hits computed
// down to zero, and could not by itself distinguish "no hit arrived" from "hit arrived, damage
// suppressed" — that distinction (choomlink-2hum, 2026-08-03) is what proved the relay's
// geometry and targeting were already correct, and that the remaining bug was in damage
// computation, not in reaching the player at all.
@wrapMethod(ScriptedPuppet)
protected cb func OnDamageReceived(evt: ref<gameDamageReceivedEvent>) -> Bool {
    let result = wrappedMethod(evt);
    if this.IsPlayer() {
        // Hit-feedback (2026-08-08, moved here 2026-08-09): originally measured in the
        // DamageSystem.Process wrap by snapshotting the Health stat pool before/after
        // wrappedMethod. That snapshot was silently wrong -- the pool write is not synchronous
        // with Process returning, so "before" and "after" read the same value and
        // damageDealt came out <= 0 every single time, despite damage visibly landing (health
        // dropping in the OnPlayerHealthChanged log the whole time). Exact same class of bug as
        // the documented "blame the probe" lesson (attackComputed not populated yet at OnHit).
        //
        // OnDamageReceived is documented (see the comment on this wrap, above) to fire only
        // AFTER the damage system has fully processed the hit -- it is "the later point in the
        // same chain" that code 12 already relies on every session. evt.totalDamageReceived is
        // the finished, post-armor number; no snapshot needed. evt.hitEvent carries the same
        // gameHitEvent Process saw, so the instigator/headshot logic below is unchanged.
        let hitEvent = evt.hitEvent;
        let instigator = hitEvent.attackData.GetInstigator();
        let puppet = instigator as ScriptedPuppet;
        if IsDefined(puppet) && !instigator.IsPlayer() && puppet.choomlink_networkedIdSet
            && evt.totalDamageReceived > 0.0 {
            // Not a flag read: vanilla's own headshot detection (damageSystem.script:400,
            // ProcessLocalizedDamage) returns BEFORE setting hitFlag.Headshot whenever the
            // instigator is not a player -- and ours never is, from the victim's point of view
            // (the remote puppet is an NPC). hitFlag.Headshot would simply never be set for any
            // of our relayed shots. Replicated here instead, from the same hit-shape data
            // (:414-421), deliberately WITHOUT that player-instigator gate.
            let isHeadshot = false;
            let hitShapes: array<HitShapeData> = hitEvent.hitRepresentationResult.hitShapes;
            if ArraySize(hitShapes) > 0 {
                let hitUserData = DamageSystemHelper.GetHitShapeUserDataBase(hitShapes[0]);
                if IsDefined(hitUserData) {
                    isHeadshot = HitShapeUserDataBase.IsHitReactionZoneHead(hitUserData);
                }
            }
            let statPools = GameInstance.GetStatPoolsSystem(this.GetGame());
            let isDead = statPools.HasStatPoolValueReachedMin(Cast<StatsObjectID>(this.GetEntityID()),
                                                              gamedataStatPoolType.Health);
            GameInstance.GetNetworkGameSystem().playerActionTracker
                .OnPlayerWasHit(puppet.choomlink_networkedEntityId, evt.totalDamageReceived, isHeadshot, isDead);
        }
    }
    return result;
}

// Schadenszahl eines relayten Schusses in die Vanilla-Pipeline einsetzen (choomlink-2hum).
//
// WARUM HIER UND NICHT AN DER WAFFE: auf dem Rechner des Opfers haengt die Waffe an einem
// NPC-Puppet und traegt keine ausgewuerfelten Stats — gemessen 2026-08-03, EffectiveDamagePerHit
// ist dort 0. Also stempelt `ModifyHitData` den Treffer mit hitFlag.DealNoDamage
// (damageSystem.script:308) und `Process` steigt sofort aus (:561). Jeder Schuss traf und
// rechnete sich zu null. Der Schuetze dagegen kennt die echte Zahl, es ist seine eigene Waffe;
// er schickt sie im EntityShoot-Paket mit.
//
// WAS DAS NICHT IST: eine erfundene Konstante. Wir setzen ausschliesslich den Waffenschaden des
// Schuetzen ein. Alles danach — Ruestung, Resistenzen, Schadensobergrenze, Trefferzone — rechnet
// weiterhin die Pipeline des OPFERS mit dessen eigenen Werten. Belegt am 2026-08-03: eingesetzte
// 20 kamen als 13,66 an. Die Hoheit ueber die eigene Gesundheit bleibt damit lokal, wie in der
// Spec festgelegt.
//
// Serverseitige Plausibilitaetspruefung (Obergrenze je Waffenklasse) ist der natuerliche
// naechste Schritt gegen manipulierte Schuetzen und passt ohne Protokollaenderung auf dieses Feld.
@wrapMethod(DamageSystem)
private final func Process(hitEvent: ref<gameHitEvent>, cache: ref<CacheData>) -> Void {
    let instigator = hitEvent.attackData.GetInstigator();
    let puppet = instigator as ScriptedPuppet;
    if IsDefined(hitEvent.target) && hitEvent.target.IsPlayer()
        && IsDefined(puppet) && !instigator.IsPlayer()
        && puppet.choomlink_threatRegistered
        && puppet.choomlink_lastShotDamage > 0.0
        && IsDefined(hitEvent.attackComputed) {
        hitEvent.attackData.RemoveFlag(hitFlag.DealNoDamage);
        hitEvent.attackComputed.SetAttackValue(puppet.choomlink_lastShotDamage,
                                               gamedataDamageType.Physical);
    }
    wrappedMethod(hitEvent, cache);
}

// Fires when the locomotion state machine actually enters the jump state — unlike the Jump
// button, this never false-positives (menus, blocked jumps).
@wrapMethod(JumpEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
    wrappedMethod(stateContext, scriptInterface);
    GameInstance.GetNetworkGameSystem().playerActionTracker.TrackJump();
}
