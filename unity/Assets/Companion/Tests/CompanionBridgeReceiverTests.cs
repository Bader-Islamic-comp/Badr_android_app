using System;
using System.Collections.Generic;
using System.Reflection;
using System.Text.RegularExpressions;
using NUnit.Framework;
using UnityEngine;

namespace Companion.Presentation.Tests
{
    /// <summary>
    /// EditMode coverage for the receiver's event emission and its guards.
    ///
    /// `BridgeSession`'s own decision table is exercised separately and without
    /// an engine by `unity/validation/Test-BridgeCore.ps1`. These tests cover
    /// what only the engine can: component wiring, transport binding, and the
    /// exact envelopes Flutter will have to validate.
    /// </summary>
    public sealed class CompanionBridgeReceiverTests
    {
        private sealed class FakeTransport : IUnityEventTransport
        {
            public bool Connected = true;
            public readonly List<string> Sent = new List<string>();
            public bool IsConnected { get { return Connected; } }
            public void Send(string json) { Sent.Add(json); }
        }

        private sealed class FakePresentation : MonoBehaviour, IAvatarPresentation
        {
            public bool Available = true;
            public string[] Installed = BridgeCommand.SupportedTypes;
            public readonly List<string> Applied = new List<string>();
            public bool IsAvailable { get { return Available; } }
            public string[] Capabilities { get { return Installed; } }
            public bool Apply(BridgeCommand command)
            {
                Applied.Add(command.Type);
                return true;
            }
        }

        private const string InitPayload =
            "{\"characterId\":\"robert\",\"capabilities\":[\"avatar.play\",\"app.pause\",\"app.resume\"]}";

        private static readonly Regex Envelope = new Regex(
            "^\\{\"schemaVersion\":1,\"messageId\":\"(?<id>[0-9a-fA-F-]{36})\"," +
            "\"type\":\"(?<type>[a-z.]+)\",\"sequence\":(?<sequence>\\d+),\"payload\":(?<payload>\\{.*\\})\\}$");

        private readonly List<GameObject> spawned = new List<GameObject>();

        [TearDown]
        public void TearDown()
        {
            foreach (GameObject go in spawned)
            {
                if (go != null) UnityEngine.Object.DestroyImmediate(go);
            }
            spawned.Clear();
        }

        // The receiver resolves its presentation in Awake, so the object is
        // built inactive and the serialized reference is set before it runs.
        private CompanionBridgeReceiver Build(out FakePresentation presentation)
        {
            GameObject go = new GameObject("CompanionBridge");
            spawned.Add(go);
            go.SetActive(false);
            presentation = go.AddComponent<FakePresentation>();
            CompanionBridgeReceiver receiver = go.AddComponent<CompanionBridgeReceiver>();
            FieldInfo field = typeof(CompanionBridgeReceiver).GetField(
                "presentationBehaviour", BindingFlags.NonPublic | BindingFlags.Instance);
            Assert.NotNull(field, "the serialized presentation field was renamed");
            field.SetValue(receiver, presentation);
            go.SetActive(true);
            return receiver;
        }

        private static string Message(string type, string payload, long sequence)
        {
            return "{\"schemaVersion\":1,\"messageId\":\"" + Guid.NewGuid().ToString("D") +
                   "\",\"type\":\"" + type + "\",\"sequence\":" + sequence +
                   ",\"payload\":" + payload + "}";
        }

        private static Match Parsed(string json)
        {
            Match match = Envelope.Match(json);
            Assert.IsTrue(match.Success, "emitted envelope does not match bridge v1: " + json);
            return match;
        }

        private static string TypeOf(string json) { return Parsed(json).Groups["type"].Value; }

        /// <summary>Drives one frame of the receiver's own polling.</summary>
        private static void Tick(CompanionBridgeReceiver receiver)
        {
            MethodInfo update = typeof(CompanionBridgeReceiver).GetMethod(
                "Update", BindingFlags.NonPublic | BindingFlags.Instance);
            Assert.NotNull(update, "the readiness poll was renamed");
            update.Invoke(receiver, null);
        }

        [Test]
        public void A_room_that_cannot_perform_yet_does_not_claim_readiness()
        {
            FakePresentation presentation;
            CompanionBridgeReceiver receiver = Build(out presentation);
            // The skin controller installs the visual in Start, so the room is
            // genuinely unavailable while every Awake is still running.
            presentation.Available = false;
            FakeTransport transport = new FakeTransport();

            Assert.IsTrue(receiver.BindTransport(transport));
            Assert.IsEmpty(transport.Sent,
                "readiness releases the host's held commands, so it must wait " +
                "for a room that can answer them");

            Tick(receiver);
            Assert.IsEmpty(transport.Sent);

            presentation.Available = true;
            Tick(receiver);
            Assert.AreEqual(1, transport.Sent.Count);
            Assert.AreEqual("unity.ready", TypeOf(transport.Sent[0]));

            // Announced once, not once per frame.
            Tick(receiver);
            Tick(receiver);
            Assert.AreEqual(1, transport.Sent.Count);
        }

