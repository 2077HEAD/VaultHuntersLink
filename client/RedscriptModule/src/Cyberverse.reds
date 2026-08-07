import Cyberverse.Network.Managers.*
//import Codeware.*

@addField(DebugDataDef)
public let AutoContinueUsed: Bool;

@wrapMethod(SingleplayerMenuGameController)
protected cb func OnSavesForLoadReady(saves: array<String>) -> Bool {
	let res = wrappedMethod(saves);

    let handler = this.GetSystemRequestsHandler();
    if (!handler.IsPreGame()) {
        return res; // PreGame == MainMenu
    }

    // TODO: In case the connection is too slow, we miss this. What to do then? Should the DLL somehow check the saves and then LoadLastCheckpoint?
    //  technically, it could still hook this method. Or put hooking aside, we could call into it and even pass the SystemRequestsHandler.
	if this.m_savesCount > 0 && !GetAllBlackboardDefs().DebugData.AutoContinueUsed {
        let networkSystem = GameInstance.GetNetworkGameSystem();
        if (networkSystem.FullyConnected) {
		    handler.LoadLastCheckpoint(false);
        } else {
            networkSystem.EnqueueLoadLastCheckpoint(handler);
        }
	}
}

@wrapMethod(SingleplayerMenuGameController)
protected cb func OnUninitialize() -> Bool {
	wrappedMethod();
	GetAllBlackboardDefs().DebugData.AutoContinueUsed = true;
}

@wrapMethod(SingleplayerMenuGameController)
private func PopulateMenuItemList() -> Void {
    wrappedMethod();
    this.AddMenuItem("Server-Browser", n"OnBuyGame");
}

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
                GameInstance.GetNetworkGameSystem().playerActionTracker.LogDiag(25, newValue);
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
        // 26 = Stat VOR unserem Zugriff. Ohne diesen Wert laesst sich nicht unterscheiden,
        // ob der Stat von uns kommt oder aus einer getragenen Zweitherz-Cyberware — genau
        // diese Verwechslung hat am 2026-08-07 drei Testlaeufe wertlos gemacht.
        let before = stats.GetStatValue(objId, gamedataStatType.HasSecondHeart);
        GameInstance.GetNetworkGameSystem().playerActionTracker.LogDiag(26, before);
        if before <= 0.0 {
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
        // Gemessen statt angenommen: ob der Stat wirklich anliegt, entscheidet ueber den
        // gesamten Respawn-Pfad, und ein Modifier auf einem berechneten Stat koennte
        // wirkungslos verpuffen. 20 = Stat-Wert nach dem Setzen.
        GameInstance.GetNetworkGameSystem().playerActionTracker
            .LogDiag(20, stats.GetStatValue(objId, gamedataStatType.HasSecondHeart));
    }
}

// Todesmeldung. Sitzt am Zustandsautomaten statt an der Gesundheitszahl, weil die mit
// Zweitherz nie 0 erreicht. 21 = Tod betreten.
@wrapMethod(DeathEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
    let tracker = GameInstance.GetNetworkGameSystem().playerActionTracker;
    // Beide Stats, die SetIsResurrectionAllowedBasedOnState abfragt (:172-173), im Moment des
    // Todes. Beim zweiten Tod sechs Sekunden nach dem ersten kam am 2026-08-07 wieder das
    // Todesmenue — welches der beiden Tore zufiel, ist ohne Messung nicht zu unterscheiden,
    // und der Statuseffekt SecondHeart taucht in diesem Tor ueberhaupt nicht auf.
    //   21 = HasSecondHeart, 24 = ForcePreventResurrect
    let stats = GameInstance.GetStatsSystem(scriptInterface.owner.GetGame());
    let objId = Cast<StatsObjectID>(scriptInterface.ownerEntityID);
    tracker.LogDiag(21, stats.GetStatValue(objId, gamedataStatType.HasSecondHeart));
    tracker.LogDiag(24, stats.GetStatValue(objId, gamedataStatType.ForcePreventResurrect));

    // HIER wird der Stat bewusst NICHT mehr nachgezogen. Der Versuch steht dokumentiert,
    // weil sein Scheitern die eigentliche Regel zeigt: StatsSystem.AddModifier wirkt nicht
    // sofort. Am 2026-08-07 las die Sonde unmittelbar nach dem AddModifier immer noch 0
    // (code 20 = 0.00 im selben Logeintrag wie code 21 = 0.00). Ein Nachziehen im
    // Todesmoment kommt also grundsaetzlich zu spaet, unabhaengig von der Reihenfolge.
    // Das Auffrischen sitzt stattdessen im Gesundheits-Listener, wo Zeit dafuer ist.
    tracker.OnPlayerHealthChanged(0.0, true);
    wrappedMethod(stateContext, scriptInterface);
}

