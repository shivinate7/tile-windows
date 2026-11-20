# Preview POST has no retry

Decision: none. Found in app.html, function previewRun (line 967), whose POST is at line 969. Recorded 2026-11-20 01:59 CST. Line numbers are at 0961e6d.

previewRun posts once. A dropped connection (fetch throws a TypeError) goes to its catch (lines 974-977). That catch drops the scene's preview and sets the status line to "Preview failed for <scene>: The app server stopped answering". loadAll retries the same error after 0.4, 0.8 and 1.6 s (app.html:885-893, PR 65). previewRun has no such retry.

Harm: a transient server blip shows a failed preview for a scene, though the server is fine. The board stops drawing that scene's preview until the next preview of it.

Likelihood: unmeasured. How often a preview hits a dropped connection is not measured.

Recovery: Refresh, which runs previewAll again (app.html:911-912).

Fix: retry a TypeError in previewRun on the loadAll schedule (LOADWAIT), and do not retry an error-status reply, as loadAll does.
