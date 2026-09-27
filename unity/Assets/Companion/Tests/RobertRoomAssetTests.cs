using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using NUnit.Framework;
using RobertCharacter;
using UnityEditor;
using UnityEditor.Animations;
using UnityEngine;

namespace Companion.Presentation.Tests
{
    /// <summary>
    /// What the room builder generated, checked where it is used: the Animator
    /// the models share, each model's clip import settings, every skin's face
    /// player, the face frames' import settings and the scene's face lengths.
    ///
    /// These read the committed generated assets, so they describe the room
    /// as last built. Rebuild it (CompanionRoomBuilder.BuildRoomBatch) after
    /// changing the models, the faces or the builder, then run this suite.
    /// </summary>
    public sealed class RobertRoomAssetTests
    {
        private const string Generated = "Assets/Companion/Generated";
        private const string Controller = Generated + "/RobertBody.controller";
        private const string Scene = Generated + "/RobertRoom.unity";
        private const string Faces = "Assets/Companion/Character/Robert/Faces";
        private const string Manifest = Faces + "/animations.json";

        private static readonly string[] Skins =
        {
            "default", "casual", "cowboy", "astronaut", "arab-thobe", "explorer", "gardener"
        };

        private static readonly Dictionary<string, float> Seconds = new Dictionary<string, float>
        {
            { "Standing", 6f }, { "Idle", 6f }, { "Wave", 3.2f }, { "Talk", 4.8f }, { "Nod", 1.6f }, { "Celebrate", 2.4f }
        };

        private static string Model(string skin)
        {
            return skin == "default"
                ? "Assets/Companion/Character/Robert/Robert.fbx"
                : "Assets/Companion/Character/Skins/" + skin + "/Robert.fbx";
        }

        private static string ActionName(string clipName)
        {
            int separator = clipName.LastIndexOf('|');
            return separator >= 0 ? clipName.Substring(separator + 1) : clipName;
        }

        private sealed class FaceClip
        {
            public string Name;
            public bool Loop;
            public readonly List<string> Frames = new List<string>();
            public readonly List<float> Durations = new List<float>();
        }

        private static List<FaceClip> ReadManifest()
        {
            TextAsset text = AssetDatabase.LoadAssetAtPath<TextAsset>(Manifest);
            Assert.NotNull(text, "the face manifest is not staged at " + Manifest);
            JsonValue root = Json.Parse(text.text);
            Assert.NotNull(root, "the face manifest is not valid JSON");
            var result = new List<FaceClip>();
            foreach (KeyValuePair<string, JsonValue> entry in root.Members["clips"].Members)
            {
                FaceClip clip = new FaceClip { Name = entry.Key };
                JsonValue loop;
                clip.Loop = entry.Value.Members.TryGetValue("loop", out loop) && loop.Boolean;
                foreach (JsonValue frame in entry.Value.Members["frames"].Items)
                {
                    long milliseconds;
                    Assert.IsTrue(frame.Members["duration_ms"].TryInteger(out milliseconds));
                    clip.Frames.Add(Path.GetFileNameWithoutExtension(frame.Members["png"].Text));
                    clip.Durations.Add(milliseconds / 1000f);
                }
                result.Add(clip);
            }
            return result;
        }

        [Test]
        public void The_shared_Animator_rests_in_Standing_and_one_shots_return_to_it()
        {
            AnimatorController controller = AssetDatabase.LoadAssetAtPath<AnimatorController>(Controller);
            Assert.NotNull(controller, "no generated Animator at " + Controller);
            Assert.AreEqual(1, controller.layers.Length);
            AnimatorStateMachine machine = controller.layers[0].stateMachine;

            Assert.AreEqual("Standing", machine.defaultState.name);
            CollectionAssert.AreEquivalent(BridgeCommand.Animations, machine.states.Select(s => s.state.name).ToArray());
            CollectionAssert.IsEmpty(machine.anyStateTransitions);

            foreach (ChildAnimatorState child in machine.states)
            {
                AnimatorState state = child.state;
                AnimationClip clip = state.motion as AnimationClip;
                Assert.NotNull(clip, state.name + " has no clip");
                // The real imported clip, never the importer's Inspector preview copy.
                Assert.AreEqual("Robert_Rig|" + state.name, clip.name);
                Assert.AreEqual(Seconds[state.name], clip.length, 1f / 30f, state.name + " length");

                bool loop = AvatarPerformance.IsLoop(state.name);
                Assert.AreEqual(loop, clip.isLooping, state.name + " Loop Time");
                if (loop)
                {
                    CollectionAssert.IsEmpty(state.transitions, state.name + " loops until the next cue");
                    continue;
                }
                Assert.AreEqual(1, state.transitions.Length, state.name);
                AnimatorStateTransition back = state.transitions[0];
                Assert.AreEqual("Standing", back.destinationState.name, state.name + " returns to Standing");
                Assert.IsTrue(back.hasExitTime, state.name);
                Assert.AreEqual(1f, back.exitTime, 1e-6f, state.name + " returns at its end");
                Assert.IsTrue(back.hasFixedDuration, state.name);
                Assert.AreEqual(0.2f, back.duration, 1e-6f, state.name + " transition");
                CollectionAssert.IsEmpty(back.conditions, state.name);
            }
        }