// Respawn-Meldung. 22 = Wiederbelebung durchlaufen, mit der Gesundheit danach als Wert —
// das ist der Beleg, dass statt des Todesmenues die Wiederbelebung kam.
@wrapMethod(PlayerPuppet)
protected func OnResurrected() -> Void {
    wrappedMethod();
    let health = GameInstance.GetStatPoolsSystem(this.GetGame())
        .GetStatPoolValue(Cast<StatsObjectID>(this.GetEntityID()), gamedataStatPoolType.Health, true);
    GameInstance.GetNetworkGameSystem().playerActionTracker.LogDiag(22, health);

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
    //
    // 23 = Zweitherz-Stat nach der Wiederbelebung.
    GameInstance.GetNetworkGameSystem().playerActionTracker.LogDiag(23,
        GameInstance.GetStatsSystem(this.GetGame())
            .GetStatValue(Cast<StatsObjectID>(this.GetEntityID()), gamedataStatType.HasSecondHeart));
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

// DIAGNOSE (choomlink-2hum, 2026-08-03): erreicht ein relayter Schuss den Spieler ueberhaupt?
//
// Stand der Messungen: der Schuss ist vollstaendig korrekt aufgesetzt — gueltige Waffe im Slot,
// attached, eigener Ranged-Attack (shoot status 0), Threat registriert, Pose korrekt, Waffe
// erhoben und auf den Spieler gerichtet. Trotzdem faellt die Gesundheit nie.
//
// Damit ist die Frage binaer geworden: kommt gar kein Treffer an (Geometrie/Kollision), oder
// kommt einer an und der Schaden wird unterdrueckt? OnHit auf ScriptedPuppet ist der frueheste
// Punkt in der Vanilla-Kette (gameObject.script:984 -> ProcessDamagePipeline) und feuert
// unabhaengig davon, ob am Ende Schaden herauskommt. PlayerPuppet erbt ihn.
//
// MESSERGEBNIS 2026-08-03: code 10 feuert einmal pro Schuss, im Takt der Schusskadenz. Die
// Kugel ERREICHT den Spieler — Geometrie und Zielrichtung stimmen. Der Schaden bleibt trotzdem
// aus. Diese Sonde trennt jetzt die verbliebenen Erklaerungen:
//
//   10 = Treffer, value = Attitude zwischen Spieler und Angreifer
//        (EAIAttitude: 0 = Friendly, 1 = Neutral, 2 = Hostile).
//        Friendly ist der Verdaechtige: CheckForQuickExit stempelt in dem Fall
//        hitFlag.DealNoDamage (damageSystem.script:1832). Wir setzen zwar
//        SetAttitudeGroup(n"neutral"), aber dieser Gruppenname kommt im Vanilla-Dump NIRGENDS
//        vor — loest die CName nicht auf, bleibt die Judy-eigene, freundliche Gruppe stehen.
//   11 = value 1 wenn attackComputed an dieser Stelle bereits befuellt ist, sonst -1.
//        Wichtig, weil OnHit VOR der Berechnung liegt: die 0.00 aus dem ersten Durchlauf
//        koennte schlicht "noch nicht gerechnet" heissen statt "auf null gerechnet".
@wrapMethod(ScriptedPuppet)
protected cb func OnHit(evt: ref<gameHitEvent>) -> Bool {
    let result = wrappedMethod(evt);
    if this.IsPlayer() {
        let tracker = GameInstance.GetNetworkGameSystem().playerActionTracker;
        let instigator = evt.attackData.GetInstigator();
        let attitude: Int32 = -1;
        if IsDefined(instigator) {
            attitude = EnumInt(GameObject.GetAttitudeBetween(this, instigator));
        }
        tracker.LogDiag(10, Cast<Float>(attitude));
        tracker.LogDiag(11, IsDefined(evt.attackComputed) ? 1.0 : -1.0);
        // 13 = ist die Attack-Source gesetzt? Eine undefinierte Source laesst
        // CheckForQuickExit die gesamte Pipeline hart abbrechen
        // (damageSystem.script:1782-1815) — und sie ist ein anderes Feld als der Instigator,
        // der nachweislich gesetzt ist.
        tracker.LogDiag(13, IsDefined(evt.attackData.GetSource()) ? 1.0 : -1.0);
    }
    return result;
}

// Der spaetere Punkt in derselben Kette: OnDamageReceived wird nur gestellt, wenn der
// Gesamtschaden groesser null ist (damageSystem.script:1309-1314). Feuert code 12 nie, waehrend
// code 10 im Takt kommt, ist der Schaden nachweislich auf null gerechnet worden — und nicht
// etwa der Treffer ausgeblieben.
@wrapMethod(ScriptedPuppet)
protected cb func OnDamageReceived(evt: ref<gameDamageReceivedEvent>) -> Bool {
    let result = wrappedMethod(evt);
    if this.IsPlayer() {
        GameInstance.GetNetworkGameSystem().playerActionTracker.LogDiag(12, evt.totalDamageReceived);
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
        GameInstance.GetNetworkGameSystem().playerActionTracker
            .LogDiag(15, puppet.choomlink_lastShotDamage);
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
