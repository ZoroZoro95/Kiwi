# Free Touch

Write equations on a Mac trackpad without holding a click. Recognize handwriting,
correct the LaTeX, preview the formatted equation, and copy it into your notes.

Native macOS prototype. The Xcode project and executable are still named
`TrackpadCanvas`. No ready-to-install public release is provided yet.

## Run from source

1. Clone this repository and open `TrackpadCanvas/TrackpadCanvas.xcodeproj` in Xcode.
2. Select the TrackpadCanvas scheme and My Mac destination. Select your own
   development team under Signing & Capabilities if required.
3. Run. Free Touch opens and its menu-bar icon provides Open and Quit commands.

Requires macOS 13.7 or newer and a compatible trackpad. Development/testing has
been on Apple silicon; Intel and external trackpad behavior remain unverified.

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

## Privacy and dependencies

Drawing and typesetting run locally. Clicking Recognize sends a PNG of the ink
directly to Groq using your account; its terms and data policies apply. Your API
key is stored in macOS Keychain and can be removed in Groq Settings. No shared
developer API key or intermediary server is used. Never commit or share keys.

MathJax 3.2.2 is bundled for offline typesetting under Apache-2.0. Its license is
in `TrackpadCanvas/MathJax-LICENSE.txt` and included in the app bundle.

## Verification and limitations

26 isolated unit tests passed during development. Manual checks on the author's
Mac cover startup, writing, positioning, erasing, undo, recognition, editing,
preview, and copying. This is not broad hardware or accuracy validation.

```sh
xcodebuild -project TrackpadCanvas/TrackpadCanvas.xcodeproj -scheme TrackpadCanvas -destination 'platform=macOS' -only-testing:TrackpadCanvasTests test
```

Drawings/history are not persisted across app restarts. Copy exports LaTeX text,
not an image. Recognition requires internet and a user-supplied Groq key. Older
prototype files remain in the repository but are not the active composer UI.

## Distribution plan

Publish a versioned macOS app ZIP or DMG through GitHub Releases after Developer
ID signing, Apple notarization, and a fresh-Mac installation test. The repository
is currently for building from source; no notarized binary is claimed.

## Project license

A project-wide open-source license has not yet been selected. Public source
visibility is not a substitute for an explicit license. The bundled MathJax
component retains its own Apache-2.0 license.
