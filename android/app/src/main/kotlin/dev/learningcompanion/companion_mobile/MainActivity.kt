package dev.learningcompanion.companion_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine

/**
 * Hosts Flutter and, when a Unity export is present in the build, the character
 * room beneath it.
 *
 * The transparent background mode is requested only when an exported Unity
 * runtime exists, so builds without one keep the ordinary opaque surface. It
 * also needs a translucent window theme, which is why this is a device-gated
 * decision rather than a settled one — see `unity/README.md`.
 */
class MainActivity : FlutterActivity() {
    private var room: UnityRoomPlugin? = null

    override fun getBackgroundMode(): BackgroundMode =
        if (UnityRuntime.isAvailable()) BackgroundMode.transparent else super.getBackgroundMode()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        room = UnityRoomPlugin(this).also { it.attach(flutterEngine.dartExecutor.binaryMessenger) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        room?.detach()
        room = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onPause() {
        // Flutter also sends `app.pause` through the bridge; this stops the
        // player loop itself so a backgrounded room costs nothing.
        room?.pause()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        room?.resume()
    }
}
