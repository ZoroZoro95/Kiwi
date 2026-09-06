# TrackpadCanvas

## Goal
Native macOS menu-bar equation composer: free-glide trackpad writing, recognition,
correction, preview, and clipboard export. Open-source distribution is intended.

## Current milestone
Groq recognition manually confirmed by user (x^{2}+5x=15).
Typeset preview and editable LaTeX accepted by user. Hold-Space positioning also
accepted. Undo and hold-E whole-stroke erasing manually accepted on 2026-09-06.
Prior startup, free-glide writing, and heading-layout fixes were manually accepted.

## Completed verification
- Ink model and composer session tests pass.
- Build and 26 isolated unit tests passed again on 2026-09-06 (unsigned unit build).
- Groq request tests use simulated responses, not live inference.
- Persistent-overlay fix: all 27 unit tests passed on 2026-09-06, including
  panel configuration regression coverage. Manual app/Space switching pending.

## Current implementation
- Groq Settings saves/replaces/removes the API key in macOS Keychain.
- Recognize sends a PNG of ink directly to Groq using qwen/qwen3.8-27b.
  Qwen 3.6 quota was exhausted; Scout returned 404 and was confirmed retired for
  free/developer plans on July 17, 2026. Qwen 3.8 works with a 512-token output cap;
  the earlier 1024 cap exceeded this account's 1000 OTPM limit.
- JSON LaTeX responses are parsed; missing credentials, HTTP failures, and
  malformed/truncated responses are reported without removing ink.
- Changes to the document invalidate pending results.
- Result appears as selectable text and can be copied.

## Exact next task
MIT license and detailed README/verification record completed. User authorized
pushing the Free Touch source and documentation to ZoroZoro95/Kiwi on main.
User chose free distribution: an ad-hoc-signed, unnotarized Apple-silicon ZIP.
Packaging script and installation guide are prepared; Release build succeeded.
Next manually test the packaged app before publishing a GitHub prerelease.
The user confirmed the packaged app opens, then reported hiding on app switch.
Disabled panel hide-on-deactivation, enabled all-Spaces overlay and manual
minimizing/restoration. Capture still releases on focus loss and minimization.
Next test the rebuilt ZIP: app switch, desktop/full-screen switch, minimize,
menu-bar restore, and close. Done when visibility follows explicit user actions
and switching apps restores normal pointer control.
No valid Developer ID identity was found in the local check on 2026-09-06.

## Missing / acceptance gate
Broader handwriting accuracy and latency remain unmeasured. Core interaction
and equation workflow passed the author's manual checks. Release validation,
and fresh-machine installation remain outstanding. Notarization is excluded
from this free prerelease; users may encounter Gatekeeper warnings.
MathJax's separate license ships in the app.

## Decisions
Cloud recognition with each user's own key; no local model or hosted proxy for V1.
Only an explicit Recognize action sends ink. The settings dialog discloses this.
Model availability and account limits must be checked when diagnosing API errors.
Reference: https://console.groq.com/docs/vision

## Later
General scratchpad and browser version follow the equation MVP. Browser trackpad
capture must be evaluated separately from the native AppKit implementation.