        [Test]
        public void Every_model_imports_all_six_clips_with_the_right_loop_flags()
        {
            foreach (string skin in Skins)
            {
                string path = Model(skin);
                ModelImporter importer = AssetImporter.GetAtPath(path) as ModelImporter;
                Assert.NotNull(importer, "no model at " + path);
                Assert.AreEqual(ModelImporterAnimationType.Generic, importer.animationType, path);

                var takes = importer.clipAnimations.ToDictionary(c => ActionName(c.takeName), c => c);
                CollectionAssert.AreEquivalent(BridgeCommand.Animations, takes.Keys.ToArray(), path);
                foreach (string name in BridgeCommand.Animations)
                {
                    Assert.AreEqual(AvatarPerformance.IsLoop(name), takes[name].loopTime, path + " " + name);
                    Assert.IsFalse(takes[name].loopPose, path + " " + name);
                }

                var clips = AssetDatabase.LoadAllAssetsAtPath(path).OfType<AnimationClip>()
                    .Where(c => !c.name.StartsWith("__preview__", StringComparison.Ordinal))
                    .ToDictionary(c => ActionName(c.name), c => c);
                CollectionAssert.AreEquivalent(BridgeCommand.Animations, clips.Keys.ToArray(), path);
                foreach (string name in BridgeCommand.Animations)
                {
                    Assert.AreEqual(AvatarPerformance.IsLoop(name), clips[name].isLooping, path + " " + name);
                    Assert.AreEqual(Seconds[name], clips[name].length, 1f / 30f, path + " " + name);
                }
            }
        }

        /// <summary>
        /// The spine's resting sway is authored at 0.004 and 0.007 radians. At
        /// the importer's default 0.5 degree keyframe reduction it imported as
        /// a constant, so the resting loop barely moved.
        /// </summary>
        [Test]
        public void The_resting_sway_survives_import()
        {
            foreach (string skin in Skins)
            {
                ModelImporter importer = (ModelImporter)AssetImporter.GetAtPath(Model(skin));
                Assert.LessOrEqual(importer.animationRotationError, 0.05f, skin);
            }

            AnimationClip[] clips = AssetDatabase.LoadAllAssetsAtPath(Model("default")).OfType<AnimationClip>()
                .Where(c => !c.name.StartsWith("__preview__", StringComparison.Ordinal)).ToArray();
            foreach (string name in new[] { "Standing", "Idle", "Talk" })
            {
                AnimationClip clip = clips.Single(c => ActionName(c.name) == name);
                float widest = 0f;
                foreach (EditorCurveBinding binding in AnimationUtility.GetCurveBindings(clip))
                {
                    if (!binding.path.EndsWith("/spine", StringComparison.Ordinal) ||
                        !binding.propertyName.StartsWith("m_LocalRotation", StringComparison.Ordinal)) continue;
                    AnimationCurve curve = AnimationUtility.GetEditorCurve(clip, binding);
                    float min = float.MaxValue, max = float.MinValue;
                    for (int i = 0; i <= 360; i++)
                    {
                        float value = curve.Evaluate(clip.length * i / 360f);
                        min = Math.Min(min, value);
                        max = Math.Max(max, value);
                    }
                    widest = Math.Max(widest, max - min);
                }
                // A 0.007 radian sway swings a quaternion component by about 0.007.
                Assert.Greater(widest, 0.005f, name + " lost its spine sway on import");
            }
        }