        [Test]
        public void Binding_a_transport_announces_installed_capabilities()
        {
            FakePresentation presentation;
            CompanionBridgeReceiver receiver = Build(out presentation);
            presentation.Installed = new[] { "avatar.play", "app.pause" };
            FakeTransport transport = new FakeTransport();

            Assert.IsTrue(receiver.BindTransport(transport));

            Assert.AreEqual(1, transport.Sent.Count);
            Match ready = Parsed(transport.Sent[0]);
            Assert.AreEqual("unity.ready", ready.Groups["type"].Value);
            StringAssert.Contains("\"characterId\":\"robert\"", transport.Sent[0]);
            StringAssert.Contains("\"capabilities\":[\"avatar.play\",\"app.pause\"]", transport.Sent[0]);
        }

        [Test]
        public void An_unrecognised_installed_capability_is_never_announced()
        {
            FakePresentation presentation;
            CompanionBridgeReceiver receiver = Build(out presentation);
            presentation.Installed = new[] { "avatar.play", "avatar.breakdance" };
            FakeTransport transport = new FakeTransport();

            receiver.BindTransport(transport);

            StringAssert.Contains("\"capabilities\":[\"avatar.play\"]", transport.Sent[0]);
            StringAssert.DoesNotContain("breakdance", transport.Sent[0]);
        }

        [Test]
        public void Initialization_is_acknowledged_and_readiness_is_repeated()
        {
            FakePresentation presentation;
            CompanionBridgeReceiver receiver = Build(out presentation);
            FakeTransport transport = new FakeTransport();
            receiver.BindTransport(transport);

            receiver.ReceiveMessage(Message(BridgeCommand.Initialize, InitPayload, 0));

            Assert.AreEqual(3, transport.Sent.Count);
            Assert.AreEqual("bridge.ack", TypeOf(transport.Sent[1]));
            StringAssert.Contains("\"accepted\":true", transport.Sent[1]);
            StringAssert.Contains("\"reason\":\"ok\"", transport.Sent[1]);

            // Readiness now reports the negotiated intersection, not everything
            // the room could have done.
            Assert.AreEqual("unity.ready", TypeOf(transport.Sent[2]));
            StringAssert.Contains(
                "\"capabilities\":[\"avatar.play\",\"app.pause\",\"app.resume\"]", transport.Sent[2]);
            StringAssert.DoesNotContain("avatar.set_cosmetics", transport.Sent[2]);
            CollectionAssert.AreEqual(new[] { BridgeCommand.Initialize }, presentation.Applied);
        }

        [Test]
        public void The_acknowledgement_names_the_message_it_answers()
        {
            FakePresentation presentation;
            CompanionBridgeReceiver receiver = Build(out presentation);
            FakeTransport transport = new FakeTransport();
            receiver.BindTransport(transport);
            string envelope = Message(BridgeCommand.Initialize, InitPayload, 0);
            string sentId = Envelope.Match(envelope).Groups["id"].Value;

            receiver.ReceiveMessage(envelope);

            StringAssert.Contains("\"ackMessageId\":\"" + sentId + "\"", transport.Sent[1]);
        }

        [Test]
        public void Malformed_envelopes_are_dropped_without_a_reply()
        {
            FakePresentation presentation;
            CompanionBridgeReceiver receiver = Build(out presentation);
            FakeTransport transport = new FakeTransport();
            receiver.BindTransport(transport);
            int afterReady = transport.Sent.Count;

            foreach (string invalid in new[] {
                "", "{}", "not json",
                Message(BridgeCommand.Initialize, InitPayload, 0) + "{}",
                Message("avatar.play", "{\"animation\":\"Wave\",\"text\":\"private\"}", 0),
                Message("avatar.play", "{\"animation\":\"Dance\"}", 0),
                "{\"schemaVersion\":2,\"messageId\":\"" + Guid.NewGuid().ToString("D") +
                    "\",\"type\":\"app.pause\",\"sequence\":0,\"payload\":{}}"})
            {
                receiver.ReceiveMessage(invalid);
            }

            Assert.AreEqual(afterReady, transport.Sent.Count,
                "a malformed envelope must produce no event at all");
            CollectionAssert.IsEmpty(presentation.Applied);
        }

