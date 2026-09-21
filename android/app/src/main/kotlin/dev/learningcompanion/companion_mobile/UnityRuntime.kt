package dev.learningcompanion.companion_mobile

import android.app.Activity
import android.view.View

/**
 * Reflective access to an exported Unity-as-a-Library runtime.
 *
 * The `unityLibrary` module is produced by a Unity Android export and is not
 * part of this repository. Binding to `com.unity3d.player.UnityPlayer` directly
 * would make every build depend on that export. Reflection keeps the app
 * buildable and runnable without it: [createOrNull] returns null, the bridge
 * reports no room, and Flutter keeps its static avatar.
 *
 * Unity permits only one runtime instance per process and retains a significant
 * memory footprint after unloading, so the host creates at most one and
 * recreates it only together with a fresh receiver.
 *
 * The reflective names are confirmed against a Unity 6000.3 export. The
 * composition itself still has to be validated on a real device.
 */
internal class UnityRuntime private constructor(private val player: Any) {

    /**
     * The view to add to the host hierarchy.
     *
     * `UnityPlayerActivity` uses `getFrameLayout()`, not `getView()`:
     * `getView()` returns the inner surface, which already sits inside that
     * frame layout and therefore cannot be re-parented.
     */
    val view: View?
        get() = (invoke("getFrameLayout") ?: invoke("getView")) as? View

    fun send(gameObject: String, method: String, payload: String) {
        playerClass(player)
            .getMethod("UnitySendMessage", String::class.java, String::class.java, String::class.java)
            .invoke(null, gameObject, method, payload)
    }

    fun pause() {
        invoke("pause")
    }

    fun resume() {
        invoke("resume")
    }

    fun destroy() {
        invoke("destroy")
    }

    // Unity-as-a-Library expects the host to forward the activity lifecycle.
    // Without onStart/onResume the player never begins rendering the scene, so
    // the receiver's Awake never runs and no handshake is possible.
    fun onStart() {
        invoke("onStart")
    }

    fun onResume() {
        invoke("onResume")
    }

    fun onPause() {
        invoke("onPause")
    }

    fun onStop() {
        invoke("onStop")
    }

    fun windowFocusChanged(hasFocus: Boolean) {
        try {
            playerClass(player)
                .getMethod("windowFocusChanged", Boolean::class.javaPrimitiveType)
                .invoke(player, hasFocus)
        } catch (error: ReflectiveOperationException) {
            // An export without this hook simply does not get focus updates.
        }
    }

    private fun invoke(name: String): Any? = try {
        playerClass(player).getMethod(name).invoke(player)
    } catch (error: ReflectiveOperationException) {
        null
    }

    companion object {
        /**
         * Candidate player classes, most recent first.
         *
         * Unity 6 made `UnityPlayer` abstract — its only constructor is
         * protected and takes an obfuscated internal type, and `getView()` is
         * abstract — and moved the concrete Activity-hosted player to
         * `UnityPlayerForActivityOrService`. Older exports only have
         * `UnityPlayer`, so both are tried.
         */
        private val PLAYERS = listOf(
            "com.unity3d.player.UnityPlayerForActivityOrService",
            "com.unity3d.player.UnityPlayer"
        )

        private fun playerClass(player: Any): Class<*> = player.javaClass

        private fun resolve(): Class<*>? = PLAYERS.firstNotNullOfOrNull { name ->
            try {
                val type = Class.forName(name)
                // An abstract base is not something this host can instantiate.
                if (java.lang.reflect.Modifier.isAbstract(type.modifiers)) null else type
            } catch (error: ClassNotFoundException) {
                null
            }
        }

        /** True when an instantiable Unity runtime is present in this build. */
        fun isAvailable(): Boolean = resolve() != null

        /**
         * Creates the runtime, or returns null when the export is absent or the
         * constructor fails. A failure here is ordinary: the caller reports no
         * room rather than crashing the learning experience.
         */
        fun createOrNull(activity: Activity): UnityRuntime? = try {
            val type = resolve()
            // The constructor's declared parameter has varied across Unity
            // versions (Activity, Context, ContextWrapper), so match on what
            // the export actually declares rather than assuming one shape.
            val constructor = type?.constructors?.firstOrNull { candidate ->
                candidate.parameterTypes.size == 1 &&
                    candidate.parameterTypes[0].isAssignableFrom(activity.javaClass)
            }
            if (constructor == null) null
            else UnityRuntime(constructor.newInstance(activity))
        } catch (error: ReflectiveOperationException) {
            null
        } catch (error: LinkageError) {
            // An export whose native library will not load is a missing room,
            // not a crash: the child keeps the static avatar and the lesson.
            null
        }
    }
}
