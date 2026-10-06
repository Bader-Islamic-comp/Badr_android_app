# Reviewer release: APK, web preview and demo server

An **adult-operated, synthetic-data development demo**. It is not a child
product: the gates in [development-boundary.md](development-boundary.md) are
still open. Enter only synthetic names and questions.

## Publishing the APK (maintainer)

The universal APK is about 114 MB. GitHub refuses files over 100 MB in a
repository, so it goes out as a **release asset** (up to 2 GB), never as a commit.

1. Build it as in the README (*Android builds*) with no `DEMO_API_*` defines.
   An APK built with `DEMO_API_TOKEN` carries that token and must not be shared.
2. Record its hash: `Get-FileHash .\companion-offline-universal.apk -Algorithm SHA256`.
3. On GitHub: **Releases → Draft a new release**, tag `v0.1.0-reviewer.N`
   on `main`, tick **Set as a pre-release**, attach the APK (and
   `reviewer-package.zip` if wanted), and paste the notes below with the hash.

### Release notes template

```markdown
Development preview for adult reviewers. Synthetic data only; not for children.

- companion-offline-universal.apk: ARM64 phones and x86_64 emulators, Unity room included
- SHA256: <paste hash>
- Built from: <commit>, Flutter 3.47.x, Unity 6000.3.24f1, development-signed (debug key)

Install: enable "Install unknown apps" for your browser or file manager and open the APK,
or `adb install -r companion-offline-universal.apk`.

Connect it to your own demo server: run Badr_backend `deploy/start-demo` (Docker), then in the
app open the parent area -> Development service and enter the address and token it prints.
The phone and the computer must be on the same Wi-Fi.

Not included or not verified: speech, grounded answers, physical-device testing.
```

### Which APK can connect

| Build | Offline UI and Unity room | Connects to a reviewer's server |
|-------|---------------------------|---------------------------------|
| Built before the *Development service* form (SHA256 `76FFEFA5…4C863A16`, 114,394,595 bytes) | yes | **no**: no form, and release builds blocked plain http |
| Built from `main` after that change | yes | yes, over http to a private address or https anywhere |

Rebuild and re-upload the APK after this change if reviewers should connect.

## Live web preview

<https://bader-islamic-comp.github.io/Badr_android_app/>, deployed by
`.github/workflows/pages.yml` on every push to `main`. It shows the screens and
the offline orientation only. There is no backend (CORS is off and an https page
cannot call http), no speech, no camera helper and no Unity room; Robert is a
still picture. One-time setup: **Settings → Pages → Source: GitHub Actions**.

## Demo server for reviewers' phones

See `Badr_backend/deploy/README.md`. In short: install Docker, then

```bash
bash deploy/start-demo.sh                                       # Linux / macOS
powershell -ExecutionPolicy Bypass -File deploy\start-demo.ps1  # Windows
```

and type the printed address and token into the app's parent area. The token is
held in memory only, so enter it again after relaunching the app.
