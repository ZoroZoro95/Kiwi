# Free Touch 0.1.0 — early testing build

Apple silicon Macs only (M-series), macOS 13.7 or later. Intel is not supported
by this binary. No Xcode or paid account is needed to use the packaged app.

This is an ad-hoc-signed, unnotarized testing build. It does not carry a verified
Apple Developer ID. macOS may block its first launch. Only open a download whose
source you trust; a checksum detects a changed file but does not establish trust
in its publisher. No system-wide security settings need to be disabled.

## Install

1. Quit any running Free Touch / TrackpadCanvas development build.
2. Unzip the download and drag `Free Touch.app` into Applications.
3. Open the app. If macOS blocks it, go to System Settings → Privacy & Security
   and use Open Anyway for this specific app, if offered. Confirm the prompt.
   Wording varies with macOS version. Do not bypass malware warnings or disable
   Gatekeeper globally. If Open Anyway is unavailable, report the exact message.
4. Free Touch should open one window and show a menu-bar icon. There is no Dock
   icon while it runs. Use its menu-bar menu to reopen or quit it.
5. Add your own Groq key using Groq Settings. Create a key at
   https://console.groq.com/keys. Recognition sends your ink directly to Groq.

An ad-hoc rebuild may trigger a Keychain access prompt for a previously saved key.
Keep the old app until you have verified the new build. Drawings do not persist
between app sessions.

## Quick test

- Control–K: start writing; glide a finger without clicking.
- Hold Space: reposition without ink. Release it to begin a separate stroke.
- Hold E: erase whole strokes. Lift the finger to end an eraser gesture.
- Command–Z with the canvas focused: undo; Clear is also undoable.
- Escape: restore normal trackpad/pointer control.
- Recognize: transcribe the ink, check the preview, edit LaTeX if necessary.
- Copy LaTeX: paste into an equation editor, such as a Notion Block equation.
- Control–Option–M: hide or reopen the window.

Please test launching, quitting/reopening, key save/restart, drawing and pointer
restoration on your Mac. Report Mac model, macOS version, and reproduction steps.
Never include an API key in a report.

## Limitations

This first package has no custom app icon or automatic updater. Download a new
release manually to update. Recognition needs internet and is subject to your
Groq account limits. Copy exports LaTeX, not an image. No drawing persistence,
redo, or partial-stroke erasing. Fresh-Mac installation validation is pending.

Project: https://github.com/ZoroZoro95/Kiwi
Project code: MIT. Bundled MathJax: Apache-2.0; both licenses are included.
