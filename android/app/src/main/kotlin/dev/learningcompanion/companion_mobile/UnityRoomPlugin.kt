package dev.learningcompanion.companion_mobile

import android.os.Handler
import android.os.Looper
import com.unity3d.player.UnityPlayer
import com.unity3d.player.UnityPlayerForActivityOrService
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The native half of the presentation bridge.
 *
 * `companion/unity_commands` accepts three methods:
 *  - `sendMessage`: forwards one bridge v1 envelope verbatim into the Unity
 *    receiver's `ReceiveMessage`.
 *  - `openRoom`: reports whether a composited room exists.
 *  - `disposeRoom`: drops the bridge session so a later retry starts from clean
 *    sequence state on both sides.
 *
 * `companion/unity_events` streams the receiver's sanitized events back.
 *
 * Commands are held until the receiver proves it exists by emitting its first
 * event. Unity silently drops a message addressed to a GameObject the scene has
 * not created yet, so delivering earlier fails with no error anywhere.
 *
 * [MainActivity] owns the player's construction, compositing and lifecycle;
 * this only speaks the bridge. Nothing here logs an envelope: payloads are
 * presentation-only by contract, but a log sink is not the place to find out.
 */
internal class UnityRoomPlugin :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private val queued = ArrayDeque<String>()

    private var commands: MethodChannel? = null
    private var events: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var player: UnityPlayerForActivityOrService? = null
    private var receiverBound = false

    fun attach(messenger: BinaryMessenger) {
        commands = MethodChannel(messenger, COMMANDS).apply { setMethodCallHandler(this@UnityRoomPlugin) }
        events = EventChannel(messenger, EVENTS).apply { setStreamHandler(this@UnityRoomPlugin) }
        CompanionEventBridge.attach(::emit)
    }

    /** The activity created and composited the player. */
    fun onPlayerReady(value: UnityPlayerForActivityOrService) {
        player = value
    }

    fun detach() {
        CompanionEventBridge.detach()
        commands?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        commands = null
        events = null
        sink = null
        queued.clear()
        receiverBound = false
        player = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sendMessage" -> {
                val envelope = call.arguments as? String
                if (envelope == null || envelope.length > MAX_COMMAND) {
                    // Never echo the argument back into an error message.
                    result.error("invalid_argument", "A bridge envelope is required.", null)
                    return
                }
                if (!deliver(envelope)) {
                    result.error("no_room", "The character room is unavailable.", null)
                    return
                }
                result.success(null)
            }
            "openRoom" -> result.success(player != null)
            "disposeRoom" -> {
                // Unity permits one player per process and the activity owns it,
                // so a retry resets this bridge session rather than tearing the
                // runtime down underneath the activity.
                queued.clear()
                receiverBound = false
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        this.sink = sink
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun deliver(envelope: String): Boolean {
        if (player == null) return false
        if (!receiverBound) {
            if (queued.size >= MAX_QUEUED) return false
            queued.addLast(envelope)
            return true
        }
        return send(envelope)
    }

    private fun send(envelope: String): Boolean = try {
        UnityPlayer.UnitySendMessage(RECEIVER, METHOD, envelope)
        true
    } catch (error: RuntimeException) {
        false
    }

    private fun emit(json: String) {
        if (json.length > MAX_EVENT) return
        main.post {
            // The first event out of Unity proves the receiver exists and has
            // bound its transport, so anything held back can go now.
            if (!receiverBound) {
                receiverBound = true
                while (queued.isNotEmpty()) {
                    if (!send(queued.removeFirst())) break
                }
            }
            sink?.success(json)
        }
    }

    companion object {
        const val COMMANDS = "companion/unity_commands"
        const val EVENTS = "companion/unity_events"

        /** The receiver GameObject created by the room builder. */
        private const val RECEIVER = "CompanionBridge"
        private const val METHOD = "ReceiveMessage"

        /** Matches the receiver's own bound and Flutter's event bound. */
        private const val MAX_COMMAND = 4096
        private const val MAX_EVENT = 16384
        private const val MAX_QUEUED = 16
    }
}

/**
 * Static hand-off point for the Unity receiver's Android transport, which
 * reaches it with `AndroidJavaClass(...).CallStatic("emit", json)`.
 */
internal object CompanionEventBridge {
    private var sink: ((String) -> Unit)? = null

    fun attach(target: (String) -> Unit) {
        sink = target
    }

    fun detach() {
        sink = null
    }

    @JvmStatic
    fun emit(json: String) {
        sink?.invoke(json)
    }

    @JvmStatic
    fun isConnected(): Boolean = sink != null
}
