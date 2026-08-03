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
        GameInstance.GetNetworkGameSystem().playerActionTracker
            .OnPlayerShoot(weapon.GetItemID(), scriptInterface.executionOwner.GetWorldPosition());
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
    private let m_lastReported: Float = -1.0;

    public func SetPlayer(player: ref<PlayerPuppet>) -> Void {
        this.m_player = player;
    }

    public func OnStatPoolValueChanged(oldValue: Float, newValue: Float, percToPoints: Float) -> Void {
        if this.m_lastReported >= 0.0 && AbsF(newValue - this.m_lastReported) < 0.5 && newValue > 0.0 {
            return;
        }
        this.m_lastReported = newValue;
        let isDead = newValue <= 0.0;
        GameInstance.GetNetworkGameSystem().playerActionTracker.OnPlayerHealthChanged(newValue, isDead);
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
    return result;
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

// Fires when the locomotion state machine actually enters the jump state — unlike the Jump
// button, this never false-positives (menus, blocked jumps).
@wrapMethod(JumpEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
    wrappedMethod(stateContext, scriptInterface);
    GameInstance.GetNetworkGameSystem().playerActionTracker.TrackJump();
}
