# Companion reviewer APK

This package is for **adult reviewers using synthetic data**. It is a
development build, not a child pilot. It contains a token-free Android APK
with Robert's Unity 3D room and the voice-preview code. It contains no speech
models, generated adhkar audio, backend credentials or private user data.

## Install

The APK includes Android `arm64-v8a` and `x86_64` Flutter and Unity runtimes. Connect an
ARM64 Android phone with USB debugging, or start an x86_64 Android emulator.
From the unzipped package directory, run:

```powershell
adb devices
adb install -r .\companion-offline-universal.apk
```

Open **companion_mobile** from the Android launcher. The APK was built as a
release variant using the project's development signing key. Its size is
114,394,595 bytes; SHA256:

```text
76FFEFA50E7BEEF9D4CB846B69DC13978A7E72BBF447B3AF3B484CEF4C863A16
```

## What you can review

The standalone APK shows the offline UI, Unity 3D Robert and local orientation.
It has no configured backend URL or token. Quests, Style rewards, Talk service
replies and speech need the operator's local backend, so they are unavailable
from this package alone. For a connected live walkthrough, join the operator's
screen share; there is no public demo URL or remote phone endpoint.

The code includes Listen and hold-to-talk controls, but the required GPU
speech service, model weights, dua registry, reference voice and rendered
adhkar WAVs were unavailable when this package was made. Adhkar playback,
transcription and Robert's voice have not been demonstrated. The backend's
child-release `voice` switch remains off. The `companion` x86_64 emulator on
the operator's computer installed and launched this Unity-enabled APK. Robert
rendered in 3D and waved when tapped. A separate local debug build connected
to the backend and completed a synthetic question, orientation, reward and
look-equipping flow; that earlier run used the static fallback.
That credential-bearing build is not in this package. Physical phone hardware
remains untested.

Do not enter real names, family information or child recordings. Do not give
this build to children. A connected demonstration needs an operator-managed
local API and a fresh private token; none is included in this package.
