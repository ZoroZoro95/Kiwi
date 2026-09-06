# Verification record

## Recorded run

- Date: September 6, 2026.
- Application source revision: `28ba6d8`; this update changes documentation/license only.
- Environment: macOS 13.7.7 (22H722), arm64, Xcode 15.2 (15C500b).
- Suite: `TrackpadCanvasTests` only.
- Result: **26 passed, 0 failed**, command exit status 0.
- Test source: [TrackpadCanvasTests.swift](../TrackpadCanvas/TrackpadCanvasTests/TrackpadCanvasTests.swift).
- Automated provider requests use simulated responses, not live inference.

Reproduce the unsigned unit-test route from the repository root:

```sh
xcodebuild -project TrackpadCanvas/TrackpadCanvas.xcodeproj \
  -scheme TrackpadCanvas -destination 'platform=macOS' \
  -derivedDataPath /tmp/free-touch-unit-tests \
  -only-testing:TrackpadCanvasTests test CODE_SIGNING_ALLOWED=NO
```

A passing unsigned run does not demonstrate that a signed app has correct
entitlements, accesses Keychain successfully, or passes Gatekeeper on another
Mac. Test those separately using a signed application. Xcode prints a local
`.xcresult` location; preserve it when sharing test results.

## Test inventory

| Area | Count | Assertions covered |
| --- | ---: | --- |
| Ink model | 10 | Finite values/clamping; ordering; empty strokes; undo; clear; point, segment, boundary erasure; document/draft serialization |
| Session | 7 | Empty state; recognition/copy; edit invalidation; failure preserves ink; whitespace rejection; stale response discard; corrected clipboard/blank-copy prevention |
| Groq boundary | 5 | PNG request/output budget; missing key; rate limits; malformed/truncated output; retry detail/key redaction |
| Canvas transitions | 4 | Space separates strokes; positioning leaves no ink; erase gesture restores strokes; Clear restoration/no-op erasing |

These count test functions, not independent user scenarios or code coverage.
Some tests assert several behaviors. No coverage percentage is claimed.

## Manual development evidence

The author confirmed startup, free-glide drawing, positioning, erasing, undo,
real recognition, editable LaTeX, preview, and copying on their Mac. Erasing and
undo were accepted on September 6, 2026.

Reported successful recognitions included `x^{2}+5x=15` and
`x = \frac{-5 + \sqrt{25 + 4y^2}}{2}`. These were not collected under a controlled
protocol and do not establish an accuracy rate. Key persistence across restarts,
multi-display behavior, and fresh-machine installation require explicit release
checks. Unit-test execution time is not recognition or visible drawing latency.

## Release checklist

- [ ] Install a signed/notarized release on another Mac without Xcode.
- [ ] Verify opening, closing, reopening, and shortcut-conflict behavior.
- [ ] Verify pointer restoration after Escape, focus loss, and quitting capture.
- [ ] Verify key save, replacement, restart persistence, and removal.
- [ ] Test offline behavior, invalid credentials, limits, and unavailable models.
- [ ] Confirm failure preserves ink and stale results do not replace new work.
- [ ] Check powers, fractions, roots, and long expressions in the preview.
- [ ] Paste into a real destination equation block and inspect the result.
- [ ] Test internal/external trackpads, resizing, and multiple displays.
- [ ] Check keyboard navigation and accessibility labels.

## Protocol for future measurements

This is a proposed study, not completed work. Publish observations before adding
performance or accuracy claims to the README.

1. Collect at least 50 consented expressions from at least 5 writers, spanning
   simple algebra, fractions, roots, scripts, and integrals. Retain failures.
2. Freeze app revision, model ID, prompt, output budget, image dimensions,
   machine details, and date. Provider/model changes require a new run.
3. Record reference/predicted LaTeX, correctness before correction, error category,
   and correction count/time. Review mathematical equivalence separately from
   exact string matching; harmless spacing is not a mathematical error.
4. Measure Recognize-to-result time with a monotonic clock. Separate first-use
   and subsequent timings. Report median and p95, sample count, failed requests,
   timeouts, and rate-limit events. Include rendering if claiming time to preview.
5. Measure ink latency separately using event-to-presentation instrumentation
   or appropriate high-frame-rate recording. Do not substitute unit-test timings.
6. Compare complete task time against participants' usual methods, including
   setup, writing, recognition, correction, and paste. Counterbalance task order
   and record LaTeX familiarity to account for practice effects.
7. Report distributions and limitations. A small convenience sample is
   exploratory, not proof of universal speed or usability advantages.

Suggested per-request fields:

```text
sample_id, writer_id, app_revision, model_id, test_date, expression_category,
reference_latex, predicted_latex, mathematically_correct, elapsed_ms,
request_outcome, error_category, correction_count, correction_ms
```

Do not put API keys or private account identifiers in benchmark artifacts.
