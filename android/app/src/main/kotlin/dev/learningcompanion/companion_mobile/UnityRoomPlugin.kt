package dev.learningcompanion.companion_mobile

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.widget.FrameLayout
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
 *  - `openRoom`: ensures the full-screen Unity surface is composited beneath
 *    Flutter and running. Idempotent; [prepare] already attached it.
 *  - `disposeRoom`: destroys runtime and receiver together so a later retry
 *    starts from a clean sequence state on both sides.
 *
 * `companion/unity_events` streams the receiver's sanitized events back.
 *
 * The runtime is created, attached and started before `avatar.initialize` is
 * delivered, and commands are held until the receiver signals that it bound its
 * transport. The receiver must not see a command before its Awake has run,
 * because Unity drops a message to a GameObject that does not exist yet without
 * any error.
 *
 * Nothing here logs an envelope. Payloads are presentation-only by contract,
 * but a log sink is not a place to find that out.
 */
internal class UnityRoomPlugin(private val activity: Activity) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private val queued = ArrayDeque<String>()

    private var commands: MethodChannel? = null
    private var events: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var runtime: UnityRuntime? = null
    private var container: FrameLayout? = null
    private var receiverBound = false

    fun attach(messenger: BinaryMessenger) {
        commands = MethodChannel(messenger, COMMANDS).apply { setMethodCallHandler(this@UnityRoomPlugin) }
        events = EventChannel(messenger, EVENTS).apply { setStreamHandler(this@UnityRoomPlugin) }
        CompanionEventBridge.attach(::emit)
        prepare()
    }

    fun detach() {
        CompanionEventBridge.detach()
        commands?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        commands = null
        events = null
        sink = null
        teardown()
    }

    fun pause() = runtime?.pause()

    fun resume() = runtime?.resume()

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
            "openRoom" -> result.success(openRoom())
            "disposeRoom" -> {
                teardown()
                prepare()
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

    /**
     * Creates the runtime, attaches its surface and starts it.
     *
     * Attaching and resuming here rather than in [openRoom] is what makes the
     * handshake possible at all: the receiver binds its transport in `Awake`,
     * which only runs once Unity is actually playing the scene. Waiting for
     * `openRoom` would deadlock, because `openRoom` is itself only offered
     * after a successful handshake.
     */
    private fun prepare() {
        if (runtime != null) return
        val created = UnityRuntime.createOrNull(activity) ?: return
        runtime = created
        if (!attachSurface(created)) {
            // A room that cannot be composited is a missing room, not a reason
            // to lose the lesson. Drop it and let Flutter keep static Robert.
            teardown()
            return
        }
        created.resume()
    }

    /**
     * Commands wait until the receiver has actually bound its transport, which
     * it signals by emitting its first event. Delivering earlier would target a
     * GameObject the scene has not created yet, and Unity drops that silently.
     */
    private fun deliver(envelope: String): Boolean {
        val active = runtime ?: return false
        if (!receiverBound) {
            if (queued.size >= MAX_QUEUED) return false
            queued.addLast(envelope)
            return true
        }
        return try {
            active.send(RECEIVER, METHOD, envelope)
            true
        } catch (error: ReflectiveOperationException) {
            false
        }
    }

    private fun drainQueued() {
        val active = runtime ?: return
        while (queued.isNotEmpty()) {
            try {
                active.send(RECEIVER, METHOD, queued.removeFirst())
            } catch (error: ReflectiveOperationException) {
                return
            }
        }
    }

    /**
     * Composites Unity full screen beneath the Flutter view. Index 0 keeps the
     * Flutter view, and therefore every control, on top.
     */
    private fun attachSurface(active: UnityRuntime): Boolean {
        if (container != null) return true
        val surface = active.view ?: return false
        val content = activity.findViewById<ViewGroup>(android.R.id.content) ?: return false
        return try {
            // Unity 6 hands back a view that is already inside the player's own
            // layout, so it has to be detached before it can be re-parented.
            (surface.parent as? ViewGroup)?.removeView(surface)
            val holder = FrameLayout(activity)
            holder.addView(
                surface,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            )
            content.addView(holder, 0)
            container = holder
            true
        } catch (error: RuntimeException) {
            // Never let a compositing failure reach the activity: this app must
            // survive a broken room with its static avatar intact.
            container = null
            false
        }
    }

    /**
     * Idempotent: the surface is already attached by [prepare]. Input routing,
     * transparency, keyboard insets and accessibility over this composition all
     * still have to be proven on a real device.
     */
    private fun openRoom(): Boolean {
        val active = runtime ?: return false
        if (!attachSurface(active)) return false
        active.resume()
        return true
    }

    /**
     * Destroys the surface and the runtime. The receiver dies with them, which
     * is what makes a later retry safe: a reused receiver would keep its
     * sequence watermark and reject a fresh session's first commands.
     */
    private fun teardown() {
        queued.clear()
        receiverBound = false
        container?.let { holder ->
            (holder.parent as? ViewGroup)?.removeView(holder)
            holder.removeAllViews()
        }
        container = null
        runtime?.destroy()
        runtime = null
    }

    private fun emit(json: String) {
        if (json.length > MAX_EVENT) return
        main.post {
            // The first event out of Unity proves the receiver exists and has
            // bound its transport, so anything held back can go now.
            if (!receiverBound) {
                receiverBound = true
                drainQueued()
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
