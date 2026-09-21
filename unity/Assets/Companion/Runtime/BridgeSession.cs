using System;
using System.Collections.Generic;

namespace Companion.Presentation
{
    /// <summary>
    /// The receiver's state machine for one loaded room.
    ///
    /// It is deliberately free of engine types so it can be compiled and
    /// exercised outside Unity. It owns capability negotiation, the replay
    /// cache, the sequence watermark and the decision to touch the presentation
    /// layer at all. A rejected command never mutates presentation and never
    /// advances the watermark, so the sender can reuse that sequence.
    ///
    /// Recreate the session together with the room for a fresh native session;
    /// reinitializing does not reset the watermark.
    /// </summary>
    public sealed class BridgeSession
    {
        /// <summary>Bounded so a long-lived room cannot grow without limit.</summary>
        public const int MaxReplays = 128;

        public const string Ok = "ok";
        public const string InvalidEnvelope = "invalid_envelope";
        public const string MessageIdConflict = "message_id_conflict";
        public const string StaleSequence = "stale_sequence";
        public const string AssetUnavailable = "asset_unavailable";
        public const string AlreadyInitialized = "already_initialized";
        public const string NotInitialized = "not_initialized";
        public const string UnsupportedCapability = "unsupported_capability";
        public const string PresentationRejected = "presentation_rejected";

        private sealed class Replay
        {
            public string Envelope;
            public BridgeResult Result;
        }

        private readonly IAvatarPresentation avatar;
        private readonly Dictionary<string, Replay> replays =
            new Dictionary<string, Replay>(StringComparer.Ordinal);
        private readonly Queue<string> order = new Queue<string>();
        private readonly List<string> negotiated = new List<string>();
        private bool initialized;
        private long watermark = -1;

        public BridgeSession(IAvatarPresentation avatar)
        {
            if (avatar == null) throw new ArgumentNullException("avatar");
            this.avatar = avatar;
        }

        /// <summary>True once an initialization has been accepted.</summary>
        public bool Initialized { get { return initialized; } }

        /// <summary>
        /// The intersection of requested and installed capabilities. This is
        /// what `unity.ready` reports, so the sender never learns about a
        /// capability this room cannot actually perform.
        /// </summary>
        public string[] Capabilities { get { return negotiated.ToArray(); } }

        public BridgeResult Receive(string envelope)
        {
            BridgeCommand command = BridgeCommand.Parse(envelope);
            if (command == null) return new BridgeResult(false, InvalidEnvelope, false);

            bool acknowledged = command.RequiresAcknowledgement;

            // The replay cache is consulted before the watermark so an exact
            // retry of an already accepted command returns its original outcome
            // instead of looking stale.
            Replay existing;
            if (replays.TryGetValue(command.MessageId, out existing))
            {
                if (!string.Equals(existing.Envelope, envelope, StringComparison.Ordinal))
                {
                    return new BridgeResult(false, MessageIdConflict, acknowledged);
                }
                return existing.Result;
            }

            if (command.Sequence <= watermark)
            {
                return new BridgeResult(false, StaleSequence, acknowledged);
            }

            bool initializing = command.Type == BridgeCommand.Initialize;
            if (initializing)
            {
                if (initialized) return new BridgeResult(false, AlreadyInitialized, acknowledged);
            }
            else
            {
                if (!initialized) return new BridgeResult(false, NotInitialized, acknowledged);
                if (!negotiated.Contains(command.Type))
                {
                    return new BridgeResult(false, UnsupportedCapability, acknowledged);
                }
            }

            if (!avatar.IsAvailable) return new BridgeResult(false, AssetUnavailable, acknowledged);

            List<string> intersection = null;
            if (initializing) intersection = Intersect(command.Capabilities, avatar.Capabilities);

            if (!avatar.Apply(command))
            {
                // A room that declines a cue is not a missing asset. Reporting
                // asset failure here would drop Flutter to the static avatar
                // for an ordinary paused frame.
                return new BridgeResult(false, PresentationRejected, acknowledged);
            }

            if (initializing)
            {
                initialized = true;
                negotiated.Clear();
                negotiated.AddRange(intersection);
            }
            watermark = command.Sequence;
            BridgeResult result = new BridgeResult(true, Ok, acknowledged);
            Remember(command.MessageId, envelope, result);
            return result;
        }

        private static List<string> Intersect(string[] requested, string[] installed)
        {
            List<string> result = new List<string>();
            if (requested == null || installed == null) return result;
            for (int i = 0; i < requested.Length; i++)
            {
                string capability = requested[i];
                if (!BridgeCommand.IsSupportedType(capability)) continue;
                if (Array.IndexOf(installed, capability) < 0) continue;
                if (result.Contains(capability)) continue;
                result.Add(capability);
            }
            return result;
        }

        // Only accepted commands are remembered: caching a rejection would let
        // a later legitimate retry inherit a stale failure.
        private void Remember(string messageId, string envelope, BridgeResult result)
        {
            Replay replay = new Replay();
            replay.Envelope = envelope;
            replay.Result = result;
            replays[messageId] = replay;
            order.Enqueue(messageId);
            while (order.Count > MaxReplays)
            {
                string evicted = order.Dequeue();
                // An evicted entry is still refused by the watermark.
                replays.Remove(evicted);
            }
        }
    }
}
