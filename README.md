# Free Touch

Write equations on a Mac trackpad without holding a click. Recognize handwriting,
correct the LaTeX, preview the formatted equation, and copy it into your notes.

Native macOS prototype. The Xcode project and executable are still named
`TrackpadCanvas`. No ready-to-install public release is provided yet.

**Open → write → reposition or erase → recognize → correct → copy.**

## Why Free Touch?

Writing a fraction or a nested root can be more familiar than typing its LaTeX.
Free Touch brings handwriting, ink correction, recognition, and an editable
mathematical result into one small window. Its intended users are Mac owners
working with equations in study notes, technical documents, and AI chats.

The trackpad captures absolute finger positions without holding a click. Hold
Space to find a new position without leaving ink, and hold E to erase mistakes.
The formatted result is separate from the editable source, so you can check and
correct recognition before pasting it elsewhere.

This is an equation-input utility, not a complete notebook or diagram editor.
Whether it is faster than a user's existing method remains to be measured.

## Features

- Free-glide trackpad handwriting with a visible finger marker.
- Hold-Space positioning and hold-E whole-stroke erasing.
- Undo for strokes, eraser gestures, and Clear, retaining up to 100 edits.
- Handwriting-to-LaTeX recognition using a user-supplied Groq key.
- Bundled offline MathJax preview and editable LaTeX.
- Native menu-bar access, global shortcut, and clipboard export.

## Run from source

```sh
git clone https://github.com/ZoroZoro95/Kiwi.git
cd Kiwi
open TrackpadCanvas/TrackpadCanvas.xcodeproj
```

1. Clone this repository and open `TrackpadCanvas/TrackpadCanvas.xcodeproj` in Xcode.
2. Select the TrackpadCanvas scheme and My Mac destination. Select your own
   development team under Signing & Capabilities if required.
3. Run. Free Touch opens and its menu-bar icon provides Open and Quit commands.

Requires macOS 13.7 or newer and a compatible trackpad. Development/testing has
been on Apple silicon; Intel and external trackpad behavior remain unverified.
The verified development environment is macOS 13.7.7 with Xcode 15.2. Stop the
previous app process before running a rebuilt version. The repository contains
the original development-team setting; select your own team when building.

## Controls

| Action | Control |
| --- | --- |
| Open or hide | Control–Option–M |
| Start or stop trackpad capture | Control–K or Start Trackpad |
| Draw | Glide one finger without clicking |
| Position without drawing | Hold Space |
| Erase whole strokes | Hold E |
| Undo a stroke, eraser gesture, or Clear | Command–Z with canvas focused |
| Release trackpad capture | Escape |

Space takes priority over erasing. Lift your finger to finish an eraser gesture.
Undo history retains the last 100 edits. Capture temporarily hides and parks the
pointer; stopping or losing window focus restores pointer control.

## Recognize and reuse an equation

1. Create your own API key at https://console.groq.com/keys.
2. Open Groq Settings in Free Touch and save the key.
3. Draw an equation, press Escape, and click Recognize.
4. Check the formatted preview; edit the LaTeX field below to correct mistakes.
5. Copy LaTeX. In Notion, paste into a Block equation, not a regular paragraph.

Recognition currently uses `qwen/qwen3.8-27b` through Groq with a 512-token output
budget. Model availability and account limits can change. Network and API errors
are displayed; recognition is not guaranteed to be accurate or instantaneous.

### Example

Write this using a stacked fraction, a radical, and a superscript:

```latex
x = \frac{-5 + \sqrt{25 + 4y^2}}{2}
```

The upper output is the typeset preview; the field beneath it is editable LaTeX.
Changing the field updates the preview and copied text. Changing ink invalidates
the previous result and requires another recognition request.

Copy LaTeX exports raw text without dollar delimiters. In Notion, create a
**Block equation** and paste into its equation editor. In a LaTeX document, paste
into a math environment. Chat rendering depends on the destination application.
Copying the visual equation as an image is not implemented.

## Privacy and dependencies

Drawing and typesetting run locally. Clicking Recognize sends a PNG of the ink
directly to Groq using your account; its terms and data policies apply. Your API
key is stored in macOS Keychain and can be removed in Groq Settings. No shared
developer API key or intermediary server is used. Never commit or share keys.

MathJax 3.2.2 is bundled for offline typesetting under Apache-2.0. Its license is
in `TrackpadCanvas/MathJax-LICENSE.txt` and included in the app bundle.

## Verification and limitations

These are verified checks and implementation limits, not recognition accuracy
or latency benchmarks.

| Evidence | Result | Scope |
| --- | --- | --- |
| Isolated unit suite | **26 passed, 0 failed** | Fresh run on September 6, 2026 |
| Ink-model tests | **10** | Validation, ordering, undo, clear, erasure geometry, serialization |
| Session tests | **7** | Recognition state, errors, corrections, copying, stale results |
| Groq boundary tests | **5** | Simulated API transport, PNG payload, credentials, response validation, limits |
| Input-transition tests | **4** | Positioning, stroke separation, erase-gesture undo, restoring Clear |
| Undo history | **100 edits** | Configured cap, not a memory benchmark |
| Local recognition-model downloads | **0** | Recognition is performed by Groq |
| Bundled renderer JavaScript | **2,108,580 bytes (~2.01 MiB)** | MathJax file only, not total app size |

