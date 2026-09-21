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

        private void Awake()
        {
            presentation = presentationBehaviour as IAvatarPresentation;
            if (presentation == null) return;
            session = new BridgeSession(presentation);
        }

        /// <summary>
        /// Attaches the platform transport. Readiness is announced immediately
        /// so a host that binds before Flutter subscribes is not lost; the
        /// receiver repeats `unity.ready` after an accepted initialization.
        /// </summary>
        public bool BindTransport(IUnityEventTransport value)
        {
            if (value == null || session == null) return false;
            transport = value;
            AnnounceReadiness();
            return true;
        }

        /// <summary>Entry point for Unity native messaging. Never throws.</summary>
        public void ReceiveMessage(string envelope)
        {
            if (session == null || transport == null || !transport.IsConnected) return;
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
            if (transport == null || !transport.IsConnected || session == null) return;
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
