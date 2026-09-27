using System.Runtime.CompilerServices;

// The room builder reuses this assembly's strict JSON reader to parse the
// approved face-timing manifest, rather than carrying a second parser or
// hardcoding timings the manifest owns. The EditMode tests read that manifest
// the same way to check what the builder generated from it.
[assembly: InternalsVisibleTo("Companion.Presentation.Editor")]
[assembly: InternalsVisibleTo("Companion.Presentation.Tests")]
