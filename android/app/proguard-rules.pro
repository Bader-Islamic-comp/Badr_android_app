# The Unity receiver reaches its Android transport by name over JNI:
#   AndroidJavaClass("dev.learningcompanion.companion_mobile.CompanionEventBridge")
#     .CallStatic("emit", json)
# R8 has no way to see that reference, so without this rule it renames the class
# and its methods and the Unity-to-Flutter event path fails in release builds
# only — the debug build keeps working, which makes it easy to miss.
#
# Keep only this one class. Everything else, including UnityRoomPlugin and
# UnityRuntime, is reached from Kotlin and is safe to shrink and rename.
-keep class dev.learningcompanion.companion_mobile.CompanionEventBridge {
    public static *** emit(java.lang.String);
    public static boolean isConnected();
}
