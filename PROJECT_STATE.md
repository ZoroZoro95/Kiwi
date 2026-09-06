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
- Build and 26 isolated unit tests passed on 2026-09-05.
- Groq request tests use simulated responses, not live inference.

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
Push source to existing GitHub remote ZoroZoro95/Kiwi. Select a project license,
then prepare a signed/notarized GitHub Release and validate on a fresh Mac.
No valid code-signing identity was found in the local check on 2026-09-06.

## Missing / acceptance gate
Broader handwriting accuracy and latency remain unmeasured. Verify the bundled
MathJax 3.2.2 preview displays superscripts and fractions correctly, and editing
LaTeX updates both the preview and clipboard. MathJax license ships in the app.
This is not yet a completed equation MVP.

## Decisions
Cloud recognition with each user's own key; no local model or hosted proxy for V1.
Only an explicit Recognize action sends ink. The settings dialog discloses this.
Model availability and account limits must be checked when diagnosing API errors.
Reference: https://console.groq.com/docs/vision

## Later
General scratchpad and browser version follow the equation MVP. Browser trackpad
capture must be evaluated separately from the native AppKit implementation.
