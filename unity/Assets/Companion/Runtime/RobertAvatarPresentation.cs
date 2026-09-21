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
        [SerializeField] private Animator animator;
        [SerializeField] private Texture2D neutralFace;
        [SerializeField] private Texture2D happyFace;
        [SerializeField] private Texture2D surprisedFace;

        [Tooltip("Capabilities this room can actually perform. Anything not " +
                 "installed here is never negotiated, so Flutter will not send it.")]
        [SerializeField] private string[] installedCapabilities = {
            "avatar.play", "avatar.set_emotion", "avatar.set_cosmetics",
            "app.pause", "app.resume"
        };

        private readonly Dictionary<string, Texture2D> faces = new Dictionary<string, Texture2D>();
        private bool paused;

        private void Awake()
        {
            faces["neutral"] = neutralFace;
            faces["happy"] = happyFace;
            faces["surprised"] = surprisedFace;
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
                return skinController != null && skinController.FacePlayer != null &&
                       animator != null && animator.runtimeAnimatorController != null &&
                       neutralFace != null;
            }
        }

        public string[] Capabilities { get { return installedCapabilities; } }

        public bool Apply(BridgeCommand command)
        {
            switch (command.Type)
            {
                case BridgeCommand.Initialize:
                    paused = false;
                    animator.speed = 1f;
                    return SetFace("neutral") && Play("Idle");
                case "avatar.play":
                    // A cue arriving while paused is declined, not an error.
                    return !paused && Play(command.Animation);
                case "avatar.set_emotion":
                    return !paused && SetFace(command.Emotion);
                case "avatar.set_cosmetics":
                    // Default equipment is already installed. The receiver never
                    // grants ownership; Flutter sends this only after the server
                    // has confirmed its own inventory write.
                    return command.CosmeticId == "default" && skinController.CurrentSkin != null;
                case "app.pause":
                    paused = true;
                    animator.speed = 0f;
                    skinController.FacePlayer.StopPlayback();
                    return true;
                case "app.resume":
                    paused = false;
                    animator.speed = 1f;
                    return SetFace("neutral");
                default:
                    return false;
            }
        }

        private bool Play(string clip)
        {
            if (string.IsNullOrEmpty(clip)) return false;
            animator.Play(clip, 0, 0f);
            return true;
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
