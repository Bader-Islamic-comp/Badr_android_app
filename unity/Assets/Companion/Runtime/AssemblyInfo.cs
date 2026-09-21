using System.Runtime.CompilerServices;

// The room builder reuses this assembly's strict JSON reader to parse the
// approved face-timing manifest, rather than carrying a second parser or
// hardcoding timings the manifest owns.
[assembly: InternalsVisibleTo("Companion.Presentation.Editor")]
