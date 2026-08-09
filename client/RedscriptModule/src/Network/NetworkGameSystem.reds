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

    // Applies a remote player's health to their puppet (choomlink-2hum). Health is not a field:
    // it lives in the native StatPoolsSystem, keyed by a StatsObjectID cast of the EntityID
    // (vanilla player.script:5354-5358 Revive uses exactly this call).
    //
    // `perc` is passed explicitly on purpose. The flag decides the unit and the default is not
    // consistent across the vanilla call sites — omitting it is how you silently write 40 hit
    // points where you meant 40 percent.
    public func ApplyHealthOnPuppet(entity: ref<Entity>, healthPercent: Float, isDead: Bool) {
        let puppet = entity as ScriptedPuppet;
        if !IsDefined(puppet) {
            return;
        }
        let statsId = Cast<StatsObjectID>(puppet.GetEntityID());
        let pools = GameInstance.GetStatPoolsSystem(puppet.GetGame());

        if isDead {
            // Kill() is the canonical forced death (scriptedPuppet.script:1761-1770); it also runs
            // the death animation and ragdoll, which a bare stat-pool write to 0 would not.
            if !puppet.IsDead() {
                puppet.Kill(null, false, false);
            }
            return;
        }

        pools.RequestSettingStatPoolValue(statsId, gamedataStatPoolType.Health, healthPercent, null, true);
    }

    // Remote puppets must be able to actually die rather than drop to the "defeated" state.
    // NPCs with the defeat mechanic active carry a health custom limit of 10% instead of 0%
    // (NPCPuppet.script:687-696), so their health can never reach zero. For a player-controlled
    // puppet that would mean a killed player stays standing at 10% on every observer's screen.
    public func SetupPuppetMortality(entity: ref<Entity>) {
        let npc = entity as NPCPuppet;
        if !IsDefined(npc) {
            return;
        }
        npc.SetIsDefeatMechanicActive(false, false);
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
    // Returns a status code that the C++ caller logs (FTLog never reaches a file). The point is
    // to tell apart the remaining candidates for "shot fires but does no damage" without guessing:
    // Called once per puppet from the C++ side (eTeleportEntity, first resolution) -- see the
    // choomlink_networkedEntityId field comment for why this needs to be set at all.
    public func SetupPuppetNetworkId(entity: ref<Entity>, networkedEntityId: Uint64) {
        let puppet = entity as ScriptedPuppet;
        if !IsDefined(puppet) {
            return;
        }
        puppet.choomlink_networkedEntityId = networkedEntityId;
    }

    // Hit-feedback (2026-08-08): the shooter's own client never runs DamageSystem.Process for
    // its own shot (victim-authoritative model, choomlink-2hum), so this is the only place a
    // confirmed hit reaches the shooter's screen. Builds the same DamageInfo/KillInfo values
    // vanilla itself constructs (core/entity/gameObject.script:1116/1122 -- DisplayHitUI /
    // DisplayKillUI) and hands them to the native widget via PuppetBlackboardUpdater. No custom
    // UI: TargetHitIndicatorGameController already renders crosshair marker, sound, floating
    // damage number and kill confirmation off this same call, filtered to the actual instigator.
    //   0 = applied   1 = not a GameObject   2 = no local player
    public func ApplyHitConfirmedOnPuppet(entity: ref<Entity>, damageDealt: Float, isHeadshot: Bool,
                                          isDead: Bool) -> Int32 {
        let victim = entity as GameObject;
        if !IsDefined(victim) {
            return 1;
        }
        let localPlayer = GameInstance.GetPlayerSystem(entity.GetGame()).GetLocalPlayerMainGameObject();
        if !IsDefined(localPlayer) {
            return 2;
        }

        let info: DamageInfo;
        info.hitPosition = victim.GetWorldPosition();
        info.damageValue = damageDealt;
        info.damageType = gamedataDamageType.Physical;
        info.hitType = isHeadshot ? gameuiHitType.CriticalHit : gameuiHitType.Hit;
        info.entityHit = victim;
        info.instigator = localPlayer;
        info.userData = new DamageInfoUserData();
        if isHeadshot {
            let flag: SHitFlag;
            flag.flag = hitFlag.Headshot;
            flag.source = n"choomlink";
            ArrayPush(info.userData.flags, flag);
        }
        GameInstance.GetTargetingSystem(entity.GetGame()).GetPuppetBlackboardUpdater().AddDamageInfo(info);

        if isDead {
            let kill: KillInfo;
            kill.killerEntity = localPlayer;
            kill.victimEntity = victim;
            kill.killType = gameKillType.Normal;
            GameInstance.GetTargetingSystem(entity.GetGame()).GetPuppetBlackboardUpdater().AddKillInfo(kill);
        }
        return 0;
    }

    //   0 = fired, weapon carried its own ranged attack
    //   1 = fired, ranged attack derived from the weapon record as a fallback
    //   2 = fired WITHOUT any ranged attack -> the projectile carries no damage payload
    //   3 = no weapon in the slot   4 = not a puppet   5 = weapon not attached
    public func ApplyShootOnPuppet(entity: ref<Entity>, yaw: Float, pitch: Float, charge: Float,
                                   damagePerHit: Float, aimPoint: Vector4) -> Int32 {
        let puppet = entity as ScriptedPuppet;
        if !IsDefined(puppet) {
            return 4;
        }
        let ts = GameInstance.GetTransactionSystem(puppet.GetGame());
        let weapon = ts.GetItemInSlot(puppet, t"AttachmentSlots.WeaponRight") as WeaponObject;
        if !IsDefined(weapon) {
            // Shot for an unarmed puppet (packet race with equip): drop, never crash (spec §5).
            return 3;
        }
        // AIWeapon.Fire bails out silently on an unattached weapon (weapon.script:1491) — worth
        // distinguishing, because "equipped" and "attached" are not the same thing.
        if !weapon.IsAttached() {
            return 5;
        }
        // Schadenszahl des Schuetzen merken - der Wrap auf DamageSystem.Process holt sie sich
        // beim Treffer von hier ab.
        puppet.choomlink_lastShotDamage = damagePerHit;

        // Den vom Schuetzen gemeldeten Zielpunkt bevorzugen. Die Rekonstruktion aus yaw/pitch
        // daneben ist eine Naeherung, die systematisch danebengeht: der Punkt entsteht aus der
        // Koerpermitte des Puppets, die Kugel verlaesst aber die Muendung daneben, und die
        // Verbindung Muendung -> Fernpunkt laeuft damit parallel versetzt zur gemeinten Linie.
        // Rund 23 cm seitlich auf 3,7 m — gemeldet am 2026-08-07 als "manche Schuesse treffen,
        // manche nicht". Eine Richtung laesst sich nicht in einen Strahl zurueckverwandeln,
        // solange der Ursprung ein anderer ist; deshalb kommt der Punkt jetzt mit.
        //
        // Der Rueckfall bleibt fuer Schuetzen ohne Zielpunkt (Bots aelterer Staende, oder ein
        // Schuss ins Leere, bei dem der Strahl nichts trifft).
        let target = aimPoint;
        if Vector4.IsZero(aimPoint) {
            target = this.AimTargetFor(puppet, yaw, pitch, 50.0);
        }

        // Why no `target` argument (7th) even though we have the local player right here:
        //
        // Passing it hands the shot to TargetShootComponent, the game's deliberate-miss system
        // (weapon.script:1542-1546 -> targetShootComponent.script:47). That system enforces a
        // minimum TIME between hits on the player and computes an offset to miss with in between
        // (HandleMissed, :79-101). It is an anti-frustration mechanic for the single player, and
        // in PvP it would mean a timer on the victim's machine decides hits instead of the
        // shooter's aim. Two of its conditions would also block us permanently: Accuracy == 0 on
        // the shooter misses every shot (:288-290), and its visibility coefficient needs a
        // continuous line of sight accumulated by AI perception (:210-214), which an AI-free
        // puppet never builds. With target == null the whole block is skipped.
        //
        // The cost is that both AI_ShootAt branches then hinge on IsPositionValid
        // (weapon.script:1572-1584); failing it drops to AI_ShootForwards, which fires along the
        // weapon's own forward axis and ignores the aim point entirely -- visible shot, no hit.
        // That was the 2026-07-31 symptom. EnsureThreatRegistered is what satisfies it -- called
        // from the C++ side before this, so its status ends up in the readable log.

        // Explicit ranged attack: without it SetAttackBasedOnTimeDilation dereferences
        // weapon.GetCurrentRangedAttack() unguarded (weapon.script:1643). On a puppet whose weapon
        // no AI action ever touched that is null, and the projectile carries no damage payload.
        // The override is a RangedAttack_Record id (weapon.script:1635 feeds it to
        // GetRangedAttackRecord). Vanilla's own fallback chain is
        // GetCurrentRangedAttack().DefaultFire(); the static equivalent that does not depend on
        // any AI having touched the weapon is WeaponItem_Record.RangedAttacks().DefaultFire().
        let rangedAttack: TweakDBID;
        let status: Int32 = 0;
        if !IsDefined(weapon.GetCurrentRangedAttack()) {
            status = 2; // bis der Rückfall greift
            let weaponRecord = TweakDBInterface.GetWeaponItemRecord(ItemID.GetTDBID(weapon.GetItemID()));
            if IsDefined(weaponRecord) && IsDefined(weaponRecord.RangedAttacks())
                && IsDefined(weaponRecord.RangedAttacks().DefaultFire()) {
                rangedAttack = weaponRecord.RangedAttacks().DefaultFire().GetID();
                status = 1;
            }
        }

        AIWeapon.Fire(puppet, weapon, 0.0, 1.0, gamedataTriggerMode.SemiAuto, target, null, rangedAttack);
        return status;
    }

    // Puts the puppet into a combat/aiming animation state, or back to relaxed.
    //
    // Why this is likely the missing piece for damage (live finding 2026-08-03): the relayed shot
    // visibly went INTO THE GROUND while the puppet held its weapon low across the body. A shot
    // follows the weapon transform, and that comes from the animation pose. A vanilla NPC raises
    // its weapon because its behaviour tree drives these very NPC-state anim features; our
    // AI-free puppet has no behaviour tree, so nothing ever raises the weapon. The upper-body
    // LookAt we already apply turns head and chest, not the weapon axis.
    //
    // Recipe copied from the game's own npcStateComponent (UpdateUpperBodyState :603-606,
    // UpdateStanceState :932-935): build an AnimFeature_NPCState, put the enum's Int in `state`,
    // apply it under the graph's feature name. The feature names are the ones the puppet's graph
    // actually declares (`find-inputs` on the animgraph dump: highLevelState, upperBodyState,
    // stanceState).
    public func SetPuppetCombatPose(entity: ref<Entity>, aiming: Bool) {
        let go = entity as GameObject;
        if !IsDefined(go) {
            return;
        }

        let highLevel = new AnimFeature_NPCState();
        highLevel.state = aiming ? EnumInt(gamedataNPCHighLevelState.Combat)
                                 : EnumInt(gamedataNPCHighLevelState.Relaxed);
        AnimationControllerComponent.ApplyFeature(go, n"highLevelState", highLevel);

        let upperBody = new AnimFeature_NPCState();
        upperBody.state = aiming ? EnumInt(gamedataNPCUpperBodyState.Aim)
                                 : EnumInt(gamedataNPCUpperBodyState.Normal);
        AnimationControllerComponent.ApplyFeature(go, n"upperBodyState", upperBody);

        // Stand explicitly: the feature defaults to 0 (= Any), which is a wildcard for matching,
        // not a real stance, and leaves the graph without a concrete stance to blend from.
        let stance = new AnimFeature_NPCState();
        stance.state = EnumInt(gamedataNPCStanceState.Stand);
        AnimationControllerComponent.ApplyFeature(go, n"stanceState", stance);
    }

    // Makes the local player a known threat on the puppet's target tracker, once per puppet.
    //
    // This is not about AI behaviour -- the puppet has none. It is the prerequisite for
    // AIWeapon.Fire to take the AI_ShootAt branch: both of its guards call
    // TargetTrackerComponent.IsPositionValid, and a tracker with no threats rejects every
    // position, silently degrading the shot to AI_ShootForwards along the weapon's own axis.
    //
    // isPersistent = true so a single registration lasts; accuracy 1.0 and no cooldown because
    // nothing here should modulate whether a player's shot lands -- geometry decides that.
    // Returns a status code instead of logging: FTLog output only reaches the CET console window,
    // never a file, so a redscript-side log is invisible to an automated check. The caller on the
    // C++ side puts the code into the red4ext log, where a test run can actually read it.
    //   0 = already registered   1 = registered now
    //   2 = puppet has no target tracker   3 = no local player
    public func EnsureThreatRegistered(entity: ref<Entity>) -> Int32 {
        let puppet = entity as ScriptedPuppet;
        if !IsDefined(puppet) {
            return 4;
        }
        if puppet.choomlink_threatRegistered {
            return 0;
        }
        let tracker = puppet.GetTargetTrackerComponent();
        if !IsDefined(tracker) {
            return 2;
        }
        let player = GameInstance.GetPlayerSystem(puppet.GetGame()).GetLocalPlayerMainGameObject();
        if !IsDefined(player) {
            return 3;
        }
        tracker.AddThreat(player, true, player.GetWorldPosition(), 1.0, 0.0, true);
        // Adding a threat is not the same as it being active/believed. Vanilla drives these
        // separately (NPCPuppet.script:579 uses SetThreatBeliefAccuracy alongside persistence),
        // and IsPositionValid is about a position the tracker currently *believes in*, not merely
        // one it has heard of.
        tracker.ActivateThreat(player);
        tracker.SetThreatAccuracy(player, 1.0);
        tracker.SetThreatBeliefAccuracy(player, 1.0);
        puppet.choomlink_threatRegistered = true;
        return 1;
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

// One-shot guard for EnsureThreatRegistered — re-adding the same threat on every shot would
// churn the tracker at the weapon's fire rate.
@addField(ScriptedPuppet)
let choomlink_threatRegistered: Bool;

// Waffenschaden des letzten relayten Schusses dieses Puppets. Der Schuetze liest ihn auf seinem
// eigenen Rechner (dort hat die Waffe echte Stats) und schickt ihn mit; die Schadenspipeline des
// Opfers greift ihn beim Treffer ab. Siehe den DamageSystem.Process-Wrap in Cyberverse.reds.
@addField(ScriptedPuppet)
let choomlink_lastShotDamage: Float;

// The puppet's own networkedEntityId. redscript has no way to resolve this on its own (the
// mapping only exists forward, networkedEntityId -> engine entity, in C++) -- set once by
// SetupPuppetNetworkId above, the first time C++ resolves this puppet from a teleport packet.
@addField(ScriptedPuppet)
let choomlink_networkedEntityId: Uint64;

@addMethod(GameInstance)
public static native func GetNetworkGameSystem() -> ref<NetworkGameSystem>
