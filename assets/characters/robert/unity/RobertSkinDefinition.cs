using UnityEngine;

namespace RobertCharacter
{
    [CreateAssetMenu(menuName = "Robert/Skin Definition", fileName = "RobertSkin")]
    public sealed class RobertSkinDefinition : ScriptableObject
    {
        [SerializeField] private string stableId = "default";
        [SerializeField] private GameObject modelPrefab;
        [SerializeField] private Texture2D defaultFace;

        public string StableId { get { return stableId; } }
        public GameObject ModelPrefab { get { return modelPrefab; } }
        public Texture2D DefaultFace { get { return defaultFace; } }
    }
}
