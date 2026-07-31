module Cyberverse.Network.Managers
import Codeware.*

public native class NetworkGameSystem extends IGameSystem {
    //public native func ConnectToServer(host: String, port: Uint16) -> Void;
    native let FullyConnected: Bool;
    native let playerActionTracker: ref<PlayerActionTracker>;
    public native func EnqueueLoadLastCheckpoint(handler: wref<inkISystemRequestsHandler>) -> Void;
    
    public func SpawnTransientEntity(entityName: TweakDBID, worldPosition: Vector4, worldOrientation: Quaternion) -> EntityID {
        let npcSpec = new DynamicEntitySpec();
        // AI-free custom puppet (phase 4b iteration 2): a real Character record (TweakXL,
        // client/assets/choomlink/choomlink.yaml) whose entityTemplatePath points to our
        // stripped puppet_base.ent. Record spawn keeps the engine-native population/teleport
        // machinery (raw templatePath spawns get a synthetic SpawnableObject record on which
        // TeleportationFacility.Teleport silently no-ops — measured, diag 2026-07-16), while
        // the template itself has no AI/move-writer components fighting the network anim feed.
        // entityName is intentionally unused for now — kept for a quick vanilla A/B fallback.
        // Stripped-template record (TweakXL, client/assets/choomlink/choomlink.yaml):
        // Character record inheriting Judy, entityTemplatePath → puppet_base.ent with
        // senses/reactions/combat stripped; AIHumanComponent + NPCStatesComponent + move
        // trio kept — the AI controller is the engine's only teleport executor (measured
        // 2026-07-16: TeleportationFacility no-ops on puppets, AITeleportCommand +
        // ForceTickNextFrame tracks at full speed).
        npcSpec.recordID = t"Character.choomlink_puppet";

        // Trust the server to properly track the entity state, because otherwise,
        // entities will just disappear for the client and never get back
        // (i.e. being invisible), as the server will only re-spawn them when
        // they have been properly despawned.
        npcSpec.alwaysSpawned = true;

        npcSpec.position = worldPosition;
        npcSpec.orientation = worldOrientation;
        npcSpec.persistState = false;
        npcSpec.persistSpawn = false;
        npcSpec.tags = [n"RED4ext"];

        return GameInstance.GetDynamicEntitySystem().CreateEntity(npcSpec);
    }

    public func DestroyTransientEntity(entityId: EntityID) {
        GameInstance.GetDynamicEntitySystem().DeleteEntity(entityId);
    }

    public func TeleportEntity(game: GameInstance, entity: ref<Entity>, position: Vector4, worldOrientation: EulerAngles) {
        // TODO: there is no SetWorldPosition.
        //let entity = GameInstance.GetDynamicEntitySystem().GetEntity(id);
        //let transform = .GetWorldTransform();
        // let worldPosition = WorldTransform.GetWorldPosition(transform);
        // WorldPosition.SetVector4(worldPosition, position);
        // WorldTransform.SetPosition(transform, position);

        // We need GameObjects, not pure Entites.
        //GameInstance.GetTeleportationFacility(game).Teleport(entity as GameObject, position, worldOrientation);
    }

    public func TeleportPuppet(puppet: ref<ScriptedPuppet>, position: Vector4, rotation: Float) -> ref<AICommand> {
        let teleportCommand = new AITeleportCommand();
        teleportCommand.position = position;
        teleportCommand.rotation = rotation;
        teleportCommand.doNavTest = false;

        puppet.GetAIControllerComponent().SendCommand(teleportCommand);
        puppet.GetAIControllerComponent().DisableCollider(); // TODO: Temp - In the future this should be controlled by the server, but currently Judy's just annoying :D 
        puppet.GetAIControllerComponent().ForceTickNextFrame();

        return teleportCommand;
    }

    public func StopAICommand(puppet: ref<ScriptedPuppet>, command: ref<AICommand>) {
        let component = puppet.GetAIControllerComponent();
        if (EnumInt(component.GetCommandState(command)) != EnumInt(AICommandState.Success)) {
            component.CancelCommand(command);
        }
    }

    // Non-puppets (vehicles, items) have no AI locomotion; plain teleport. Returns true if handled.
    public func TeleportIfNotPuppet(entity: ref<Entity>, position: Vector4, yaw: Float) -> Bool {
        let puppet = entity as ScriptedPuppet;
        if IsDefined(puppet) {
            return false;
        }
        let go = entity as GameObject;
        if IsDefined(go) {
            let angles: EulerAngles;
            angles.Yaw = yaw;
            GameInstance.GetTeleportationFacility(go.GetGame()).Teleport(go, position, angles);
        }
        return true;
    }

    // Applies an AnimFeature through the game's own helper (AnimationControllerComponent.
    // ApplyFeature) — the exact code path the base game uses for hit reactions, cover
    // stances and equips. The feature instance itself is built natively in C++ (the
    // locomotion feature classes are not script-exposed).
    public func ApplyAnimFeature(entity: ref<Entity>, inputName: CName, feature: ref<AnimFeature>) {
        let go = entity as GameObject;
        if !IsDefined(go) {
            return;
        }
        AnimationControllerComponent.ApplyFeature(go, inputName, feature);
    }

    // Fires a named external anim event on the puppet's graph (the trigger half of the
    // game's feature+event pattern: ApplyFeature carries the data, PushEvent fires the
    // state transition — the graph's transitions require both, composed simultaneously).
    public func PushPuppetEvent(entity: ref<Entity>, eventName: CName) {
        let go = entity as GameObject;
        if !IsDefined(go) {
            return;
        }
        AnimationControllerComponent.PushEvent(go, eventName);
    }

    // Kinematic per-frame move for remote puppets (AI-free locomotion, phase 4b): the C++
    // interpolation calls this every frame with the next position on the network path.
    // DIAG BISECT (temporary): facility teleports measurably no-op on puppets right now
    // (positions frozen, diag 2026-07-16) — route through the iteration-0 AI teleport
    // command instead to establish whether ANY mover works in the current engine state.
    // Works only on puppets with an AI controller (vanilla baseline), which is what the
    // bisect currently spawns.
    public func KinematicMove(entity: ref<Entity>, position: Vector4, yaw: Float) {
        let puppet = entity as ScriptedPuppet;
        if IsDefined(puppet) {
            let ctrl = puppet.GetAIControllerComponent();
            if IsDefined(ctrl) {
                let teleportCommand = new AITeleportCommand();
                teleportCommand.position = position;
                teleportCommand.rotation = yaw;
                teleportCommand.doNavTest = false;
                ctrl.SendCommand(teleportCommand);
                // Without this the command sits in the AI queue until the puppet's next
                // (LOD-throttled) AI tick — measured ~0.1 Hz effective, 2026-07-16. With it
                // the AI ticks this frame and the teleport lands at interpolation rate.
                ctrl.ForceTickNextFrame();
                return;
            }
        }
        let go = entity as GameObject;
        if !IsDefined(go) {
            return;
        }
        let angles: EulerAngles;
        angles.Yaw = yaw;
        GameInstance.GetTeleportationFacility(go.GetGame()).Teleport(go, position, angles);
    }

    // D1 locomotion-anim driver: full-body anims on remote puppets via the game's own
    // ActionAnimationScriptProxy — the AI-action machinery, instantiated by US (no AI
    // decision involved). Verified 2026-07-17: raw features/events never drive the NPC
    // graph, this proxy does. The C++ interpolation launches/loops/stops these.

    // Launches a full-body action anim; returns the proxy for status polling (null = failure).
    // Root motion stays OFF — translation belongs to the kinematic interpolation.
    // phase: EAIActionPhase as Int32 — 1 = Startup (one-shot, completes immediately),
    // 2 = Loop (runs for stateDuration; the walk driver uses this).
    public func StartActionAnim(entity: ref<Entity>, actionRecordId: TweakDBID, phase: Int32, duration: Float) -> ref<ActionAnimationScriptProxy> {
        let puppet = entity as ScriptedPuppet;
        if !IsDefined(puppet) {
            return null;
        }
        let record = TweakDBInterface.GetAIActionAnimDataRecord(actionRecordId);
        if !IsDefined(record) {
            return null;
        }
        let proxy = new ActionAnimationScriptProxy();
        proxy.Bind(puppet);
        let feature = new AnimFeature_AIAction();
        feature.state = phase;
        feature.stateDuration = duration;
        let slideParams: ActionAnimationSlideParams;
        if !proxy.Setup(record.AnimFeature(), feature, false, false, false, false, false, slideParams, null, 0.0) {
            return null;
        }
        proxy.Launch();
        return proxy;
    }

    // gameEActionStatus as Int32 (3 = STATUS_PROGRESS); used by C++ to detect clip end for
    // the walk loop relaunch.
    public func GetActionAnimStatus(proxy: ref<ActionAnimationScriptProxy>) -> Int32 {
        if !IsDefined(proxy) {
            return 0; // STATUS_INVALID
        }
        return EnumInt(proxy.GetStatus());
    }

    public func StopActionAnim(proxy: ref<ActionAnimationScriptProxy>) {
        if IsDefined(proxy) {
            proxy.Stop();
        }
    }

    // Relayed remote-player actions (EntityAction packet). Unknown actions are ignored on
    // purpose — forward compatibility for swim/climb/... in later phases.
    public func PuppetAction(entity: ref<Entity>, action: Uint32) {
        if !Equals(action, 0u) { // 0 = jump (EPlayerAction.ActionJump)
            return;
        }

        let puppet = entity as ScriptedPuppet;
        if !IsDefined(puppet) {
            return;
        }

        // Best effort: NPC anim graphs have no scriptable jump (no AI jump command exists in
        // the engine). Push the event anyway — harmless if the graph ignores it; the in-game
        // test decides whether phase 1 jump display needs a different approach.
        AnimationControllerComponent.PushEvent(puppet, n"Jump");
        FTLog(s"[ChoomLink] remote jump for puppet \(EntityID.GetHash(puppet.GetEntityID()))");
    }

    // Weapon sync (EquipItemEntity packet): equips/unequips the relayed item on the remote
    // puppet through the game's own NPC path — TransactionSystem GiveItem + AddItemToSlot,
    // exactly EquipSavedLoadoutTask (vanilla scriptedPuppet.script:358-372). The engine owns
    // mesh attachment, appearance and draw/holster from there. Slot comes from the packet:
    // cyberware arms are just a different slot/item id through the same code.
    public func ApplyEquipOnPuppet(entity: ref<Entity>, slot: TweakDBID, item: TweakDBID, isUnequipping: Bool) {
        let puppet = entity as ScriptedPuppet;
        if !IsDefined(puppet) {
            return;
        }
        let ts = GameInstance.GetTransactionSystem(puppet.GetGame());
        if isUnequipping {
            ts.RemoveItemFromSlot(puppet, slot, true);
            FTLog(s"[ChoomLink] remote unequip slot \(TDBID.ToStringDEBUG(slot))");
            return;
        }
        if !IsDefined(TweakDBInterface.GetItemRecord(item)) {
            // Unknown record (e.g. a modded item this observer lacks): puppet stays unarmed,
            // never crash (weapon sync spec §5).
            FTLog(s"[ChoomLink] unknown item record for remote equip, skipping");
            return;
        }
        let itemId = ItemID.FromTDBID(item);
        if !ts.HasItem(puppet, itemId) {
            ts.GiveItem(puppet, itemId, 1);
        }
        ts.AddItemToSlot(puppet, slot, itemId);
        FTLog(s"[ChoomLink] remote equip \(TDBID.ToStringDEBUG(item)) into \(TDBID.ToStringDEBUG(slot))");
    }

    // Aim target from the relayed yaw/pitch: eye-height point `dist` meters along the aim
    // direction. Yaw convention: 0 = +Y, CCW positive -> forward = (-sin, cos). VERIFY the
    // sign in-game (Task 8) — if the torso turns mirrored, flip the X sign here.
    private func AimTargetFor(puppet: ref<ScriptedPuppet>, yaw: Float, pitch: Float, dist: Float) -> Vector4 {
        let yawRad = Deg2Rad(yaw);
        let pitchRad = Deg2Rad(pitch);
        let dir = new Vector4(-SinF(yawRad) * CosF(pitchRad), CosF(yawRad) * CosF(pitchRad), SinF(pitchRad), 0.0);
        return puppet.GetWorldPosition() + dir * dist + new Vector4(0.0, 0.0, 1.55, 0.0);
    }

    // Weapon sync aim: drives the remote puppet's upper body toward the relayed aim point via
    // the engine's LookAt system — the recipe every NPC reaction uses (vanilla
    // reactionComponent.script:3558-3586, Chest weight = torso). Discrete re-adds on aim
    // change are fine: LookAt styles smooth the transition anim-side.
    public func ApplyAimOnPuppet(entity: ref<Entity>, yaw: Float, pitch: Float) {
        let puppet = entity as ScriptedPuppet;
        if !IsDefined(puppet) {
            return;
        }
        this.ClearAimOnPuppet(entity);
        let evt = new LookAtAddEvent();
        evt.SetStaticTarget(this.AimTargetFor(puppet, yaw, pitch, 20.0));
        evt.SetStyle(animLookAtStyle.Normal);
        evt.request.limits.softLimitDegrees = 360.0;
        evt.request.limits.hardLimitDegrees = 270.0;
        evt.request.limits.backLimitDegrees = 210.0;
        evt.request.limits.hardLimitDistance = GetLookAtLimitDistanceValue(animLookAtLimitDistanceType.None);
        evt.bodyPart = n"Eyes";
        let parts: array<LookAtPartRequest>;
        let part: LookAtPartRequest;
        part.partName = n"Head";
        part.weight = 0.30;
        part.suppress = 1.00;
        part.mode = 0;
        ArrayPush(parts, part);
        part.partName = n"Chest";
        part.weight = 2.00;
        part.suppress = 0.00;
        part.mode = 0;
        ArrayPush(parts, part);
        evt.SetAdditionalPartsArray(parts);
        puppet.QueueEvent(evt);
        puppet.choomlink_aimLookAt = evt;
    }

    // Weapon sync shots (EntityShoot packet): fires the remote puppet's drawn weapon through
    // AIWeapon.Fire — the exact call every NPC shot goes through (vanilla
    // tweakAISubActions.script:2459), no AI behavior context needed. Projectile/hitscan,
    // spread and muzzle effects are engine-owned from there.
    // timeStamp mirrors the AI caller's duration param; 0.0 = fire now. If nothing shows
    // in-game, second attempt: EngineTime.ToFloat(GameInstance.GetSimTime(...)).
    public func ApplyShootOnPuppet(entity: ref<Entity>, yaw: Float, pitch: Float, charge: Float) {
        let puppet = entity as ScriptedPuppet;
        if !IsDefined(puppet) {
            return;
        }
        let ts = GameInstance.GetTransactionSystem(puppet.GetGame());
        let weapon = ts.GetItemInSlot(puppet, t"AttachmentSlots.WeaponRight") as WeaponObject;
        if !IsDefined(weapon) {
            // Shot for an unarmed puppet (packet race with equip): drop, never crash (spec §5).
            return;
        }
        let target = this.AimTargetFor(puppet, yaw, pitch, 50.0);
        AIWeapon.Fire(puppet, weapon, 0.0, 1.0, gamedataTriggerMode.SemiAuto, target);
        FTLog(s"[ChoomLink] remote shot for puppet \(EntityID.GetHash(puppet.GetEntityID()))");
    }

    // Remote players must be shootable: the Judy-derived record is attitude-Friendly, which
    // engages the game's weapon-safe trigger lock when aiming at them (scriptedPuppet.script:
    // 3856 checks AIA_Friendly). Neutral keeps them non-hostile but a valid target.
    public func SetupPuppetAttitude(entity: ref<Entity>) {
        let puppet = entity as ScriptedPuppet;
        if !IsDefined(puppet) {
            return;
        }
        let agent = puppet.GetAttitudeAgent();
        if IsDefined(agent) {
            agent.SetAttitudeGroup(n"neutral");
        }
    }

    public func ClearAimOnPuppet(entity: ref<Entity>) {
        let puppet = entity as ScriptedPuppet;
        if !IsDefined(puppet) {
            return;
        }
        if IsDefined(puppet.choomlink_aimLookAt) {
            LookAtRemoveEvent.QueueRemoveLookatEvent(puppet, puppet.choomlink_aimLookAt);
            puppet.choomlink_aimLookAt = null;
        }
    }

}

// Per-puppet aim LookAt state (redscript has no map type; the puppet itself carries it).
@addField(ScriptedPuppet)
let choomlink_aimLookAt: ref<LookAtAddEvent>;

@addMethod(GameInstance)
public static native func GetNetworkGameSystem() -> ref<NetworkGameSystem>
