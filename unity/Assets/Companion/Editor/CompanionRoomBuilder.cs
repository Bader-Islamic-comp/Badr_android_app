using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using RobertCharacter;
using UnityEditor;
using UnityEditor.Animations;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace Companion.Presentation.Editor
{
    /// <summary>
    /// Builds the development character room from the staged canonical assets.
    ///
    /// Everything it creates lands under Assets/Companion/Generated so the
    /// canonical package stays authoritative and a rebuild never edits a
    /// hand-made file. It validates the model, rig and face manifest before
    /// touching anything, and refuses rather than fabricating a substitute.
    /// </summary>
    public static class CompanionRoomBuilder
    {
        private const string Model = "Assets/Companion/Character/Robert/Robert.fbx";
        private const string Faces = "Assets/Companion/Character/Robert/Faces";
        private const string Manifest = Faces + "/animations.json";
        private const string Generated = "Assets/Companion/Generated";
        private const string SkinAsset = Generated + "/RobertSkin_default.asset";
        private const string Backdrop = "Assets/Companion/Room/backdrop_desert.png";
        private const string BackdropMesh = Generated + "/RoomBackdrop.mesh";
        private const string BackdropMaterial = Generated + "/RoomBackdrop_Unlit.mat";
        private const string FaceMesh = "FaceScreen";
        private const string Rig = "Robert_Rig";
        private static readonly string[] BodyClips = { "Idle", "Wave", "Nod", "Celebrate" };

        /// <summary>
        /// Modelled outfits, by the cosmetic id the bridge and the service use.
        /// Each is a whole skin: the canonical package's `skins/{folder}` (a `_`
        /// in the folder name is written `-` here, because cosmetic ids are
        /// letters, digits and hyphens) exported to `Character/Skins/{id}/Robert.fbx`
        /// by tools/export_robert_fbx.py. Every one must carry the default rig
        /// exactly, so the default model's clips and Animator drive it unchanged.
        /// </summary>
        internal static readonly string[] Outfits =
        {
            "casual", "cowboy", "astronaut", "arab-thobe", "explorer", "gardener"
        };

        private static string OutfitModel(string id)
        {
            return "Assets/Companion/Character/Skins/" + id + "/Robert.fbx";
        }

        [MenuItem("Companion/Create Robert Development Room")]
        public static void BuildRoom()
        {
            string scenePath = Build();
            Debug.Log("Companion: created the development room at " + scenePath);
        }

        /// <summary>Batch entry point: fails the Editor run on any problem.</summary>
        public static void BuildRoomBatch()
        {
            try
            {
                string scenePath = Build();
                Console.WriteLine("ROOM_OK " + scenePath);
                EditorApplication.Exit(0);
            }
            catch (Exception error)
            {
                Console.WriteLine("ROOM_FAILED " + error.Message);
                EditorApplication.Exit(2);
            }
        }

        [MenuItem("Companion/Export Android Character Room")]
        public static void ExportAndroid()
        {
            Debug.Log("Companion: exported the character room to " + ExportProject(Build()));
        }

        /// <summary>Batch entry point: builds the room and exports it, or fails.</summary>
        public static void ExportAndroidBatch()
        {
            try
            {
                string output = ExportProject(Build());
                Console.WriteLine("EXPORT_OK " + output);
                EditorApplication.Exit(0);
            }
            catch (Exception error)
            {
                Console.WriteLine("EXPORT_FAILED " + error.Message);
                EditorApplication.Exit(2);
            }
        }

        /// <summary>
        /// Exports a Gradle `unityLibrary` module for the Flutter host to embed.
        ///
        /// This targets x86_64 only, which is what the development emulator
        /// runs. A physical phone needs ARM64, and a store build needs both
        /// plus its own signing — neither is configured here.
        /// </summary>
        private static string ExportProject(string scenePath)
        {
            string output = Path.GetFullPath(Path.Combine(Application.dataPath, "..", "export"));
            if (Directory.Exists(output)) Directory.Delete(output, true);
            Directory.CreateDirectory(output);

            PlayerSettings.SetApplicationIdentifier(
                NamedBuildTarget.Android, "dev.learningcompanion.companion_mobile");
            PlayerSettings.companyName = "Learning Companion";
            PlayerSettings.productName = "Robert Room";
            PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel24;
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.X86_64;
            PlayerSettings.SetScriptingBackend(NamedBuildTarget.Android, ScriptingImplementation.IL2CPP);
            // Unity 6 defaults to GameActivity, whose export ships only
            // `UnityPlayerGameActivity` — an Activity to launch, with no
            // embeddable `UnityPlayer` view. Unity-as-a-Library composition
            // needs the classic Activity entry point, which exports
            // `UnityPlayer` and `UnityPlayerActivity`.
            PlayerSettings.Android.applicationEntry = AndroidApplicationEntry.Activity;

            EditorUserBuildSettings.androidBuildSystem = AndroidBuildSystem.Gradle;
            EditorUserBuildSettings.exportAsGoogleAndroidProject = true;
            EditorUserBuildSettings.buildAppBundle = false;

            BuildPlayerOptions options = new BuildPlayerOptions
            {
                scenes = new[] { scenePath },
                locationPathName = output,
                target = BuildTarget.Android,
                options = BuildOptions.AcceptExternalModificationsToPlayer
            };
            BuildReport report = BuildPipeline.BuildPlayer(options);
            if (report.summary.result != BuildResult.Succeeded)
            {
                throw new InvalidOperationException(
                    "Android export finished as " + report.summary.result +
                    " with " + report.summary.totalErrors + " errors.");
            }
            return output;
        }

        private static string Build()
        {
            GameObject model = LoadModel(Model);

            Dictionary<string, AnimationClip> clips = LoadBodyClips();
            Texture2D neutral = LoadFace("neutral");
            Texture2D happy = LoadFace("happy");
            Texture2D surprised = LoadFace("surprised");

            Directory.CreateDirectory(Generated);
            AssetDatabase.Refresh();

            Material faceMaterial = CreateFaceMaterial(neutral);
            CreateBackdropAssets();
            AnimatorController controller = CreateAnimator(clips);
            Bounds framing;
            GameObject prefab = CreatePrefab(
                model, faceMaterial, controller, neutral, Generated + "/RobertSkin_default.prefab", out framing);
            RobertSkinDefinition skin = CreateSkinDefinition(prefab, neutral, "default", SkinAsset);
            string[] rig = RigNames(model);

            // Outfits share the face material, the Animator and the default
            // model's clips. The camera frames all of them, so a hat is never
            // cropped by whichever look happens to be worn.
            var outfits = new List<string>();
            foreach (string id in Outfits)
            {
                GameObject outfitModel = LoadModel(OutfitModel(id));
                string[] outfitRig = RigNames(outfitModel);
                if (!outfitRig.SequenceEqual(rig))
                {
                    throw new InvalidOperationException(
                        "Outfit '" + id + "' does not carry the default rig (" + outfitRig.Length + " vs " +
                        rig.Length + " transforms under " + Rig + "); its clips would not drive it.");
                }
                Bounds bounds;
                string asset = Generated + "/RobertSkin_" + id + ".asset";
                GameObject outfitPrefab = CreatePrefab(
                    outfitModel, faceMaterial, controller, neutral,
                    Generated + "/RobertSkin_" + id + ".prefab", out bounds);
                framing.Encapsulate(bounds);
                CreateSkinDefinition(outfitPrefab, neutral, id, asset);
                outfits.Add(asset);
            }
            string scenePath = CreateScene(skin, outfits, neutral, happy, surprised, framing);

            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();
            return scenePath;
        }

        /// <summary>
        /// Pins the backdrop's import settings. Clamped, because the quad shows
        /// a centre crop of the image and a repeating edge would mirror the
        /// picture back into frame on a wide screen.
        /// </summary>
        private static void ConfigureBackdropImporter()
        {
            TextureImporter importer = AssetImporter.GetAtPath(Backdrop) as TextureImporter;
            if (importer == null)
            {
                throw new InvalidOperationException(
                    "No backdrop image at " + Backdrop + ". Generate it with " +
                    "tools/make_backdrop.py.");
            }
            importer.textureType = TextureImporterType.Default;
            importer.wrapMode = TextureWrapMode.Clamp;
            importer.filterMode = FilterMode.Bilinear;
            importer.mipmapEnabled = true;
            importer.alphaSource = TextureImporterAlphaSource.None;
            importer.sRGBTexture = true;
            importer.maxTextureSize = 2048;
            importer.SaveAndReimport();
        }

        private static GameObject LoadModel(string path)
        {
            ConfigureModelImporter(path);
            GameObject model = AssetDatabase.LoadAssetAtPath<GameObject>(path);
            if (model == null)
            {
                throw new InvalidOperationException(
                    "No imported model at " + path + ". Regenerate it with " +
                    "tools/export_robert_fbx.py from the canonical Blender source.");
            }
            return model;
        }

        /// <summary>The rig's transform names in hierarchy order: what the clips bind to.</summary>
        private static string[] RigNames(GameObject model)
        {
            Transform rig = model.GetComponentsInChildren<Transform>(true).FirstOrDefault(t => t.name == Rig);
            if (rig == null) throw new InvalidOperationException(model.name + " has no " + Rig + ".");
            return rig.GetComponentsInChildren<Transform>(true).Select(t => t.name).ToArray();
        }

        /// <summary>
        /// Pins the import settings the rig contract depends on, rather than
        /// inheriting whatever default the Editor happened to apply.
        /// </summary>
        private static void ConfigureModelImporter(string path)
        {
            ModelImporter importer = AssetImporter.GetAtPath(path) as ModelImporter;
            if (importer == null)
            {
                throw new InvalidOperationException(
                    "No model importer for " + path + ". Is the file present and an FBX?");
            }
            importer.animationType = ModelImporterAnimationType.Generic;
            importer.avatarSetup = ModelImporterAvatarSetup.CreateFromThisModel;
            importer.importAnimation = true;
            importer.importConstraints = false;
            importer.importCameras = false;
            importer.importLights = false;
            importer.importBlendShapes = false;
            // A material is needed in slot 0 so the face renderer can be found;
            // the generated unlit material replaces it immediately after.
            importer.materialImportMode = ModelImporterMaterialImportMode.ImportStandard;
            importer.SaveAndReimport();
        }

        /// <summary>
        /// Blender exports one take per action, which Unity names
        /// `Armature|Action`. Match on the action, not the qualified take name.
        /// </summary>
        private static string ClipName(string name)
        {
            int separator = name.LastIndexOf('|');
            return separator >= 0 ? name.Substring(separator + 1) : name;
        }

        private static Dictionary<string, AnimationClip> LoadBodyClips()
        {
            var found = new Dictionary<string, AnimationClip>(StringComparer.OrdinalIgnoreCase);
            foreach (UnityEngine.Object asset in AssetDatabase.LoadAllAssetsAtPath(Model))
            {
                AnimationClip clip = asset as AnimationClip;
                if (clip == null) continue;
                string name = ClipName(clip.name);
                if (!found.ContainsKey(name)) found[name] = clip;
            }
            var missing = BodyClips.Where(name => !found.ContainsKey(name)).ToArray();
            if (missing.Length > 0)
            {
                throw new InvalidOperationException(
                    "The imported model is missing required clips: " + string.Join(", ", missing) +
                    ". Found: " + string.Join(", ", found.Keys.ToArray()));
            }
            return found;
        }

        private static Texture2D LoadFace(string name)
        {
            string path = Faces + "/" + name + ".png";
            Texture2D texture = AssetDatabase.LoadAssetAtPath<Texture2D>(path);
            if (texture == null) throw new InvalidOperationException("Missing face texture " + path);
            return texture;
        }

        private static Material CreateFaceMaterial(Texture2D neutral)
        {
            // The face is an opaque unlit screen; the render pipeline decides
            // which unlit shader exists, and an unknown pipeline is refused
            // rather than silently rendered with a lit shader.
            Shader shader = Shader.Find("Unlit/Texture") ?? Shader.Find("Universal Render Pipeline/Unlit");
            if (shader == null)
            {
                throw new InvalidOperationException(
                    "No unlit shader found. Add an explicit material adapter for this render pipeline.");
            }
            Material material = new Material(shader) { name = "FaceScreen_Unlit_Generated" };
            material.mainTexture = neutral;
            AssetDatabase.CreateAsset(material, Generated + "/FaceScreen_Unlit.mat");
            // CreateAsset makes this instance the asset. Reloading it by path
            // can return null within the same pass, which would wire a silent
            // null reference into everything downstream.
            return material;
        }

        private static AnimatorController CreateAnimator(Dictionary<string, AnimationClip> clips)
        {
            string path = Generated + "/RobertBody.controller";
            AnimatorController controller = AnimatorController.CreateAnimatorControllerAtPath(path);
            AnimatorStateMachine machine = controller.layers[0].stateMachine;

            AnimatorState idle = machine.AddState("Idle");
            idle.motion = clips["Idle"];
            machine.defaultState = idle;

            // One-shot reactions return to Idle on their own, which is what lets
            // bridge v1 stay free of an `animation.completed` event.
            foreach (string name in BodyClips.Where(c => c != "Idle"))
            {
                AnimatorState state = machine.AddState(name);
                state.motion = clips[name];
                AnimatorStateTransition transition = state.AddTransition(idle);
                transition.hasExitTime = true;
                transition.exitTime = 1f;
                transition.duration = 0.12f;
            }
            EditorUtility.SetDirty(controller);
            return controller;
        }

        private static GameObject CreatePrefab(
            GameObject model, Material faceMaterial, AnimatorController controller,
            Texture2D neutral, string path, out Bounds framing)
        {
            framing = new Bounds(Vector3.zero, Vector3.one);
            GameObject instance = (GameObject)PrefabUtility.InstantiatePrefab(model);
            try
            {
                // Unpack before wiring. Saved as a variant of the FBX, the
                // added components' references to base objects serialize as
                // bare local file IDs that do not exist in this asset, so they
                // resolve to null at runtime while looking correct in YAML.
                PrefabUtility.UnpackPrefabInstance(
                    instance, PrefabUnpackMode.Completely, InteractionMode.AutomatedAction);
                Renderer faceRenderer = FindFaceRenderer(instance);
                Material[] materials = faceRenderer.sharedMaterials;
                materials[0] = faceMaterial;
                faceRenderer.sharedMaterials = materials;

                Animator animator = instance.GetComponent<Animator>() ?? instance.AddComponent<Animator>();
                animator.runtimeAnimatorController = controller;
                animator.applyRootMotion = false;

                RobertFacePlayer player = instance.AddComponent<RobertFacePlayer>();
                ConfigureFacePlayer(player, faceRenderer, neutral);

                // Prove the binding the skin controller will demand at runtime,
                // so a broken face player fails the build instead of showing up
                // as "wire a valid default skin" on a device.
                if (!player.Rebind())
                {
                    throw new InvalidOperationException(
                        "The face player could not bind to '" + FaceMesh + "'. Its material " +
                        "must expose _BaseMap, _MainTex or _BaseColorTexture.");
                }
                if (!player.SetDefaultFace(neutral))
                {
                    throw new InvalidOperationException("The face player rejected the neutral face.");
                }

                framing = Measure(instance);

                GameObject saved = PrefabUtility.SaveAsPrefabAsset(instance, path);
                if (saved == null) throw new InvalidOperationException("Could not save the model prefab.");
                return saved;
            }
            finally
            {
                UnityEngine.Object.DestroyImmediate(instance);
            }
        }

        /// <summary>Combined renderer bounds, so the camera frames the real model.</summary>
        private static Bounds Measure(GameObject instance)
        {
            Renderer[] renderers = instance.GetComponentsInChildren<Renderer>(true);
            if (renderers.Length == 0) return new Bounds(Vector3.zero, Vector3.one);
            Bounds total = renderers[0].bounds;
            for (int i = 1; i < renderers.Length; i++) total.Encapsulate(renderers[i].bounds);
            return total;
        }

        private static Renderer FindFaceRenderer(GameObject instance)
        {
            foreach (Renderer renderer in instance.GetComponentsInChildren<Renderer>(true))
            {
                if (renderer.gameObject.name != FaceMesh) continue;
                if (renderer.sharedMaterials.Length == 0 || renderer.sharedMaterials[0] == null) continue;
                return renderer;
            }
            throw new InvalidOperationException(
                "The imported model has no '" + FaceMesh + "' renderer with a material in slot 0.");
        }

        // The approved manifest owns the timings; convert its milliseconds to the
        // seconds the player expects rather than restating them here.
        private static void ConfigureFacePlayer(
            RobertFacePlayer player, Renderer faceRenderer, Texture2D neutral)
        {
            SerializedObject serialized = new SerializedObject(player);
            serialized.FindProperty("faceRenderer").objectReferenceValue = faceRenderer;
            serialized.FindProperty("defaultFace").objectReferenceValue = neutral;
            serialized.FindProperty("useUnscaledTime").boolValue = true;

            List<FaceClip> clips = ReadFaceClips();
            SerializedProperty array = serialized.FindProperty("clips");
            array.arraySize = clips.Count;
            for (int i = 0; i < clips.Count; i++)
            {
                FaceClip clip = clips[i];
                SerializedProperty element = array.GetArrayElementAtIndex(i);
                element.FindPropertyRelative("name").stringValue = clip.Name;
                element.FindPropertyRelative("loop").boolValue = clip.Loop;
                element.FindPropertyRelative("framesPerSecond").floatValue = 12f;

                SerializedProperty frames = element.FindPropertyRelative("frames");
                SerializedProperty durations = element.FindPropertyRelative("frameDurations");
                frames.arraySize = clip.Frames.Count;
                durations.arraySize = clip.Frames.Count;
                for (int f = 0; f < clip.Frames.Count; f++)
                {
                    frames.GetArrayElementAtIndex(f).objectReferenceValue = LoadFace(clip.Frames[f]);
                    durations.GetArrayElementAtIndex(f).floatValue = clip.Durations[f];
                }
            }
            serialized.ApplyModifiedPropertiesWithoutUndo();
        }

        private sealed class FaceClip
        {
            public string Name;
            public bool Loop;
            public readonly List<string> Frames = new List<string>();
            public readonly List<float> Durations = new List<float>();
        }

        private static List<FaceClip> ReadFaceClips()
        {
            TextAsset text = AssetDatabase.LoadAssetAtPath<TextAsset>(Manifest);
            if (text == null) throw new InvalidOperationException("Missing face manifest " + Manifest);
            JsonValue root = Json.Parse(text.text);
            if (root == null || root.Kind != JsonKind.Object || !root.Members.ContainsKey("clips"))
            {
                throw new InvalidOperationException("The face manifest is not valid JSON with a 'clips' object.");
            }
            JsonValue clips = root.Members["clips"];
            var result = new List<FaceClip>();
            foreach (KeyValuePair<string, JsonValue> entry in clips.Members)
            {
                JsonValue body = entry.Value;
                if (body.Kind != JsonKind.Object || !body.Members.ContainsKey("frames")) continue;
                FaceClip clip = new FaceClip { Name = entry.Key };
                JsonValue loop;
                clip.Loop = body.Members.TryGetValue("loop", out loop) && loop.Boolean;
                foreach (JsonValue frame in body.Members["frames"].Items)
                {
                    string png = frame.Members["png"].Text;
                    long milliseconds;
                    if (!frame.Members["duration_ms"].TryInteger(out milliseconds)) continue;
                    clip.Frames.Add(Path.GetFileNameWithoutExtension(png));
                    clip.Durations.Add(milliseconds / 1000f);
                }
                if (clip.Frames.Count > 0) result.Add(clip);
            }
            if (result.Count == 0) throw new InvalidOperationException("The face manifest declares no usable clips.");
            return result;
        }

        /// <summary>
        /// Creates the backdrop quad's mesh and unlit material.
        ///
        /// The mesh is built here rather than reusing Unity's primitive so the
        /// winding is not a guess: it carries both windings, which makes the
        /// quad visible from either side and removes any question of which way
        /// the camera ends up facing it. Four extra triangles is a fair price
        /// for a backdrop that cannot silently disappear.
        /// </summary>
        private static void CreateBackdropAssets()
        {
            ConfigureBackdropImporter();
            Texture2D image = AssetDatabase.LoadAssetAtPath<Texture2D>(Backdrop);
            if (image == null)
            {
                throw new InvalidOperationException("The backdrop at " + Backdrop + " did not import.");
            }

            Mesh mesh = new Mesh();
            mesh.name = "RoomBackdropQuad";
            mesh.vertices = new[]
            {
                new Vector3(-0.5f, -0.5f, 0f), new Vector3(0.5f, -0.5f, 0f),
                new Vector3(-0.5f, 0.5f, 0f), new Vector3(0.5f, 0.5f, 0f)
            };
            mesh.uv = new[]
            {
                new Vector2(0f, 0f), new Vector2(1f, 0f),
                new Vector2(0f, 1f), new Vector2(1f, 1f)
            };
            mesh.normals = new[]
            {
                -Vector3.forward, -Vector3.forward, -Vector3.forward, -Vector3.forward
            };
            mesh.triangles = new[] { 0, 1, 2, 2, 1, 3, 0, 2, 1, 2, 3, 1 };
            mesh.RecalculateBounds();
            AssetDatabase.CreateAsset(mesh, BackdropMesh);

            Shader shader = Shader.Find("Unlit/Texture") ??
                            Shader.Find("Universal Render Pipeline/Unlit");
            if (shader == null)
            {
                throw new InvalidOperationException(
                    "No unlit shader found for the backdrop. Add an explicit " +
                    "material adapter for this render pipeline.");
            }
            Material material = new Material(shader);
            material.name = "RoomBackdrop_Unlit_Generated";
            material.mainTexture = image;
            AssetDatabase.CreateAsset(material, BackdropMaterial);

            // Opening a new scene invalidates references to assets that exist
            // only in memory, which serialises as a silent null. Flush first,
            // so the scene can reload both from disk.
            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();
        }

        /// <summary>
        /// Parks the backdrop behind the character and hands the runtime
        /// component what it needs to keep filling whatever screen it lands on.
        /// </summary>
        private static void CreateBackdrop(Camera camera, float characterDistance)
        {
            Texture2D image = AssetDatabase.LoadAssetAtPath<Texture2D>(Backdrop);
            Mesh mesh = AssetDatabase.LoadAssetAtPath<Mesh>(BackdropMesh);
            Material material = AssetDatabase.LoadAssetAtPath<Material>(BackdropMaterial);
            if (image == null || mesh == null || material == null)
            {
                throw new InvalidOperationException(
                    "The generated backdrop assets did not reload from disk.");
            }

            // Well behind the character, and inside the far plane with room to
            // spare so the quad is never clipped away.
            float distance = Mathf.Max(characterDistance * 2.5f, characterDistance + 4f);
            camera.farClipPlane = Mathf.Max(camera.farClipPlane, distance * 2f);

            GameObject backdrop = new GameObject("Room Backdrop");
            backdrop.AddComponent<MeshFilter>().sharedMesh = mesh;
            MeshRenderer renderer = backdrop.AddComponent<MeshRenderer>();
            renderer.sharedMaterial = material;
            // Decoration: it neither casts nor receives the key light's shadows.
            renderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            renderer.receiveShadows = false;
            renderer.lightProbeUsage = UnityEngine.Rendering.LightProbeUsage.Off;
            renderer.reflectionProbeUsage = UnityEngine.Rendering.ReflectionProbeUsage.Off;

            RoomBackdrop component = backdrop.AddComponent<RoomBackdrop>();
            SerializedObject serialized = new SerializedObject(component);
            serialized.FindProperty("roomCamera").objectReferenceValue = camera;
            serialized.FindProperty("distance").floatValue = distance;
            serialized.FindProperty("imageAspect").floatValue =
                image.height == 0 ? 2f : (float)image.width / image.height;
            serialized.ApplyModifiedPropertiesWithoutUndo();
            Require(serialized, "roomCamera");

            if (backdrop.GetComponent<MeshFilter>().sharedMesh == null ||
                renderer.sharedMaterial == null)
            {
                throw new InvalidOperationException(
                    "The generated scene left the backdrop quad without a mesh or material.");
            }
        }

        private static RobertSkinDefinition CreateSkinDefinition(
            GameObject prefab, Texture2D neutral, string stableId, string assetPath)
        {
            RobertSkinDefinition skin = ScriptableObject.CreateInstance<RobertSkinDefinition>();
            SerializedObject serialized = new SerializedObject(skin);
            serialized.FindProperty("stableId").stringValue = stableId;
            serialized.FindProperty("modelPrefab").objectReferenceValue = prefab;
            serialized.FindProperty("defaultFace").objectReferenceValue = neutral;
            serialized.ApplyModifiedPropertiesWithoutUndo();

            AssetDatabase.CreateAsset(skin, assetPath);
            // Flush before the scene is replaced: opening a new scene
            // invalidates references to assets that are still only in memory,
            // which silently serialises as a null reference.
            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();
            return skin;
        }

        /// <summary>
        /// A reference that failed to serialise shows up on a device only as a
        /// generic "wire a valid ..." error, so check it here instead.
        /// </summary>
        private static void Require(SerializedObject target, string field)
        {
            SerializedProperty property = target.FindProperty(field);
            if (property == null || property.objectReferenceValue == null)
            {
                throw new InvalidOperationException(
                    "The generated scene left '" + field + "' unassigned on " +
                    target.targetObject.GetType().Name + ".");
            }
        }

        private static string CreateScene(
            RobertSkinDefinition skin, List<string> outfitAssets, Texture2D neutral, Texture2D happy,
            Texture2D surprised, Bounds framing)
        {
            Scene scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

            GameObject cameraObject = new GameObject("Room Camera");
            Camera camera = cameraObject.AddComponent<Camera>();
            camera.clearFlags = CameraClearFlags.SolidColor;
            // The backdrop covers the frustum, so this only shows in the frame
            // before it is first sized. It is the image's own sky colour rather
            // than the transparent clear this used to have: transparent meant a
            // pitch-black window wherever the full-bleed page was not painting.
            camera.backgroundColor = new Color(0.498f, 0.659f, 0.706f, 1f);
            // Frame the measured model rather than a guessed distance: the
            // character's real size is whatever the artist exported.
            const float fieldOfView = 40f;
            // The character page now carries only the character and one reply
            // bubble, so the character can take the middle of the frame instead
            // of hiding above a stack of cards. This still leaves the lower
            // quarter clear for the bubble and the composer.
            const float margin = 2.6f;
            camera.fieldOfView = fieldOfView;
            float extent = Mathf.Max(framing.size.x, framing.size.y, 0.1f);
            float distance =
                extent * 0.5f / Mathf.Tan(fieldOfView * 0.5f * Mathf.Deg2Rad) * margin;
            // Level with the model and barely tilted: pitching the camera down
            // pushes the subject up the frame, which is what used to strand the
            // character against the sky above the backdrop's horizon.
            camera.transform.position = new Vector3(
                framing.center.x, framing.center.y, framing.center.z + distance);
            camera.transform.rotation = Quaternion.Euler(2f, 180f, 0f);

            CreateBackdrop(camera, distance);

            GameObject lightObject = new GameObject("Key Light");
            Light light = lightObject.AddComponent<Light>();
            light.type = LightType.Directional;
            light.intensity = 1.1f;
            lightObject.transform.rotation = Quaternion.Euler(45f, 160f, 0f);

            GameObject character = new GameObject("Robert");
            GameObject visualRoot = new GameObject("Visual Root");
            visualRoot.transform.SetParent(character.transform, false);
            RobertSkinController controller = character.AddComponent<RobertSkinController>();
            SerializedObject serializedController = new SerializedObject(controller);
            serializedController.FindProperty("visualRoot").objectReferenceValue = visualRoot.transform;
            // Re-resolve after the scene switch rather than trusting the
            // instance created before it.
            RobertSkinDefinition persisted =
                AssetDatabase.LoadAssetAtPath<RobertSkinDefinition>(SkinAsset) ?? skin;
            serializedController.FindProperty("defaultSkin").objectReferenceValue = persisted;
            serializedController.ApplyModifiedPropertiesWithoutUndo();
            Require(serializedController, "visualRoot");
            Require(serializedController, "defaultSkin");

            GameObject bridge = new GameObject("CompanionBridge");
            RobertAvatarPresentation presentation = bridge.AddComponent<RobertAvatarPresentation>();
            SerializedObject serializedPresentation = new SerializedObject(presentation);
            serializedPresentation.FindProperty("skinController").objectReferenceValue = controller;
            serializedPresentation.FindProperty("neutralFace").objectReferenceValue = neutral;
            serializedPresentation.FindProperty("happyFace").objectReferenceValue = happy;
            serializedPresentation.FindProperty("surprisedFace").objectReferenceValue = surprised;
            // Re-resolved by path, like the default skin: the scene switch
            // invalidates the instances created before it.
            SerializedProperty outfits = serializedPresentation.FindProperty("outfits");
            outfits.arraySize = outfitAssets.Count;
            for (int i = 0; i < outfitAssets.Count; i++)
            {
                RobertSkinDefinition outfit = AssetDatabase.LoadAssetAtPath<RobertSkinDefinition>(outfitAssets[i]);
                if (outfit == null) throw new InvalidOperationException("Lost outfit " + outfitAssets[i] + ".");
                outfits.GetArrayElementAtIndex(i).objectReferenceValue = outfit;
            }
            serializedPresentation.ApplyModifiedPropertiesWithoutUndo();
            SerializedProperty saved = serializedPresentation.FindProperty("outfits");
            for (int i = 0; i < saved.arraySize; i++)
            {
                if (saved.GetArrayElementAtIndex(i).objectReferenceValue == null)
                {
                    throw new InvalidOperationException("The generated scene left outfit " + i + " unassigned.");
                }
            }
            foreach (string field in new[] { "skinController", "neutralFace", "happyFace", "surprisedFace" })
            {
                Require(serializedPresentation, field);
            }

            CompanionBridgeReceiver receiver = bridge.AddComponent<CompanionBridgeReceiver>();
            SerializedObject serializedReceiver = new SerializedObject(receiver);
            serializedReceiver.FindProperty("presentationBehaviour").objectReferenceValue = presentation;
            serializedReceiver.ApplyModifiedPropertiesWithoutUndo();
            Require(serializedReceiver, "presentationBehaviour");

            bridge.AddComponent<AndroidUnityEventTransport>();

            string scenePath = Generated + "/RobertRoom.unity";
            if (!EditorSceneManager.SaveScene(scene, scenePath))
            {
                throw new InvalidOperationException("Could not save the generated scene.");
            }
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(scenePath, true) };
            return scenePath;
        }
    }
}
