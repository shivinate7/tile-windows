# Clearing the board refills at once

Decision: fill-controls (Fill controls). Owner report, 2026-11-11 16:10 CST. Recorded 2026-11-18 11:15 CST. Not yet checked against main 9e6ae0a; a later lane verifies before it builds.

Taking a tile off the page into Windows That Stay Put (the owner's "dock") makes fill put the next window in fill order into that cell at once. The owner can never clear the page, so they cannot pile windows in Windows That Stay Put and sort them by hand.

Ruled fix: fill-controls (owner, 2026-11-11 16:16 CST) adds a "Fill Empty Cells" switch per scene. Off holds every window where it is. "Clear Board" turns the switch off. Whether main has either is unchecked.