Verified environment: **Apple silicon (`arm64`), macOS 13.7.7, Xcode 15.2**.
The fresh run used an unsigned unit build to avoid local test-bundle signing
conflicts. It does not validate signed distribution or sandboxed networking.
See the [verification record and measurement protocol](docs/VALIDATION.md).

Manual checks on the author's Mac cover startup, writing, positioning, erasing,
undo, real Groq recognition, editing, preview, and copying. A fraction with a
nested root and a power was successfully recognized during development. This
is a reported example, not an accuracy score from a controlled test set.

**Not yet measured:** recognition p50/p95 latency, exact-expression accuracy,
input-to-display latency, peak memory, installation success on other Macs,
speed versus typing, and repeat-user retention. No FPS, speedup, or percentage
accuracy claim is made.

```sh
xcodebuild -project TrackpadCanvas/TrackpadCanvas.xcodeproj -scheme TrackpadCanvas -destination 'platform=macOS' -only-testing:TrackpadCanvasTests test
```

Drawings/history are not persisted across app restarts. Copy exports LaTeX text,
not an image. Recognition requires internet and a user-supplied Groq key. Older
prototype files remain in the repository but are not the active composer UI.

## Architecture

```text
Trackpad touch events
        ↓
ComposerCanvasView → normalized InkDocument + undo snapshots
        ↓
ComposerSession → recognition state + document revision checks
        ↓ explicit Recognize action
InkPNGRenderer → URLSession → Groq → validated LaTeX
        ↓
Editable LaTeX → bundled MathJax / WKWebView → preview
        ↓
macOS clipboard → destination equation editor
```

| Component | Responsibility |
| --- | --- |
| [InkModels.swift](TrackpadCanvas/InkModels.swift) | Normalized ink data, validation, geometry, serialization |
| [ComposerCanvasView.swift](TrackpadCanvas/ComposerCanvasView.swift) | Touch capture, positioning, rendering, erasing, undo |
| [ComposerFeature.swift](TrackpadCanvas/ComposerFeature.swift) | Keychain, PNG encoding, API transport, session state, clipboard |
| [AppShell.swift](TrackpadCanvas/AppShell.swift) | Panel, shortcuts, settings, editable result and preview |
| [AppDelegate.swift](TrackpadCanvas/TrackpadCanvas/AppDelegate.swift) | Explicit application lifecycle, editing menus, status item |

### Design decisions

- **Explicit input modes:** Space and E determine how touch samples affect ink.
  Space takes priority, and transitions prevent unintended connecting strokes.
- **Gesture-level undo:** erasing records a snapshot before its first removal;
  one undo restores the gesture instead of reversing individual touch samples.
- **Swept erasing:** intermediate samples along finger movement help detect
  strokes crossed between events, rather than checking only the latest position.
- **Stale-result protection:** revision checks discard recognition responses
  when the drawing changed while the request was running.
- **Testable recognition boundary:** `RecognitionService` separates session
  behavior from provider transport. Automated tests use simulated responses.
- **Local typesetting:** LaTeX is passed as serialized data to a bundled renderer
  in a nonpersistent web view with a restrictive content policy.

Free Touch integrates an existing vision model; it does not train or supply a
new recognition model. Development used AI coding assistance and iterative
manual testing.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Window missing | Use the menu-bar icon or Control–Option–M; stop any old process before rebuilding |
| Global shortcut unavailable | Another app may own it; use the menu-bar menu |
| API key rejected | Replace the key in Groq Settings and check the account |
| DNS / sandbox connection failure | Build with the committed outgoing-network entitlement |
| Model unavailable / 404 | Read the provider error and check current model availability |
| Request too large / 429 | Compare requested tokens with account limits; this can occur without exhausting a daily quota |
| Usage limit reached | Read the dialog and any retry interval; avoid repeated clicking |
| Incomplete equation | Check handwriting or simplify the expression; truncated responses are rejected |
| Plain text after paste | Paste into a destination equation editor |

The current request timeout is 30 seconds and maximum output budget is 512
tokens. These are settings, not measured response times. Long expressions may
exceed the output budget. Check [Groq's current vision documentation](https://console.groq.com/docs/vision)
and [your account limits](https://console.groq.com/settings/limits) for changes.

## Contributions and feedback

Useful contributions include fresh-Mac installation feedback, input edge cases,
reproducible recognition failures, accessibility improvements, and packaging.
For an issue, include macOS version, Mac/trackpad type, reproduction steps, and
expected versus actual behavior. For recognition failures, include a
non-sensitive sample and expected LaTeX. Remove API keys and account identifiers.

If Free Touch is useful, a GitHub star helps others discover it. Reports from
real workflows are especially valuable while the project is a prototype.

## Distribution plan

Publish a versioned macOS app ZIP or DMG through GitHub Releases after Developer
ID signing, Apple notarization, and a fresh-Mac installation test. The repository
is currently for building from source; no notarized binary is claimed.

## Project license

Original project code and documentation are licensed under [MIT](LICENSE).
Bundled MathJax 3.2.2 retains its [Apache-2.0 license](TrackpadCanvas/MathJax-LICENSE.txt)
and is not relicensed under MIT. Groq and its hosted models are governed by their
respective service and model terms.
