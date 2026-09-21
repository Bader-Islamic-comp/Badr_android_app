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
 * NOT COMPILED OR RUN. No Unity Editor, Android SDK or JDK was available. Every
 * reflective name below has to be confirmed against the actual export, and the
 * composition has to be validated on a device before this is relied upon.
 */
internal class UnityRuntime private constructor(private val player: Any) {

    val view: View?
        get() = invoke("getView") as? View

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

    private fun invoke(name: String): Any? = try {
        playerClass(player).getMethod(name).invoke(player)
    } catch (error: ReflectiveOperationException) {
        null
    }

    companion object {
        private const val PLAYER = "com.unity3d.player.UnityPlayer"

        private fun playerClass(player: Any): Class<*> = player.javaClass

        /** True when an exported Unity runtime is present in this build. */
        fun isAvailable(): Boolean = try {
            Class.forName(PLAYER)
            true
        } catch (error: ClassNotFoundException) {
            false
        }

        /**
         * Creates the runtime, or returns null when the export is absent or the
         * constructor fails. A failure here is ordinary: the caller reports no
         * room rather than crashing the learning experience.
         */
        fun createOrNull(activity: Activity): UnityRuntime? = try {
            val type = Class.forName(PLAYER)
            val player = type.getConstructor(Activity::class.java).newInstance(activity)
            UnityRuntime(player)
        } catch (error: ReflectiveOperationException) {
            null
        } catch (error: LinkageError) {
            // An export whose native library will not load is a missing room,
            // not a crash: the child keeps the static avatar and the lesson.
            null
        }
    }
}
