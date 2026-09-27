using System;
using System.Collections.Generic;
using NUnit.Framework;

namespace Companion.Presentation.Tests
{
    /// <summary>
    /// The body/face rules behind every presentation cue, against a recording
    /// rig. The real rig is the Animator and face player, which only run in a
    /// playing scene; these rules are what decides what they are told to do.
    /// </summary>
    public sealed class AvatarPerformanceTests
    {
        private sealed class FakeRig : IAvatarRig
        {
            public readonly List<string> Calls = new List<string>();
            public bool Resting = true;
            public bool Frozen;
            public string Body;
            public string Face;

            /// <summary>One-shot lengths as in the approved manifest; loops by one cycle.</summary>
            public readonly Dictionary<string, float> Seconds = new Dictionary<string, float>
            {
                { "idle", 4.49f }, { "talk", 4.8f }, { "blink", 0.22f },
                { "happy", 1f }, { "surprised", 0.8f }, { "joy", 1.1f }, { "giggle", 1.17f },
                { "wink", 0.95f }, { "curious", 1.1f }, { "wow", 1.2f }, { "sleepy", 1.3f },
                { "bashful", 1.1f }, { "starry", 1f }
            };

            public bool PlayBody(string state, bool crossfade)
            {
                if (Array.IndexOf(BridgeCommand.Animations, state) < 0) return false;
                Calls.Add((crossfade ? "fade:" : "cut:") + state);
                Body = state;
                return true;
            }

            public bool PlayFace(string clip)
            {
                if (!Seconds.ContainsKey(clip)) return false;
                Calls.Add("face:" + clip);
                Face = clip;
                return true;
            }

            public bool ShowNeutralFace()
            {
                Calls.Add("neutral");
                Face = "neutral";
                return true;
            }

            public void SetFrozen(bool frozen)
            {
                Calls.Add(frozen ? "freeze" : "thaw");
                Frozen = frozen;
            }

            public bool BodyResting { get { return Resting; } }

            public float FaceSeconds(string clip)
            {
                float seconds;
                return Seconds.TryGetValue(clip, out seconds) ? seconds : 0f;
            }
        }

        private FakeRig rig;
        private AvatarPerformance performance;

        [SetUp]
        public void SetUp()
        {
            rig = new FakeRig();
            performance = new AvatarPerformance();
        }

        private void Begin()
        {
            Assert.IsTrue(performance.Begin(rig));
            rig.Calls.Clear();
        }

        [Test]
        public void Initialization_rests_in_Standing_with_the_blinking_face()
        {
            Assert.IsTrue(performance.Begin(rig));

            CollectionAssert.AreEqual(new[] { "thaw", "cut:Standing", "face:idle" }, rig.Calls);
            Assert.AreEqual("Standing", performance.BodyLoop);
            Assert.AreEqual("idle", performance.FaceClip);
            Assert.IsFalse(performance.Paused);
        }

        [Test]
        public void Every_allowlisted_animation_pairs_with_a_face()
        {
            Assert.AreEqual("idle", AvatarPerformance.PairedFace("Standing"));
            Assert.AreEqual("idle", AvatarPerformance.PairedFace("Idle"));
            Assert.AreEqual("talk", AvatarPerformance.PairedFace("Talk"));
            Assert.AreEqual("joy", AvatarPerformance.PairedFace("Wave"));
            Assert.AreEqual("joy", AvatarPerformance.PairedFace("Celebrate"));
            Assert.AreEqual("idle", AvatarPerformance.PairedFace("Nod"));
            foreach (string animation in BridgeCommand.Animations)
            {
                Assert.IsNotNull(AvatarPerformance.PairedFace(animation), animation);
            }
            // Face clip names are not body cues, whatever their case.
            Assert.IsNull(AvatarPerformance.PairedFace("talk"));
            Assert.IsNull(AvatarPerformance.PairedFace("standing"));
        }

        [Test]
        public void Standing_Idle_and_Talk_loop_and_the_rest_are_one_shots()
        {
            CollectionAssert.AreEquivalent(
                new[] { "Standing", "Idle", "Talk" },
                Array.FindAll(BridgeCommand.Animations, AvatarPerformance.IsLoop));
            CollectionAssert.AreEquivalent(
                new[] { "Standing", "Idle" },
                Array.FindAll(BridgeCommand.Animations, AvatarPerformance.IsResting));
        }