        [Test]
        public void Every_skin_plays_every_manifest_face_with_its_timing()
        {
            List<FaceClip> manifest = ReadManifest();
            foreach (string skin in Skins)
            {
                string path = Generated + "/RobertSkin_" + skin + ".prefab";
                GameObject prefab = AssetDatabase.LoadAssetAtPath<GameObject>(path);
                Assert.NotNull(prefab, "no generated skin at " + path);

                Animator animator = prefab.GetComponentInChildren<Animator>(true);
                Assert.NotNull(animator, path);
                Assert.AreEqual(Controller, AssetDatabase.GetAssetPath(animator.runtimeAnimatorController),
                    path + " shares the Animator");
                Assert.IsFalse(animator.applyRootMotion, path);

                RobertFacePlayer[] players = prefab.GetComponentsInChildren<RobertFacePlayer>(true);
                Assert.AreEqual(1, players.Length, path);
                SerializedProperty clips = new SerializedObject(players[0]).FindProperty("clips");
                Assert.AreEqual(manifest.Count, clips.arraySize, path);
                for (int i = 0; i < clips.arraySize; i++)
                {
                    SerializedProperty clip = clips.GetArrayElementAtIndex(i);
                    FaceClip expected = manifest.Single(c => c.Name == clip.FindPropertyRelative("name").stringValue);
                    string label = path + " face " + expected.Name;
                    Assert.AreEqual(expected.Loop, clip.FindPropertyRelative("loop").boolValue, label);
                    SerializedProperty frames = clip.FindPropertyRelative("frames");
                    SerializedProperty durations = clip.FindPropertyRelative("frameDurations");
                    Assert.AreEqual(expected.Frames.Count, frames.arraySize, label);
                    Assert.AreEqual(expected.Frames.Count, durations.arraySize, label);
                    for (int f = 0; f < frames.arraySize; f++)
                    {
                        UnityEngine.Object frame = frames.GetArrayElementAtIndex(f).objectReferenceValue;
                        Assert.NotNull(frame, label + " frame " + f);
                        Assert.AreEqual(expected.Frames[f], frame.name, label + " frame " + f);
                        Assert.AreEqual(expected.Durations[f], durations.GetArrayElementAtIndex(f).floatValue, 1e-5f,
                            label + " frame " + f);
                    }
                }
            }
        }

        [Test]
        public void Every_cue_the_bridge_allows_has_its_face()
        {
            Dictionary<string, FaceClip> faces = ReadManifest().ToDictionary(c => c.Name, c => c);

            foreach (string animation in BridgeCommand.Animations)
            {
                string paired = AvatarPerformance.PairedFace(animation);
                Assert.IsTrue(faces.ContainsKey(paired), animation + " pairs with missing face " + paired);
            }
            Assert.IsTrue(faces["idle"].Loop, "idle blinks until something else plays");
            Assert.IsTrue(faces["talk"].Loop, "talk runs until the next body cue");
            Assert.IsFalse(faces["joy"].Loop);

            foreach (string emotion in BridgeCommand.Emotions)
            {
                if (emotion == "neutral") continue;
                Assert.IsTrue(faces.ContainsKey(emotion), "no face clip for emotion " + emotion);
                Assert.IsFalse(faces[emotion].Loop, emotion + " must be a one-shot");
            }
            // Lowercase face clips that are not emotions stay out of the allowlist.
            foreach (string clip in new[] { "idle", "talk", "blink" })
            {
                CollectionAssert.DoesNotContain(BridgeCommand.Emotions, clip);
            }
        }

        [Test]
        public void Face_frames_are_clamped_srgb_textures()
        {
            var names = new HashSet<string> { "neutral" };
            foreach (FaceClip clip in ReadManifest()) names.UnionWith(clip.Frames);
            foreach (string name in names)
            {
                string path = Faces + "/" + name + ".png";
                TextureImporter importer = AssetImporter.GetAtPath(path) as TextureImporter;
                Assert.NotNull(importer, "no face texture at " + path);
                Assert.AreEqual(TextureImporterType.Default, importer.textureType, path);
                Assert.IsTrue(importer.sRGBTexture, path);
                Assert.AreEqual(TextureWrapMode.Clamp, importer.wrapModeU, path);
                Assert.AreEqual(TextureWrapMode.Clamp, importer.wrapModeV, path);
            }
        }

        /// <summary>
        /// The presentation resumes blinking once a one-shot face has run its
        /// length, which it knows only from these serialized values.
        /// </summary>
        [Test]
        public void The_scene_knows_every_face_clips_length()
        {
            string scene = File.ReadAllText(Scene);
            StringAssert.Contains("faceCues:", scene);
            foreach (FaceClip clip in ReadManifest())
            {
                Match match = Regex.Match(scene,
                    @"- name: " + Regex.Escape(clip.Name) + @"\r?\n\s+seconds: ([0-9.eE+-]+)");
                Assert.IsTrue(match.Success, "the scene has no length for face " + clip.Name);
                float seconds = float.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture);
                Assert.AreEqual(clip.Durations.Sum(), seconds, 1e-3f, clip.Name);
            }
        }
    }
}
