# A test file run directly leaves headless Edge running

Decision: none (test harness). Found at d2ee88e. Recorded 2026-11-20 16:39 CST. Line numbers are at d2ee88e.

The suite puts each test child in a job object, so stopping the suite ends its processes (test/run.ps1:39, :69). A test file run directly, and killed hard, has no job object. Its headless Edge stays and holds files and ports for the next run. Teardown has left headless Edge running after a test-author run, nine processes once.

Harm: the next run finds its files and ports held.

Likelihood: measured once, nine processes left after one test-author run. Otherwise unmeasured.

Recovery: none in the code. A stray headless Edge is stopped by hand.

Fix: give a directly run test file its own job object, or stop its Edge on exit. Write a red case first: kill a test file run directly, then count the msedge processes left.
