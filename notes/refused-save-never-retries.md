# A refused save never retries, but Follow Again says to try again

Decision: monitor setups. Recorded 2026-11-17 22:14 CST.

After an earlier save is refused (409), `flushSave` returns false, and `followAgain` says "Try again after it saves". That save never retries until Refresh. A refused save offers Refresh and no retry, by design (`renderSetbar`), so the message promises a save that will not run.