        [Test]
        public void Talk_runs_the_mouth_cycle_until_Standing_ends_it()
        {
            Begin();

            Assert.IsTrue(performance.Play(rig, "Talk", 0));
            CollectionAssert.AreEqual(new[] { "fade:Talk", "face:talk" }, rig.Calls);
            Assert.AreEqual("Talk", performance.BodyLoop);

            // It keeps talking however long it runs.
            rig.Calls.Clear();
            rig.Resting = false;
            performance.Tick(rig, 60);
            CollectionAssert.IsEmpty(rig.Calls);

            rig.Resting = true;
            Assert.IsTrue(performance.Play(rig, "Standing", 61));
            CollectionAssert.AreEqual(new[] { "fade:Standing", "face:idle" }, rig.Calls);
            Assert.AreEqual("Standing", performance.BodyLoop);
            Assert.AreEqual("idle", performance.FaceClip);
        }

        [Test]
        public void Repeating_a_loop_that_is_playing_does_not_restart_it()
        {
            Begin();
            performance.Play(rig, "Talk", 0);
            rig.Calls.Clear();

            Assert.IsTrue(performance.Play(rig, "Talk", 1));
            Assert.IsTrue(performance.Play(rig, "Talk", 2));
            CollectionAssert.IsEmpty(rig.Calls);

            // Standing is already where Begin left the body, and blinking is on.
            AvatarPerformance resting = new AvatarPerformance();
            FakeRig other = new FakeRig();
            resting.Begin(other);
            other.Calls.Clear();
            Assert.IsTrue(resting.Play(other, "Standing", 0));
            CollectionAssert.IsEmpty(other.Calls);
        }

        [Test]
        public void Idle_is_a_resting_loop_with_the_blinking_face()
        {
            Begin();
            performance.Play(rig, "Talk", 0);
            rig.Calls.Clear();

            Assert.IsTrue(performance.Play(rig, "Idle", 1));
            CollectionAssert.AreEqual(new[] { "fade:Idle", "face:idle" }, rig.Calls);
            Assert.AreEqual("Idle", performance.BodyLoop);
        }

        [Test]
        public void Wave_and_Celebrate_show_joy_and_blinking_waits_for_the_body_to_rest()
        {
            foreach (string gesture in new[] { "Wave", "Celebrate" })
            {
                SetUp();
                Begin();

                Assert.IsTrue(performance.Play(rig, gesture, 10));
                CollectionAssert.AreEqual(new[] { "fade:" + gesture, "face:joy" }, rig.Calls, gesture);
                Assert.AreEqual("Standing", performance.BodyLoop, "one-shots return to Standing");

                // Joy lasts 1.1 s; the gesture lasts longer.
                rig.Calls.Clear();
                rig.Resting = false;
                performance.Tick(rig, 10.5);
                performance.Tick(rig, 11.2);
                CollectionAssert.IsEmpty(rig.Calls, "no blinking while the gesture is still playing");
                Assert.IsNull(performance.FaceClip, "the face player has returned to neutral");

                rig.Resting = true;
                performance.Tick(rig, 12.5);
                CollectionAssert.AreEqual(new[] { "face:idle" }, rig.Calls);

                // Once blinking, the per-frame check has nothing more to do.
                performance.Tick(rig, 13);
                performance.Tick(rig, 100);
                Assert.AreEqual(1, rig.Calls.Count);
            }
        }

        [Test]
        public void A_gesture_that_rests_before_its_face_ends_lets_the_face_finish()
        {
            Begin();
            performance.Play(rig, "Wave", 0);
            rig.Calls.Clear();

            // Resting, but joy is still showing: it is not cut short.
            performance.Tick(rig, 0.5);
            CollectionAssert.IsEmpty(rig.Calls);

            performance.Tick(rig, 1.2);
            CollectionAssert.AreEqual(new[] { "face:idle" }, rig.Calls);
        }

