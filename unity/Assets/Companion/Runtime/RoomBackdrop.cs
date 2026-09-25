using UnityEngine;

namespace Companion.Presentation
{
    /// <summary>
    /// Keeps the room's backdrop image filling the camera on any device.
    ///
    /// The room has no skybox and clears to a solid colour, so without this the
    /// character stands in a flat void — on a device that read as pitch black
    /// behind the full-bleed Flutter page. A single unlit quad parked behind the
    /// character fixes that for one draw call and no lighting, but how big it
    /// has to be depends on the viewport, which is not known when the room is
    /// built. This sizes it, and crops the image rather than stretching it,
    /// whenever the viewport changes.
    ///
    /// Decoration only: it carries no text, no symbol and no real place, and
    /// nothing here reacts to a bridge command.
    /// </summary>
    [DisallowMultipleComponent]
    [RequireComponent(typeof(MeshRenderer))]
    public sealed class RoomBackdrop : MonoBehaviour
    {
        [SerializeField] private Camera roomCamera;

        [Tooltip("Metres behind the camera's pivot. Must clear the character.")]
        [SerializeField] private float distance = 12f;

        [Tooltip("Width over height of the backdrop image, so cropping it to " +
                 "the screen never distorts the picture.")]
        [SerializeField] private float imageAspect = 2f;

        private float appliedAspect = -1f;
        private float appliedFieldOfView = -1f;

        private void OnEnable()
        {
            Apply();
        }

        private void LateUpdate()
        {
            if (roomCamera == null) return;
            // Rotating the device, or a host that resizes the surface, changes
            // the aspect after the room is already running.
            if (Mathf.Approximately(roomCamera.aspect, appliedAspect) &&
                Mathf.Approximately(roomCamera.fieldOfView, appliedFieldOfView))
            {
                return;
            }
            Apply();
        }

        private void Apply()
        {
            if (roomCamera == null || distance <= 0f || imageAspect <= 0f) return;
            Renderer surface = GetComponent<Renderer>();
            if (surface == null) return;

            float height = 2f * distance *
                           Mathf.Tan(roomCamera.fieldOfView * 0.5f * Mathf.Deg2Rad);
            float width = height * roomCamera.aspect;
            Transform view = roomCamera.transform;
            transform.SetPositionAndRotation(
                view.position + view.forward * distance, view.rotation);
            transform.localScale = new Vector3(width, height, 1f);

            // "Cover": show the largest centred part of the image that has the
            // screen's shape. Scaling the quad alone would squash the picture
            // on a tall phone.
            float viewAspect = width / height;
            Vector2 scale = viewAspect > imageAspect
                ? new Vector2(1f, imageAspect / viewAspect)
                : new Vector2(viewAspect / imageAspect, 1f);
            Material instance = surface.material;
            if (instance != null)
            {
                instance.mainTextureScale = scale;
                instance.mainTextureOffset = (Vector2.one - scale) * 0.5f;
            }

            appliedAspect = roomCamera.aspect;
            appliedFieldOfView = roomCamera.fieldOfView;
        }
    }
}
