# The second install rename has no retry

Decision: none (install). Found at d2ee88e. Recorded 2026-11-20 16:39 CST. Line numbers are at d2ee88e.

The swap retries its first rename for about 15 s when a process holds the app folder (install.ps1:48-54). The second rename, app.new to app, has no retry (install.ps1:60). A brief antivirus handle fails the install, and the rollback runs (install.ps1:61-63). A failed rollback leaves app.new with no app. No test covers it.

Harm: the install fails, and a failed rollback leaves the app missing.

Likelihood: unmeasured.

Recovery: none in the code. The app folder is restored by hand.

Fix: retry the second rename as the first one does. Write a red case first: hold app.new for a few seconds, run the install, and expect exit 0.