        [Test]
        public void Nod_leaves_the_blinking_face_alone()
        {
            Begin();

            Assert.IsTrue(performance.Play(rig, "Nod", 0));
            CollectionAssert.AreEqual(new[] { "fade:Nod" }, rig.Calls);
            Assert.AreEqual("idle", performance.FaceClip);
        }

        [Test]
        public void Nod_during_Talk_stops_the_mouth_cycle()
        {
            Begin();
            performance.Play(rig, "Talk", 0);
            rig.Calls.Clear();

            Assert.IsTrue(performance.Play(rig, "Nod", 1));
            CollectionAssert.AreEqual(new[] { "fade:Nod", "face:idle" }, rig.Calls);
            Assert.AreEqual("Standing", performance.BodyLoop);
        }

        [Test]
        public void Every_emotion_plays_once_and_blinking_resumes_while_resting()
        {
            foreach (string emotion in BridgeCommand.Emotions)
            {
                if (emotion == "neutral") continue;
                SetUp();
                Begin();

                Assert.IsTrue(performance.Emotion(rig, emotion, 100), emotion);
                CollectionAssert.AreEqual(new[] { "face:" + emotion }, rig.Calls, emotion);
                Assert.AreEqual(emotion, performance.FaceClip);

                rig.Calls.Clear();
                double ends = 100 + rig.Seconds[emotion];
                performance.Tick(rig, ends - 0.05);
                CollectionAssert.IsEmpty(rig.Calls, emotion + " is cut short");
                performance.Tick(rig, ends + 0.01);
                CollectionAssert.AreEqual(new[] { "face:idle" }, rig.Calls, emotion);
            }
        }

        [Test]
        public void An_emotion_during_Talk_interrupts_the_mouth_until_Standing()
        {
            Begin();
            performance.Play(rig, "Talk", 0);
            rig.Resting = false;
            rig.Calls.Clear();

            Assert.IsTrue(performance.Emotion(rig, "giggle", 1));
            CollectionAssert.AreEqual(new[] { "face:giggle" }, rig.Calls);

            // The body is still talking, so the face stays neutral afterwards.
            rig.Calls.Clear();
            performance.Tick(rig, 5);
            CollectionAssert.IsEmpty(rig.Calls);
            Assert.IsNull(performance.FaceClip);

            rig.Resting = true;
            performance.Play(rig, "Standing", 6);
            CollectionAssert.AreEqual(new[] { "fade:Standing", "face:idle" }, rig.Calls);
        }

        [Test]
        public void Returning_to_Standing_lets_a_running_expression_finish()
        {
            Begin();
            performance.Play(rig, "Talk", 0);
            performance.Play(rig, "Standing", 1);
            performance.Emotion(rig, "wink", 2);
            performance.Play(rig, "Wave", 2.1);
            rig.Calls.Clear();

            // Standing again while joy (from the wave) is still showing.
            Assert.IsTrue(performance.Play(rig, "Standing", 2.5));
            CollectionAssert.AreEqual(new[] { "fade:Standing" }, rig.Calls);
            Assert.AreEqual("joy", performance.FaceClip);

            performance.Tick(rig, 3.3);
            CollectionAssert.AreEqual(new[] { "fade:Standing", "face:idle" }, rig.Calls);
        }

        [Test]
        public void Neutral_shows_the_neutral_face_and_resumes_blinking()
        {
            Begin();
            performance.Emotion(rig, "happy", 0);
            rig.Calls.Clear();

            Assert.IsTrue(performance.Emotion(rig, "neutral", 0.2));
            CollectionAssert.AreEqual(new[] { "neutral", "face:idle" }, rig.Calls);
            Assert.AreEqual("idle", performance.FaceClip);
        }

        [Test]
        public void Neutral_while_moving_waits_for_rest_before_blinking()
        {
            Begin();
            performance.Play(rig, "Celebrate", 0);
            rig.Resting = false;
            rig.Calls.Clear();

            Assert.IsTrue(performance.Emotion(rig, "neutral", 0.1));
            CollectionAssert.AreEqual(new[] { "neutral" }, rig.Calls);

            performance.Tick(rig, 1);
            Assert.AreEqual(1, rig.Calls.Count);
            rig.Resting = true;
            performance.Tick(rig, 2.5);
            CollectionAssert.AreEqual(new[] { "neutral", "face:idle" }, rig.Calls);
        }

