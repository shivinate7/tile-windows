# Apply and scene routes answer 200 with an empty body

Decision: run undo (`run-undo`). Found in serve.ps1 at 0961e6d: POST scene (lines 278-282) and POST apply (lines 284-286). Recorded 2026-11-20 01:59 CST. Line numbers are at 0961e6d.

When the engine gives no output, both routes answer 200 with an empty body. PR 63 fixed only the preview route, which answers 500 when the engine gives no answer (serve.ps1:269-276).

The page reads each reply as JSON at app.html:2888 (scene) and app.html:2906 (apply). An empty body fails that parse, so the page shows a JSON parse error under Undo instead of the result.

On a live scene run, the route still writes its log line, which reads "Moved 0 window(s)", because an empty output counts as no placed windows. Checked in PowerShell 5.1: ConvertFrom-Json on an empty string returns nothing and does not throw.

Harm: the user sees a parse error where the apply result should be. A live run that may have moved windows is logged as moving none.

Likelihood: unmeasured. The engine gives no output only when it fails without throwing.

Recovery: Refresh reads the windows again. The log entry stays wrong.

Fix: answer 500 with the engine's error text, or a fixed message, when the output is empty, as the preview route does. Do this on both routes.
