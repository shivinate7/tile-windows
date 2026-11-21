# Layout cases measure in Segoe UI, not Sora

Decision: none (test harness). Found at f55111d. Recorded 2026-11-20 21:42 CST. Line numbers are at f55111d.

app.html:10 loads Sora from Google Fonts. test/setup-page.ps1:431 starts headless Edge with a host-resolver rule that maps fonts.googleapis.com to 0.0.0.0, so the page falls back to Segoe UI, which is narrower than Sora. A layout case therefore measures a line that wraps in Sora as one line. A phone-width bar case passed while the real page wrapped (PR 111, round 2).

Harm: a layout case passes on a page that wraps for the user.

Likelihood: unmeasured.

Recovery: none in the code. The owner checks the page in a browser with the font loaded.

Fix: let the test page load Sora, then measure. Write a red case first: the phone-width bar case, with the font loaded, on the page that wraps.
