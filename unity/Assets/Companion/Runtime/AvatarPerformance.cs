namespace Companion.Presentation
{
    /// <summary>
    /// The body and face a performance drives. The Unity presentation implements
    /// it over the Animator and the face player; tests implement it with fakes.
    /// </summary>
    public interface IAvatarRig
    {
        /// <summary>
        /// Starts a body state, crossfading over
        /// <see cref="AvatarPerformance.CrossfadeSeconds"/> or cutting to it.
        /// False when the state does not exist.
        /// </summary>
        bool PlayBody(string state, bool crossfade);

        /// <summary>Starts a named face clip. Its own loop flag decides whether it repeats.</summary>
        bool PlayFace(string clip);

        /// <summary>Stops face playback and shows the neutral face.</summary>
        bool ShowNeutralFace();

        /// <summary>Stops body and face time (true), or lets the body run again (false).</summary>
        void SetFrozen(bool frozen);

        /// <summary>True when the body is in Standing or Idle, or already blending into one.</summary>
        bool BodyResting { get; }

        /// <summary>Seconds one pass of a face clip lasts, or zero when the clip is unknown.</summary>
        float FaceSeconds(string clip);
    }

    /// <summary>
    /// What Robert's body and face do for each allowlisted cue.
    ///
    /// Engine-free on purpose, like <see cref="BridgeSession"/>, so the pairing
    /// and resumption rules can be compiled and exercised without Unity.
    ///
    /// Resting is the body in Standing (or its alias Idle) with the `idle` face,
    /// which blinks now and then. Talk loops with the `talk` mouth cycle until
    /// the next body cue. Wave and Celebrate are one-shots that show `joy`; Nod
    /// is a one-shot that keeps the idle face. One-shots return to Standing
    /// through the Animator's own exit transitions, and a one-shot face returns
    /// to the neutral PNG by itself. Blinking resumes once a one-shot face has
    /// ended and the body is resting again, which <see cref="Tick"/> watches.
    ///
    /// Nothing here allocates after construction, so calling
    /// <see cref="Tick"/> every frame is free in the steady state.
    /// </summary>
    public sealed class AvatarPerformance
    {
        public const string Standing = "Standing";
        public const string Idle = "Idle";
        public const string Talk = "Talk";
        public const string Wave = "Wave";
        public const string Nod = "Nod";
        public const string Celebrate = "Celebrate";

        /// <summary>Face clips. Lowercase, and never confused with the body clips above.</summary>
        public const string IdleFace = "idle";
        public const string TalkFace = "talk";
        public const string JoyFace = "joy";

        /// <summary>The emotion that shows the neutral face rather than a clip.</summary>
        public const string Neutral = "neutral";

        /// <summary>Body crossfades and the one-shots' return to Standing.</summary>
        public const float CrossfadeSeconds = 0.2f;

        private enum Face { None, Idle, Talk, OneShot, Neutral, Frozen }

        private Face face = Face.None;
        private string faceClip;
        private double faceEndsAt;
        private string bodyCue;
        private string bodyLoop = Standing;
        private bool paused;

        /// <summary>True between `app.pause` and `app.resume`.</summary>
        public bool Paused { get { return paused; } }

        /// <summary>
        /// The looping body state the room is in or returns to: Standing, Idle
        /// or Talk. One-shots return to Standing, so they leave this at Standing.
        /// </summary>
        public string BodyLoop { get { return bodyLoop; } }

        /// <summary>The face clip being driven, or null while the neutral face shows.</summary>
        public string FaceClip { get { return faceClip; } }

        public static bool IsLoop(string animation)
        {
            return animation == Standing || animation == Idle || animation == Talk;
        }

        public static bool IsResting(string animation)
        {
            return animation == Standing || animation == Idle;
        }

        /// <summary>
        /// The face clip a body cue brings, following the package's
        /// `shared/animations.json`. Null for a name that is not a body clip.
        /// </summary>
        public static string PairedFace(string animation)
        {
            if (animation == Standing || animation == Idle || animation == Nod) return IdleFace;
            if (animation == Talk) return TalkFace;
            if (animation == Wave || animation == Celebrate) return JoyFace;
            return null;
        }

        /// <summary>Initialization: resting, running, blinking.</summary>
        public bool Begin(IAvatarRig rig)
        {
            paused = false;
            rig.SetFrozen(false);
            bodyLoop = Standing;
            bool body = Cue(rig, Standing, false);
            return StartLoopFace(rig, IdleFace, Face.Idle) && body;
        }

        /// <summary>`avatar.play`: crossfades the body and starts its paired face.</summary>
        public bool Play(IAvatarRig rig, string animation, double now)
        {
            if (paused) return false;
            // A loop that is already playing never ends by itself, so cueing it
            // again would only restart it with a visible hitch.
            if (!(IsLoop(animation) && animation == bodyCue) && !Cue(rig, animation, true)) return false;
            bodyLoop = IsLoop(animation) ? animation : Standing;

            string paired = PairedFace(animation);
            if (paired == TalkFace)
            {
                return face == Face.Talk || StartLoopFace(rig, TalkFace, Face.Talk);
            }
            if (paired == JoyFace) return StartOneShot(rig, JoyFace, now);
            if (paired == IdleFace)
            {
                // An expression still showing finishes first; blinking follows.
                if (face == Face.Idle || OneShotRunning(now)) return true;
                return StartLoopFace(rig, IdleFace, Face.Idle);
            }
            return true;
        }

        /// <summary>
        /// `avatar.set_emotion`: every emotion but `neutral` plays its face clip
        /// once. During Talk this interrupts the mouth cycle; the sender avoids
        /// that by returning to Standing first.
        /// </summary>
        public bool Emotion(IAvatarRig rig, string emotion, double now)
        {
            if (paused) return false;
            if (emotion != Neutral) return StartOneShot(rig, emotion, now);
            if (!rig.ShowNeutralFace()) return false;
            face = Face.Neutral;
            faceClip = null;
            if (rig.BodyResting) StartLoopFace(rig, IdleFace, Face.Idle);
            return true;
        }

        /// <summary>`app.pause`: freezes the body and stops the face where it is.</summary>
        public bool Pause(IAvatarRig rig)
        {
            paused = true;
            rig.SetFrozen(true);
            face = Face.Frozen;
            faceClip = null;
            return true;
        }

        /// <summary>`app.resume`: back to Standing and the blinking face.</summary>
        public bool Resume(IAvatarRig rig)
        {
            paused = false;
            rig.SetFrozen(false);
            bodyLoop = Standing;
            bool body = Cue(rig, Standing, true);
            return StartLoopFace(rig, IdleFace, Face.Idle) && body;
        }

        /// <summary>
        /// After a skin swap, whose new model starts its own Animator and face
        /// player: resting with the idle face, talking if Talk was the loop, or
        /// frozen on the neutral face if paused. A one-shot in progress does not
        /// carry over; the swap lands where it would have returned to.
        /// </summary>
        public bool Reapply(IAvatarRig rig)
        {
            if (paused)
            {
                bool still = Cue(rig, Standing, false);
                rig.ShowNeutralFace();
                rig.SetFrozen(true);
                face = Face.Frozen;
                faceClip = null;
                return still;
            }
            rig.SetFrozen(false);
            bool body = Cue(rig, bodyLoop, false);
            bool talking = bodyLoop == Talk;
            return StartLoopFace(rig, talking ? TalkFace : IdleFace, talking ? Face.Talk : Face.Idle) && body;
        }

        /// <summary>
        /// Per frame: once a one-shot face has run its course and the body is
        /// resting, the blinking face resumes. Until the body rests the face
        /// stays neutral, which is where the face player leaves a one-shot.
        /// </summary>
        public void Tick(IAvatarRig rig, double now)
        {
            if (paused) return;
            if (face == Face.OneShot)
            {
                if (now < faceEndsAt) return;
                face = Face.Neutral;
                faceClip = null;
            }
            else if (face != Face.Neutral)
            {
                return;
            }
            if (rig.BodyResting) StartLoopFace(rig, IdleFace, Face.Idle);
        }

        private bool OneShotRunning(double now)
        {
            return face == Face.OneShot && now < faceEndsAt;
        }

        private bool Cue(IAvatarRig rig, string state, bool crossfade)
        {
            if (!rig.PlayBody(state, crossfade)) return false;
            bodyCue = state;
            return true;
        }

        private bool StartLoopFace(IAvatarRig rig, string clip, Face state)
        {
            if (!rig.PlayFace(clip)) return false;
            face = state;
            faceClip = clip;
            return true;
        }

        private bool StartOneShot(IAvatarRig rig, string clip, double now)
        {
            float seconds = rig.FaceSeconds(clip);
            if (!(seconds > 0f) || !rig.PlayFace(clip)) return false;
            face = Face.OneShot;
            faceClip = clip;
            faceEndsAt = now + seconds;
            return true;
        }
    }
}
