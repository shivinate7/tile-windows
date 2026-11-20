# The test sweep loses a locked folder's unlocked files

Decision: none. Found in the test sweep review (PR 88, the locked-file sweep, later review round). The fault predates PR 88. Recorded 2026-11-20 13:13 CST.

When a test run folder holds a file that another process has open, the sweep does not keep the folder whole. It deletes the unlocked files and keeps the locked one. The comment in test/run-folders.ps1 says the folder "is skipped", which is not what the code does.

Harm: a test scratch folder is left partly deleted, with only its locked file kept.

Likelihood: unmeasured. Each test run starts this sweep.

Recovery: unmeasured. The review did not check how the next sweep treats the kept folder.

Fix: make the sweep skip a folder that holds a locked file, as test/run-folders.ps1 says. Write a red case first: a folder with one locked file and one unlocked file keeps both.
