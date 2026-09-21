using UnityEngine;

namespace Companion.Presentation
{
    /// <summary>
    /// Android transport: hands sanitized events to the Flutter host's static
    /// `CompanionEventBridge`, which forwards them to the
    /// `companion/unity_events` EventChannel.
    ///
    /// Attach this beside <see cref="CompanionBridgeReceiver"/> in the room. It
    /// reports connectivity from the host rather than assuming it, so a room
    /// whose host has detached claims no readiness and Flutter keeps its static
    /// avatar.
    ///
    /// NOT COMPILED OR RUN: no Unity Editor was available. The Java class and
    /// method names must be confirmed against the host before use.
    /// </summary>
    [DisallowMultipleComponent]
    [RequireComponent(typeof(CompanionBridgeReceiver))]
    public sealed class AndroidUnityEventTransport : MonoBehaviour, IUnityEventTransport
    {
        private const string HostClass = "dev.learningcompanion.companion_mobile.CompanionEventBridge";

#if UNITY_ANDROID && !UNITY_EDITOR
        private AndroidJavaClass host;
#endif

        private void Awake()
        {
#if UNITY_ANDROID && !UNITY_EDITOR
            try
            {
                host = new AndroidJavaClass(HostClass);
            }
            catch (AndroidJavaException)
            {
                host = null;
            }
#endif
            CompanionBridgeReceiver receiver = GetComponent<CompanionBridgeReceiver>();
            if (receiver != null) receiver.BindTransport(this);
        }

        public bool IsConnected
        {
            get
            {
#if UNITY_ANDROID && !UNITY_EDITOR
                if (host == null) return false;
                try
                {
                    return host.CallStatic<bool>("isConnected");
                }
                catch (AndroidJavaException)
                {
                    return false;
                }
#else
                // In the Editor there is no Flutter host to answer, so the room
                // must not claim it can reach one.
                return false;
#endif
            }
        }

        public void Send(string json)
        {
#if UNITY_ANDROID && !UNITY_EDITOR
            if (host == null) return;
            try
            {
                host.CallStatic("emit", json);
            }
            catch (AndroidJavaException)
            {
                // A detached host is an ordinary fallback, not an error to log.
            }
#endif
        }

        private void OnDestroy()
        {
#if UNITY_ANDROID && !UNITY_EDITOR
            if (host != null) host.Dispose();
            host = null;
#endif
        }
    }
}
