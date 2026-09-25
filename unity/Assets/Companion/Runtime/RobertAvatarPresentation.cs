using System.Collections.Generic;
using RobertCharacter;
using UnityEngine;

namespace Companion.Presentation
{
    /// <summary>
    /// Binds validated bridge commands to Robert's Animator and face player.
    ///
    /// Presentation only. Body clips drive the Animator; emotions set a static
    /// face PNG; pause freezes the body and stops local face playback. Idle
    /// loops while resumed, and one-shot clips return to it through the
    /// Animator's own exit transitions rather than a completion event.
    /// </summary>
    [DisallowMultipleComponent]
    public sealed class RobertAvatarPresentation : MonoBehaviour, IAvatarPresentation
    {
        [SerializeField] private RobertSkinController skinController;
        [SerializeField] private Texture2D neutralFace;
        [SerializeField] private Texture2D happyFace;
        [SerializeField] private Texture2D surprisedFace;

        [Tooltip("Capabilities this room can actually perform. Anything not " +
                 "installed here is never negotiated, so Flutter will not send it.")]
        [SerializeField] private string[] installedCapabilities = {
            "avatar.play", "avatar.set_emotion", "avatar.set_cosmetics",
            "app.pause", "app.resume"
        };

        /// <summary>
        /// The look each earned cosmetic installs, keyed by the ids the bridge
        /// allowlists. The catalogue is fixed in the build: the room grants no
        /// ownership and never invents an entry, so an id that is not here is
        /// declined rather than approximated.
        ///
        /// Each look currently recolours the body and leaves the face screen
        /// alone. The skin system already swaps whole model prefabs, so
        /// modelled garments drop in later as new skin definitions without the
        /// bridge contract or the server catalogue changing.
        /// </summary>
        private static readonly Dictionary<string, Color> Looks =
            new Dictionary<string, Color>
            {
                { "default", Color.white },
                { "sunset", new Color(0.93f, 0.56f, 0.36f) },
                { "dune", new Color(0.95f, 0.86f, 0.68f) },
                { "midnight", new Color(0.36f, 0.62f, 0.62f) }
            };

        private static readonly int ColorProperty = Shader.PropertyToID("_Color");
        private static readonly int BaseColorProperty = Shader.PropertyToID("_BaseColor");
        private const string FaceMesh = "FaceScreen";

        private readonly Dictionary<string, Texture2D> faces = new Dictionary<string, Texture2D>();
        private Animator animator;
        private RobertSkinDefinition boundSkin;
        private string cosmeticId = "default";
        private bool paused;

        private void Awake()
        {
            faces["neutral"] = neutralFace;
            faces["happy"] = happyFace;
            faces["surprised"] = surprisedFace;
        }

        /// <summary>
        /// The Animator belongs to the model prefab, which the skin controller
        /// instantiates at runtime, so it cannot be wired in the scene. Resolve
        /// it from whatever visual is currently installed and re-resolve after a
        /// skin swap, which replaces that object entirely.
        /// </summary>
        private Animator ResolveAnimator()
        {
            if (skinController == null) return null;
            if (animator != null && boundSkin == skinController.CurrentSkin) return animator;
            RobertFacePlayer player = skinController.FacePlayer;
            if (player == null) return null;
            animator = player.GetComponentInParent<Animator>();
            boundSkin = skinController.CurrentSkin;
            return animator;
        }

        /// <summary>
        /// False whenever a required presentation asset is missing, which makes
        /// the session answer `asset_unavailable` and lets Flutter fall back to
        /// the static avatar instead of showing a broken room.
        /// </summary>
        public bool IsAvailable
        {
            get
            {
                Animator current = ResolveAnimator();
                return current != null && current.runtimeAnimatorController != null &&
                       skinController.FacePlayer != null && neutralFace != null;
            }
        }

        public string[] Capabilities { get { return installedCapabilities; } }

        public bool Apply(BridgeCommand command)
        {
            Animator current = ResolveAnimator();
            if (current == null) return false;
            switch (command.Type)
            {
                case BridgeCommand.Initialize:
                    paused = false;
                    current.speed = 1f;
                    // Re-assert the look: initialize also runs after a room is
                    // rebuilt, which installs a fresh visual at its own colours.
                    return ApplyLook(cosmeticId) && SetFace("neutral") &&
                           Play(current, "Idle");
                case "avatar.play":
                    // A cue arriving while paused is declined, not an error.
                    return !paused && Play(current, command.Animation);
                case "avatar.set_emotion":
                    return !paused && SetFace(command.Emotion);
                case "avatar.set_cosmetics":
                    // The receiver never grants ownership: Flutter sends this
                    // only after the service has confirmed its own inventory
                    // write, and the room just installs what it was told.
                    return skinController.CurrentSkin != null &&
                           ApplyLook(command.CosmeticId);
                case "app.pause":
                    paused = true;
                    current.speed = 0f;
                    skinController.FacePlayer.StopPlayback();
                    return true;
                case "app.resume":
                    paused = false;
                    current.speed = 1f;
                    return SetFace("neutral");
                default:
                    return false;
            }
        }

        private static bool Play(Animator target, string clip)
        {
            if (string.IsNullOrEmpty(clip)) return false;
            if (!target.HasState(0, Animator.StringToHash(clip))) return false;
            target.Play(clip, 0, 0f);
            return true;
        }

        /// <summary>
        /// Recolours the body of whatever visual is installed. The face screen
        /// is skipped: it is an unlit display of approved art, and tinting it
        /// would change what the face reads as.
        /// </summary>
        private bool ApplyLook(string requested)
        {
            Color tint;
            if (requested == null || !Looks.TryGetValue(requested, out tint)) return false;
            RobertFacePlayer player = skinController == null ? null : skinController.FacePlayer;
            if (player == null) return false;

            bool applied = false;
            foreach (Renderer renderer in player.GetComponentsInChildren<Renderer>(true))
            {
                if (renderer.gameObject.name == FaceMesh) continue;
                // The instance, never the shared asset: recolouring that would
                // persist into the next room and into the imported material.
                Material material = renderer.material;
                if (material == null) continue;
                if (material.HasProperty(ColorProperty))
                {
                    material.SetColor(ColorProperty, tint);
                    applied = true;
                }
                if (material.HasProperty(BaseColorProperty))
                {
                    material.SetColor(BaseColorProperty, tint);
                    applied = true;
                }
            }
            if (applied) cosmeticId = requested;
            return applied;
        }

        private bool SetFace(string emotion)
        {
            Texture2D texture;
            if (emotion == null || !faces.TryGetValue(emotion, out texture) || texture == null)
            {
                return false;
            }
            RobertFacePlayer player = skinController.FacePlayer;
            return player != null && player.SetFace(texture);
        }
    }
}
