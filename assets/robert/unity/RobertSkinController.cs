using UnityEngine;

namespace RobertCharacter
{
    public sealed class RobertSkinController : MonoBehaviour
    {
        [SerializeField] private Transform visualRoot;
        [SerializeField] private RobertSkinDefinition defaultSkin;
        private GameObject currentVisual;

        public RobertSkinDefinition CurrentSkin { get; private set; }
        public RobertFacePlayer FacePlayer { get; private set; }

        private void Start()
        {
            if (currentVisual == null && !SelectSkin(null))
                Debug.LogError("Robert: wire a valid default skin, visual root and face player.", this);
        }

        // Returns true when a requested skin OR its default fallback was installed.
        public bool SelectSkin(RobertSkinDefinition requested)
        {
            if (visualRoot == null) return false;
            RobertSkinDefinition selected = requested != null ? requested : defaultSkin;
            if (TryInstall(selected)) return true;
            return selected != defaultSkin && TryInstall(defaultSkin);
        }

        private bool TryInstall(RobertSkinDefinition skin)
        {
            if (skin == null || string.IsNullOrWhiteSpace(skin.StableId) ||
                skin.ModelPrefab == null || skin.DefaultFace == null) return false;
            if (skin == CurrentSkin && currentVisual != null) return true;

            // Stage inactive so a rejected prefab never renders or starts animation.
            GameObject staging = new GameObject("Robert skin staging");
            staging.SetActive(false);
            staging.transform.SetParent(visualRoot, false);
            GameObject candidate = Instantiate(skin.ModelPrefab, staging.transform, false);
            candidate.transform.localPosition = Vector3.zero;
            candidate.transform.localRotation = Quaternion.identity;
            candidate.transform.localScale = Vector3.one;
            RobertFacePlayer[] players = candidate.GetComponentsInChildren<RobertFacePlayer>(true);
            if (players.Length != 1 || !players[0].enabled || !players[0].Rebind() ||
                !players[0].SetDefaultFace(skin.DefaultFace))
            {
                Destroy(staging);
                return false;
            }

            if (currentVisual != null)
            {
                currentVisual.SetActive(false);
                Destroy(currentVisual);
            }
            candidate.transform.SetParent(visualRoot, false);
            candidate.SetActive(true);
            currentVisual = candidate;
            CurrentSkin = skin;
            FacePlayer = players[0];
            Destroy(staging);
            return true;
        }

        private void OnDestroy()
        {
            if (currentVisual != null) Destroy(currentVisual);
        }
    }
}
