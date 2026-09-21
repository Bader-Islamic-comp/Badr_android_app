using System;
using System.Collections;
using UnityEngine;

namespace RobertCharacter
{
    [Serializable]
    public sealed class RobertFaceClip
    {
        public string name;
        public Texture2D[] frames;
        [Min(0.01f)] public float framesPerSecond = 12f;
        [Tooltip("Optional seconds per frame; leave empty to use FPS.")]
        public float[] frameDurations;
        public bool loop;
    }

    /// <summary>Instance-local PNG playback on the dedicated FaceScreen renderer.</summary>
    public sealed class RobertFacePlayer : MonoBehaviour
    {
        [SerializeField] private Renderer faceRenderer;
        [SerializeField] private Texture2D defaultFace;
        [SerializeField] private RobertFaceClip[] clips;
        [SerializeField] private bool useUnscaledTime = true;
        [Tooltip("Optional shader emission texture property. Its keyword must already be enabled on the material.")]
        [SerializeField] private string emissionTextureProperty = "";

        private static readonly int[] TextureProperties = {
            Shader.PropertyToID("_BaseMap"), Shader.PropertyToID("_MainTex"),
            Shader.PropertyToID("_BaseColorTexture")
        };
        private readonly bool[] supportedProperties = new bool[3];
        private MaterialPropertyBlock block;
        private Coroutine playback;
        private bool bound;
        private bool hasEmission;
        private int emissionProperty;

        private void Awake()
        {
            if (Rebind() && defaultFace != null) Apply(defaultFace);
        }

        // Call after replacing the renderer's material. This never edits shared materials.
        public bool Rebind()
        {
            bound = false;
            if (faceRenderer == null) return false;
            Material material = faceRenderer.sharedMaterial; // Dedicated screen uses slot 0.
            if (material == null) return false;
            bool any = false;
            for (int i = 0; i < TextureProperties.Length; i++)
            {
                supportedProperties[i] = material.HasProperty(TextureProperties[i]);
                any |= supportedProperties[i];
            }
            if (!any) return false;
            hasEmission = !string.IsNullOrEmpty(emissionTextureProperty);
            if (hasEmission)
            {
                emissionProperty = Shader.PropertyToID(emissionTextureProperty);
                hasEmission = material.HasProperty(emissionProperty);
            }
            if (block == null) block = new MaterialPropertyBlock();
            bound = true;
            return true;
        }

        public bool SetDefaultFace(Texture2D texture)
        {
            if (!SetFace(texture)) return false;
            defaultFace = texture;
            return true;
        }

        public bool SetFace(Texture2D texture)
        {
            // Invalid requests preserve existing valid playback.
            if (texture == null || (!bound && !Rebind())) return false;
            StopPlayback();
            Apply(texture);
            return true;
        }

        public bool Play(string clipName)
        {
            if (string.IsNullOrEmpty(clipName) || clips == null) return false;
            for (int i = 0; i < clips.Length; i++)
                if (clips[i] != null && clips[i].name == clipName) return Play(clips[i]);
            return false;
        }

        public bool Play(RobertFaceClip clip)
        {
            if (!isActiveAndEnabled || !Valid(clip) || (!bound && !Rebind())) return false;
            StopPlayback();
            playback = StartCoroutine(PlayFrames(clip));
            return true;
        }

        private static bool PositiveFinite(float value)
        {
            return value > 0f && !float.IsInfinity(value) && !float.IsNaN(value);
        }

        private static bool Valid(RobertFaceClip clip)
        {
            if (clip == null || clip.frames == null || clip.frames.Length == 0) return false;
            bool durations = clip.frameDurations != null && clip.frameDurations.Length > 0;
            if (durations && clip.frameDurations.Length != clip.frames.Length) return false;
            if (!durations && !PositiveFinite(clip.framesPerSecond)) return false;
            for (int i = 0; i < clip.frames.Length; i++)
                if (clip.frames[i] == null || (durations && !PositiveFinite(clip.frameDurations[i]))) return false;
            return true;
        }

        private IEnumerator PlayFrames(RobertFaceClip clip)
        {
            bool durations = clip.frameDurations != null && clip.frameDurations.Length > 0;
            float remaining = 0f;
            do
            {
                for (int i = 0; i < clip.frames.Length; i++)
                {
                    Apply(clip.frames[i]);
                    remaining += durations ? clip.frameDurations[i] : 1f / clip.framesPerSecond;
                    while (remaining > 0f)
                    {
                        yield return null; // No per-frame WaitForSeconds or other managed allocation.
                        remaining -= useUnscaledTime ? Time.unscaledDeltaTime : Time.deltaTime;
                    }
                }
            } while (clip.loop);
            if (defaultFace != null) Apply(defaultFace);
            playback = null;
        }

        private void Apply(Texture2D texture)
        {
            if (!bound || faceRenderer == null) return;
            faceRenderer.GetPropertyBlock(block, 0);
            for (int i = 0; i < TextureProperties.Length; i++)
                if (supportedProperties[i]) block.SetTexture(TextureProperties[i], texture);
            if (hasEmission) block.SetTexture(emissionProperty, texture);
            faceRenderer.SetPropertyBlock(block, 0);
        }

        public void StopPlayback()
        {
            if (playback == null) return;
            StopCoroutine(playback);
            playback = null;
        }

        private void OnDisable() { StopPlayback(); }
    }
}