        [Test]
        public void Best_effort_cues_are_applied_without_an_acknowledgement()
        {
            FakePresentation presentation;
            CompanionBridgeReceiver receiver = Build(out presentation);
            FakeTransport transport = new FakeTransport();
            receiver.BindTransport(transport);
            receiver.ReceiveMessage(Message(BridgeCommand.Initialize, InitPayload, 0));
            int afterInit = transport.Sent.Count;

            receiver.ReceiveMessage(Message("avatar.play", "{\"animation\":\"Wave\"}", 1));
            receiver.ReceiveMessage(Message("app.pause", "{}", 2));

            Assert.AreEqual(afterInit, transport.Sent.Count,
                "animation and lifecycle cues are best effort");
            CollectionAssert.AreEqual(
                new[] { BridgeCommand.Initialize, "avatar.play", "app.pause" }, presentation.Applied);
        }

        [Test]
        public void A_refused_equipment_request_is_acknowledged_with_its_reason()
        {
            FakePresentation presentation;
            CompanionBridgeReceiver receiver = Build(out presentation);
            FakeTransport transport = new FakeTransport();
            receiver.BindTransport(transport);

            // Equipment before initialization: structurally valid, so Flutter is
            // waiting on an answer and must not be left to time out.
            receiver.ReceiveMessage(Message("avatar.set_cosmetics", "{\"cosmeticId\":\"default\"}", 0));

            Assert.AreEqual(2, transport.Sent.Count);
            Assert.AreEqual("bridge.ack", TypeOf(transport.Sent[1]));
            StringAssert.Contains("\"accepted\":false", transport.Sent[1]);
            StringAssert.Contains("\"reason\":\"not_initialized\"", transport.Sent[1]);
            CollectionAssert.IsEmpty(presentation.Applied);
        }

        [Test]
        public void Missing_presentation_assets_report_asset_failure()
        {
            FakePresentation presentation;
            CompanionBridgeReceiver receiver = Build(out presentation);
            FakeTransport transport = new FakeTransport();
            receiver.BindTransport(transport);
            presentation.Available = false;

            receiver.ReceiveMessage(Message(BridgeCommand.Initialize, InitPayload, 0));

            Assert.AreEqual(3, transport.Sent.Count);
            StringAssert.Contains("\"reason\":\"asset_unavailable\"", transport.Sent[1]);
            Assert.AreEqual("asset.failed", TypeOf(transport.Sent[2]));
            StringAssert.Contains("\"code\":\"asset_unavailable\"", transport.Sent[2]);
            CollectionAssert.IsEmpty(presentation.Applied);
        }

        [Test]
        public void Without_a_connected_transport_nothing_is_accepted()
        {
            FakePresentation presentation;
            CompanionBridgeReceiver unbound = Build(out presentation);

            // No transport at all: the room cannot answer, so it accepts nothing.
            unbound.ReceiveMessage(Message(BridgeCommand.Initialize, InitPayload, 0));
            CollectionAssert.IsEmpty(presentation.Applied);

            FakePresentation second;
            CompanionBridgeReceiver receiver = Build(out second);
            FakeTransport transport = new FakeTransport();
            transport.Connected = false;

            // A transport that reports itself disconnected claims no readiness.
            Assert.IsTrue(receiver.BindTransport(transport));
            CollectionAssert.IsEmpty(transport.Sent);

            receiver.ReceiveMessage(Message(BridgeCommand.Initialize, InitPayload, 0));
            CollectionAssert.IsEmpty(transport.Sent);
            CollectionAssert.IsEmpty(second.Applied);
        }

        [Test]
        public void A_receiver_without_a_presentation_binds_nothing()
        {
            GameObject go = new GameObject("CompanionBridge");
            spawned.Add(go);
            CompanionBridgeReceiver receiver = go.AddComponent<CompanionBridgeReceiver>();

            Assert.IsFalse(receiver.BindTransport(new FakeTransport()));
            Assert.IsFalse(receiver.BindTransport(null));
        }

        [Test]
        public void Emitted_sequences_increase_and_identifiers_are_unique()
        {
            FakePresentation presentation;
            CompanionBridgeReceiver receiver = Build(out presentation);
            FakeTransport transport = new FakeTransport();
            receiver.BindTransport(transport);
            receiver.ReceiveMessage(Message(BridgeCommand.Initialize, InitPayload, 0));
            receiver.ReceiveMessage(Message("avatar.set_cosmetics", "{\"cosmeticId\":\"default\"}", 1));

            long previous = -1;
            HashSet<string> identifiers = new HashSet<string>();
            foreach (string sent in transport.Sent)
            {
                Match match = Parsed(sent);
                long sequence = long.Parse(match.Groups["sequence"].Value);
                Assert.Greater(sequence, previous, "outgoing sequences must increase");
                previous = sequence;
                Assert.IsTrue(identifiers.Add(match.Groups["id"].Value), "message IDs must be unique");
            }
            Assert.AreEqual(4, transport.Sent.Count);
        }
    }
}
