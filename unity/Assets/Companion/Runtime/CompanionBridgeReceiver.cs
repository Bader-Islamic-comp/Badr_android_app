using System.Text;
using UnityEngine;

namespace Companion.Presentation
{
    /// <summary>
    /// Platform adapter that carries sanitized events back to Flutter's
    /// `companion/unity_events` EventChannel. Implement it per platform and
    /// bind it on Unity's main thread before the room claims readiness.
    /// </summary>
    public interface IUnityEventTransport
    {
        /// <summary>Must report the real state; a hopeful `true` strands Flutter.</summary>
        bool IsConnected { get; }

        void Send(string json);
    }

    /// <summary>
    /// The Unity end of bridge v1.
    ///
    /// The native host forwards Flutter's `sendMessage` argument verbatim into
    /// <see cref="ReceiveMessage"/>. This component owns no credentials,
    /// networking, conversation state, rewards or persistence, and never logs
    /// payloads: a malformed envelope is dropped silently.
    ///
    /// Without an attached, connected transport it accepts nothing and claims
    /// no readiness, so Flutter keeps its static avatar.
    /// </summary>
    [DisallowMultipleComponent]
    public sealed class CompanionBridgeReceiver : MonoBehaviour
    {
        [SerializeField] private MonoBehaviour presentationBehaviour;

        private IAvatarPresentation presentation;
        private IUnityEventTransport transport;
        private BridgeSession session;
        private long outgoing;
        private bool announced;

        private void Awake()
        {
            EnsureSession();
        }

        /// <summary>
        /// Resolves the presentation and session on first need.
        ///
        /// Unity does not order `Awake` between components on one GameObject,
        /// so the transport's `Awake` may call <see cref="BindTransport"/>
        /// before this component's own `Awake` has run. Doing the wiring here
        /// rather than only in `Awake` removes that race — otherwise the room
        /// would silently never announce readiness.
        /// </summary>
        private bool EnsureSession()
        {
            if (session != null) return true;
            presentation = presentationBehaviour as IAvatarPresentation;
            if (presentation == null) return false;
            session = new BridgeSession(presentation);
            return true;
        }

        /// <summary>
        /// Attaches the platform transport. Readiness follows as soon as the
        /// room can actually perform, which may be this call or a later frame;
        /// the receiver repeats `unity.ready` after an accepted initialization.
        /// </summary>
        public bool BindTransport(IUnityEventTransport value)
        {
            if (value == null || !EnsureSession()) return false;
            transport = value;
            AnnounceReadiness();
            return true;
        }

        /// <summary>
        /// Readiness is the only unprompted event this room sends, and the host
        /// releases every held command the moment it arrives. Announcing it
        /// from `Awake` therefore raced the scene: the skin controller installs
        /// the visual in `Start`, so the first command landed while the
        /// presentation was still unavailable, came back `asset_unavailable`,
        /// and Flutter fell back to the static avatar for good — on every
        /// launch, with the room rendering perfectly behind it.
        ///
        /// So keep trying until the room can perform. A room whose assets never
        /// arrive simply never claims readiness, and Flutter's own deadline
        /// falls back, which is the outcome that was wanted anyway.
        /// </summary>
        private void Update()
        {
            if (announced) return;
            AnnounceReadiness();
        }

        /// <summary>Entry point for Unity native messaging. Never throws.</summary>
        public void ReceiveMessage(string envelope)
        {
            if (!EnsureSession() || transport == null || !transport.IsConnected) return;
            BridgeResult result = session.Receive(envelope);

            // Structurally valid state-changing requests are answered; anything
            // that failed to parse is dropped without a reply or a log line.
            if (result.NeedsAcknowledgement)
            {
                string messageId = AcknowledgedId(envelope);
                if (messageId != null) Emit("bridge.ack", Acknowledgement(messageId, result));
            }

            if (result.Accepted && session.Initialized && IsInitialize(envelope))
            {
                AnnounceReadiness();
            }

            if (!result.Accepted && result.Reason == BridgeSession.AssetUnavailable)
            {
                Emit("asset.failed", "{\"code\":\"asset_unavailable\"}");
            }
        }

        private void AnnounceReadiness()
        {
            // Cheap checks first: this runs every frame until it succeeds, and
            // asking the transport costs a JNI call on Android.
            if (session == null || presentation == null || !presentation.IsAvailable) return;
            if (transport == null || !transport.IsConnected) return;
            StringBuilder builder = new StringBuilder();
            builder.Append("{\"characterId\":\"robert\",\"capabilities\":[");
            string[] capabilities = session.Initialized
                ? session.Capabilities
                : InstalledCapabilities();
            for (int i = 0; i < capabilities.Length; i++)
            {
                if (i > 0) builder.Append(',');
                builder.Append('"').Append(capabilities[i]).Append('"');
            }
            builder.Append("]}");
            Emit("unity.ready", builder.ToString());
            announced = true;
        }

        private string[] InstalledCapabilities()
        {
            string[] installed = presentation.Capabilities;
            if (installed == null) return new string[0];
            // Report only contract capabilities, never an unrecognized name.
            int count = 0;
            for (int i = 0; i < installed.Length; i++)
            {
                if (BridgeCommand.IsSupportedType(installed[i])) count++;
            }
            string[] result = new string[count];
            int next = 0;
            for (int i = 0; i < installed.Length; i++)
            {
                if (BridgeCommand.IsSupportedType(installed[i])) result[next++] = installed[i];
            }
            return result;
        }

        private static bool IsInitialize(string envelope)
        {
            BridgeCommand command = BridgeCommand.Parse(envelope);
            return command != null && command.Type == BridgeCommand.Initialize;
        }

        private static string AcknowledgedId(string envelope)
        {
            BridgeCommand command = BridgeCommand.Parse(envelope);
            return command == null ? null : command.MessageId;
        }

        private static string Acknowledgement(string messageId, BridgeResult result)
        {
            StringBuilder builder = new StringBuilder();
            builder.Append("{\"ackMessageId\":\"").Append(messageId).Append("\",\"accepted\":");
            builder.Append(result.Accepted ? "true" : "false");
            builder.Append(",\"reason\":\"").Append(result.Reason).Append("\"}");
            return builder.ToString();
        }

        private void Emit(string type, string payload)
        {
            if (transport == null || !transport.IsConnected) return;
            StringBuilder builder = new StringBuilder();
            builder.Append("{\"schemaVersion\":1,\"messageId\":\"");
            builder.Append(System.Guid.NewGuid().ToString("D"));
            builder.Append("\",\"type\":\"").Append(type).Append("\",\"sequence\":");
            builder.Append(outgoing++);
            builder.Append(",\"payload\":").Append(payload).Append('}');
            transport.Send(builder.ToString());
        }
    }
}
