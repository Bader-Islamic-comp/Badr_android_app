using System;
using System.Collections.Generic;
using RobertCharacter;
using UnityEngine;

namespace Companion.Presentation
{
    /// <summary>
    /// Binds validated bridge commands to Robert's Animator and face player.
    ///
    /// Presentation only. <see cref="AvatarPerformance"/> decides what the body
    /// and face do for each cue; this component carries that out on whichever
    /// model is installed. Body cues crossfade over 0.2 s, and one-shots return
    /// to Standing through the Animator's own exit transitions rather than a
    /// completion event. Each body cue starts its paired face clip, and a small
    /// per-frame check resumes the blinking face once a one-shot face has ended
    /// and the body is resting, because the shared face player reports neither.
    /// </summary>
    [DisallowMultipleComponent]
    public sealed class RobertAvatarPresentation : MonoBehaviour, IAvatarPresentation, IAvatarRig
    {
        /// <summary>One face clip's length, copied from the approved manifest by the room builder.</summary>
        [Serializable]
        private struct FaceCue
        {
            public string name;
            public float seconds;
        }

        [SerializeField] private RobertSkinController skinController;
        [SerializeField] private Texture2D neutralFace;

        [Tooltip("Every face clip's length in seconds, from the approved face manifest. " +
                 "Written by the room builder; it tells a finished one-shot face from a running one.")]
        [SerializeField] private FaceCue[] faceCues = new FaceCue[0];

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
        private static readonly int StandingState = Animator.StringToHash(AvatarPerformance.Standing);
        private static readonly int IdleState = Animator.StringToHash(AvatarPerformance.Idle);
        private const string FaceMesh = "FaceScreen";
        private const string DefaultSkinId = "default";

        private readonly AvatarPerformance performance = new AvatarPerformance();
        private Animator animator;
        private RobertSkinDefinition boundSkin;
        private string cosmeticId = "default";
        private string cuedState;
        private int cuedFrame = -10;

        /// <summary>The face player's clock: unscaled, so pausing time alone does not stop it.</summary>
        private static double Now { get { return Time.unscaledTimeAsDouble; } }

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
            if (ResolveAnimator() == null) return false;
            switch (command.Type)
            {
                case BridgeCommand.Initialize:
                    // Re-assert the look: initialize also runs after a room is
                    // rebuilt, which installs a fresh default visual. An outfit
                    // swaps that model, so the Animator is resolved afterwards.
                    if (!ApplyLook(cosmeticId) || ResolveAnimator() == null) return false;
                    return performance.Begin(this);
                case "avatar.play":
                    // A cue arriving while paused is declined, not an error.
                    return performance.Play(this, command.Animation, Now);
                case "avatar.set_emotion":
                    return performance.Emotion(this, command.Emotion, Now);
                case "avatar.set_cosmetics":
                    // The receiver never grants ownership: Flutter sends this
                    // only after the service has confirmed its own inventory
                    // write, and the room just installs what it was told.
                    return skinController.CurrentSkin != null &&
                           ApplyLook(command.CosmeticId);
                case "app.pause":
                    return performance.Pause(this);
                case "app.resume":
                    return performance.Resume(this);
                default:
                    return false;
            }
        }

        /// <summary>
        /// The face player reports neither a finished clip nor whether one is
        /// playing, so the performance watches the clock and the Animator here.
        /// Allocation-free: while the idle face loops this returns at once.
        /// </summary>
        private void Update()
        {
            performance.Tick(this, Now);
        }

        bool IAvatarRig.PlayBody(string state, bool crossfade)
        {
            Animator current = ResolveAnimator();
            if (current == null || string.IsNullOrEmpty(state)) return false;
            int hash = Animator.StringToHash(state);
            if (!current.HasState(0, hash)) return false;
            if (crossfade) current.CrossFadeInFixedTime(hash, AvatarPerformance.CrossfadeSeconds, 0, 0f);
            else current.Play(hash, 0, 0f);
            cuedState = state;
            cuedFrame = Time.frameCount;
            return true;
        }

        bool IAvatarRig.PlayFace(string clip)
        {
            RobertFacePlayer player = skinController != null ? skinController.FacePlayer : null;
            return player != null && player.Play(clip);
        }

        bool IAvatarRig.ShowNeutralFace()
        {
            RobertFacePlayer player = skinController != null ? skinController.FacePlayer : null;
            return player != null && neutralFace != null && player.SetFace(neutralFace);
        }

        void IAvatarRig.SetFrozen(bool frozen)
        {
            Animator current = ResolveAnimator();
            if (current != null) current.speed = frozen ? 0f : 1f;
            RobertFacePlayer player = skinController != null ? skinController.FacePlayer : null;
            // Stopping leaves the last image showing; nothing resumes it but a cue.
            if (frozen && player != null) player.StopPlayback();
        }

        bool IAvatarRig.BodyResting
        {
            get
            {
                Animator current = ResolveAnimator();
                if (current == null || !current.isActiveAndEnabled || !current.isInitialized) return false;
                // The Animator applies a cue on its next evaluation, so until
                // then its state info still describes where it was before.
                if (Time.frameCount - cuedFrame <= 1) return AvatarPerformance.IsResting(cuedState);
                AnimatorStateInfo state = current.IsInTransition(0)
                    ? current.GetNextAnimatorStateInfo(0)
                    : current.GetCurrentAnimatorStateInfo(0);
                return state.shortNameHash == StandingState || state.shortNameHash == IdleState;
            }
        }

        float IAvatarRig.FaceSeconds(string clip)
        {
            if (faceCues == null) return 0f;
            for (int i = 0; i < faceCues.Length; i++)
            {
                if (faceCues[i].name == clip) return faceCues[i].seconds;
            }
            return 0f;
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
        /// A swap replaces the model, its Animator and its face player, and the
        /// new ones start from scratch. Re-apply the current presentation state
        /// to them: resting with the idle face, talking if Talk was active, or
        /// frozen on the neutral face if the room is paused. Does nothing when
        /// the installed visual has not changed.
        /// </summary>
        private void RefreshVisual()
        {
            if (animator != null && boundSkin == skinController.CurrentSkin) return;
            if (ResolveAnimator() == null) return;
            performance.Reapply(this);
        }
    }
}
