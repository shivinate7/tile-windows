# Direct runs of server and tray test files have no kill-on-close job

Decision: none (test harness). Found at f55111d. Recorded 2026-11-20 21:42 CST. Line numbers are at f55111d.

test/direct-run-job.ps1 gives a file that starts headless Edge its own kill-on-close job, and test/direct-run.ps1 checks that each such file calls `Enter-DirectRunJob`. Five test files start servers or the tray and do not call it: test/install-swap.ps1, test/setup-plumbing.ps1, test/fresh-screens.ps1, test/triggers.ps1 and test/safe-moves.ps1. Killed hard, a direct run of one of them leaves its servers or tray process running, holding files and ports for the next run.

Harm: the next run finds the files and ports held.

Likelihood: unmeasured.

Recovery: the user ends the leftover process by hand.

Fix: give each of the five the job, and widen the check in test/direct-run.ps1 to them. Write a red case first: a file that starts a server without the call fails the check.
