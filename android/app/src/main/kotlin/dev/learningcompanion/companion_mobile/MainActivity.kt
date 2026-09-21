package dev.learningcompanion.companion_mobile

import android.content.res.Configuration
import android.os.Bundle
import android.view.ViewGroup
import android.widget.FrameLayout
import com.unity3d.player.IUnityPermissionRequestSupport
import com.unity3d.player.IUnityPlayerLifecycleEvents
import com.unity3d.player.IUnityPlayerSupport
import com.unity3d.player.PermissionRequest
import com.unity3d.player.UnityPlayerForActivityOrService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine

/**
 * Hosts Flutter with the Unity character room composited beneath it.
 *
 * Unity-as-a-Library cannot be driven from outside the activity. Its native
 * code resolves a field named `mUnityPlayer` on the current activity by name,
 * and the player expects its host to implement [IUnityPlayerSupport],
 * [IUnityPlayerLifecycleEvents] and [IUnityPermissionRequestSupport]. None of
 * that can be satisfied reflectively, so this activity implements the contract
 * directly and the app depends on the Unity export at compile time.
 *
 * `UnityPlayerActivity` in the export is the reference implementation. This
 * deliberately omits its input forwarding: Flutter owns every interactive
 * control, and the room is a presentation layer that receives only sanitized
 * bridge cues.
 */
class MainActivity :
    FlutterActivity(),
    IUnityPlayerLifecycleEvents,
    IUnityPermissionRequestSupport,
    IUnityPlayerSupport {

    // Do not rename: Unity's native code resolves this field by name.
    @JvmField
    protected var mUnityPlayer: UnityPlayerForActivityOrService? = null

    private var room: UnityRoomPlugin? = null
    private var surface: FrameLayout? = null

    /** Flutter must be transparent for the room behind it to be visible. */
    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // After super.onCreate, so Flutter's view already owns the content
        // frame and the room can be inserted underneath it.
        attachRoom()
    }

    private fun attachRoom() {
        if (mUnityPlayer != null) return
        val player = try {
            UnityPlayerForActivityOrService(this, this)
        } catch (error: RuntimeException) {
            // A room that will not start is a missing room, never a crash:
            // Flutter keeps its static avatar and the lesson continues.
            null
        } ?: return
        mUnityPlayer = player
        val content = findViewById<ViewGroup>(android.R.id.content) ?: return
        val holder = FrameLayout(this)
        holder.addView(
            player.frameLayout,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
        // Index 0 keeps the Flutter view, and every control on it, on top.
        content.addView(holder, 0)
        surface = holder
        room?.onPlayerReady(player)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = UnityRoomPlugin()
        plugin.attach(flutterEngine.dartExecutor.binaryMessenger)
        mUnityPlayer?.let(plugin::onPlayerReady)
        room = plugin
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        room?.detach()
        room = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun getUnityPlayerConnection(): UnityPlayerForActivityOrService? = mUnityPlayer

    override fun onUnityPlayerUnloaded() {
        // The room is a panel inside this app, not the app itself, so an
        // unloaded player must never send the learning session to the back.
    }

    override fun onUnityPlayerQuitted() {
        // Nothing to do: Flutter owns the session and falls back on its own.
    }

    override fun requestPermissions(request: PermissionRequest) {
        mUnityPlayer?.addPermissionRequest(request)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        mUnityPlayer?.permissionResponse(this, requestCode, permissions, grantResults)
    }

    override fun onStart() {
        super.onStart()
        mUnityPlayer?.onStart()
    }

    override fun onResume() {
        super.onResume()
        mUnityPlayer?.onResume()
        mUnityPlayer?.resume()
    }

    override fun onPause() {
        mUnityPlayer?.pause()
        mUnityPlayer?.onPause()
        super.onPause()
    }

    override fun onStop() {
        mUnityPlayer?.onStop()
        super.onStop()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        mUnityPlayer?.windowFocusChanged(hasFocus)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        mUnityPlayer?.configurationChanged(newConfig)
    }

    override fun onDestroy() {
        surface?.let { holder ->
            (holder.parent as? ViewGroup)?.removeView(holder)
            holder.removeAllViews()
        }
        surface = null
        mUnityPlayer?.destroy()
        mUnityPlayer = null
        super.onDestroy()
    }
}
