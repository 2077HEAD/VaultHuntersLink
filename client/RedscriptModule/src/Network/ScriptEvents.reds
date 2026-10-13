module Cyberverse.Network.Managers

// Vault Hunters co-op (2026-10-13): generic script events.
//
// A game mode (the Vault Hunters mod, or anything else) talks to the other players through
// these without the C++ client or the server knowing what the event means:
//
//   let evt = NetScriptEvent.Create(n"vh.class");
//   evt.u0 = 3l;
//   GameInstance.GetNetworkGameSystem().SendScriptEvent(evt);
//
// and receives them by registering a NetScriptEventListener subclass:
//
//   GameInstance.GetNetworkGameSystem().RegisterScriptEventListener(myListener);
//
// The server stamps `sender` with the sender's puppet id and relays to everyone else (target 0)
// or to one player (target = their puppet id). It also sends "vh.session" itself whenever the
// party changes: u0 = host puppet id, u1 = party size, u2 = YOUR puppet id,
// text = "id:name;id:name;..." in join order.
//
// Ids are Int32 and payload words Int64 because this game version's script RTTI cannot compare
// Uint64 values at all.
public class NetScriptEvent extends IScriptable {
    public let channel: CName;
    public let sender: Int32;   // filled in by the server; 0 = the server itself
    public let target: Int32;   // 0 = everyone else
    public let u0: Int64;
    public let u1: Int64;
    public let u2: Int64;
    public let f: array<Float>; // up to 8 values travel, the rest is dropped
    public let text: String;    // up to 127 bytes travel

    public static func Create(channel: CName) -> ref<NetScriptEvent> {
        let evt = new NetScriptEvent();
        evt.channel = channel;
        return evt;
    }

    public func F(index: Int32) -> Float {
        return index >= 0 && index < ArraySize(this.f) ? this.f[index] : 0.0;
    }
}

public abstract class NetScriptEventListener extends IScriptable {
    public func OnNetScriptEvent(evt: ref<NetScriptEvent>) -> Void {}
}

// The NetworkGameSystem side (listener registry, SendScriptEvent, SetAvatar, OnScriptEvent) lives
// inside the class body in NetworkGameSystem.reds: @addField/@addMethod on this native class from a
// separate file trips the compiler ("constant pool error: definition not found").
