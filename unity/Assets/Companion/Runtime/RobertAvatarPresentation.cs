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

        [Tooltip("Modelled outfits, each a whole skin whose Stable Id is the cosmetic id " +
                 "the bridge allowlists. Written by the room builder.")]
        [SerializeField] private RobertSkinDefinition[] outfits = new RobertSkinDefinition[0];

        /// <summary>
        /// The colourways of the original model, keyed by the ids the bridge
        /// allowlists. Together with <see cref="outfits"/> this is the whole
        /// catalogue, fixed in the build: the room grants no ownership and
        /// never invents an entry, so an id in neither is declined rather than
        /// approximated.
        ///
        /// A colourway recolours the original model and leaves the face screen
        /// alone; an outfit swaps in its own model, which is authored in its
        /// own colours and is never tinted.
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
        private const string DefaultSkinId = "default";

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
                    // Re-assert the look: initialize also runs after a room is
                    // rebuilt, which installs a fresh default visual. An outfit
                    // swaps that model, so the Animator is resolved afterwards.
                    if (!ApplyLook(cosmeticId)) return false;
                    current = ResolveAnimator();
                    if (current == null) return false;
                    current.speed = 1f;
                    return SetFace("neutral") && Play(current, "Idle");
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
        /// Installs a look: an outfit's own model, or the original model in a
        /// colourway. Colourways recolour the body only; the face screen is an
        /// unlit display of approved art, and tinting it would change what the
        /// face reads as.
        /// </summary>
        private bool ApplyLook(string requested)
        {
            if (requested == null || skinController == null) return false;
            RobertSkinDefinition outfit = FindOutfit(requested);
            if (outfit != null)
            {
                if (!Wear(outfit)) return false;
                cosmeticId = requested;
                return true;
            }

            Color tint;
            if (!Looks.TryGetValue(requested, out tint)) return false;
            // A colourway belongs to the original model, so an outfit comes
            // off first; SelectSkin(null) is the controller's default skin.
            if (!IsWearing(DefaultSkinId) && (!skinController.SelectSkin(null) || !IsWearing(DefaultSkinId)))
            {
                return false;
            }
            RefreshVisual();
            RobertFacePlayer player = skinController.FacePlayer;
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

        private RobertSkinDefinition FindOutfit(string id)
        {
            if (outfits == null) return null;
            foreach (RobertSkinDefinition outfit in outfits)
            {
                if (outfit != null && outfit.StableId == id) return outfit;
            }
            return null;
        }

        private bool IsWearing(string stableId)
        {
            RobertSkinDefinition current = skinController.CurrentSkin;
            return current != null && current.StableId == stableId;
        }

        /// <summary>
        /// Swaps in an outfit's model. The controller falls back to the default
        /// skin when an outfit cannot be installed, so success is judged by what
        /// is actually worn afterwards, never by the call's return value alone.
        /// </summary>
        private bool Wear(RobertSkinDefinition outfit)
        {
            if (skinController.CurrentSkin == outfit) return true;
            if (!skinController.SelectSkin(outfit) || skinController.CurrentSkin != outfit) return false;
            RefreshVisual();
            return true;
        }

        /// <summary>
        /// A swap replaces the model, its Animator and its face player, so the
        /// new visual starts neutral and idle, and stays frozen if the room is
        /// paused. Does nothing when the installed visual has not changed.
        /// </summary>
        private void RefreshVisual()
        {
            if (animator != null && boundSkin == skinController.CurrentSkin) return;
            Animator current = ResolveAnimator();
            if (current == null) return;
            SetFace("neutral");
            Play(current, "Idle");
            current.speed = paused ? 0f : 1f;
            if (paused) skinController.FacePlayer.StopPlayback();
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