        [Test]
        public void Pause_freezes_everything_and_declines_cues()
        {
            Begin();
            performance.Play(rig, "Talk", 0);
            performance.Emotion(rig, "joy", 0.5);
            rig.Calls.Clear();

            Assert.IsTrue(performance.Pause(rig));
            CollectionAssert.AreEqual(new[] { "freeze" }, rig.Calls);
            Assert.IsTrue(performance.Paused);
            Assert.IsTrue(rig.Frozen);

            Assert.IsFalse(performance.Play(rig, "Wave", 1));
            Assert.IsFalse(performance.Emotion(rig, "joy", 1));
            Assert.IsFalse(performance.Emotion(rig, "neutral", 1));
            performance.Tick(rig, 30);
            CollectionAssert.AreEqual(new[] { "freeze" }, rig.Calls, "nothing moves while paused");
        }

        [Test]
        public void Resume_returns_to_Standing_and_the_blinking_face()
        {
            Begin();
            performance.Play(rig, "Talk", 0);
            performance.Pause(rig);
            rig.Calls.Clear();

            Assert.IsTrue(performance.Resume(rig));
            CollectionAssert.AreEqual(new[] { "thaw", "fade:Standing", "face:idle" }, rig.Calls);
            Assert.IsFalse(performance.Paused);
            Assert.IsFalse(rig.Frozen);
            Assert.AreEqual("Standing", performance.BodyLoop);
            Assert.AreEqual("idle", performance.FaceClip);
        }

        [Test]
        public void A_skin_swap_while_resting_restores_the_loop_and_blinking()
        {
            Begin();
            performance.Play(rig, "Idle", 0);
            performance.Emotion(rig, "curious", 0.1);
            rig.Calls.Clear();

            Assert.IsTrue(performance.Reapply(rig));
            CollectionAssert.AreEqual(new[] { "thaw", "cut:Idle", "face:idle" }, rig.Calls);
        }

        [Test]
        public void A_skin_swap_while_talking_keeps_talking()
        {
            Begin();
            performance.Play(rig, "Talk", 0);
            rig.Calls.Clear();

            Assert.IsTrue(performance.Reapply(rig));
            CollectionAssert.AreEqual(new[] { "thaw", "cut:Talk", "face:talk" }, rig.Calls);
            Assert.AreEqual("Talk", performance.BodyLoop);
        }

        [Test]
        public void A_skin_swap_mid_gesture_lands_where_the_gesture_would_have()
        {
            Begin();
            performance.Play(rig, "Wave", 0);
            rig.Calls.Clear();

            Assert.IsTrue(performance.Reapply(rig));
            CollectionAssert.AreEqual(new[] { "thaw", "cut:Standing", "face:idle" }, rig.Calls);
        }

        [Test]
        public void A_skin_swap_while_paused_stays_frozen_on_the_neutral_face()
        {
            Begin();
            performance.Play(rig, "Talk", 0);
            performance.Pause(rig);
            rig.Calls.Clear();

            Assert.IsTrue(performance.Reapply(rig));
            CollectionAssert.AreEqual(new[] { "cut:Standing", "neutral", "freeze" }, rig.Calls);
            Assert.IsTrue(performance.Paused);
            Assert.IsTrue(rig.Frozen);

            rig.Calls.Clear();
            Assert.IsTrue(performance.Resume(rig));
            CollectionAssert.AreEqual(new[] { "thaw", "fade:Standing", "face:idle" }, rig.Calls);
        }

        [Test]
        public void Unknown_bodies_and_faces_change_nothing()
        {
            Begin();

            Assert.IsFalse(performance.Play(rig, "Dance", 0));
            Assert.IsFalse(performance.Emotion(rig, "angry", 0));
            CollectionAssert.IsEmpty(rig.Calls);
            Assert.AreEqual("Standing", performance.BodyLoop);
            Assert.AreEqual("idle", performance.FaceClip);
        }
    }
}
