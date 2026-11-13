# Fill controls

Kind: build
Plan: docs/design/mockups/board-feedback-notes.md#fill-controls (windows)

**Question.** How does the owner clear the board to sort windows by hand, when fill refills every freed cell?

**Ruling (owner, 2026-11-11 16:16 CST; every option in the board-feedback mockup approved as an improvement, not an alternative, 16:31 CST).** Build both.
- "Fill Empty Cells" is a switch per scene in the inspector. On keeps today's behaviour. Off holds every window where it is, without pinning it (owner, 2026-11-12 12:05 CST). The scene keeps a held layout, separate from its pins: each window that the fill or a zone placed keeps its cell while fill is off, and no pin mark shows. A window the fill put on a closed pin's cell (locked or not) is not held. It goes to Windows That Stay Put, unpinned, and the locked pin keeps its lock (decision `stack-and-lock`: nothing is placed over a locked tile, so nothing is held over one). A window taken off the board leaves its cell empty, and a new window goes to Windows That Stay Put. With the switch off, zones pause too, and their outlines stay on the board. Turning it back on clears the held layout, and the fill places windows as usual. Pins the owner set stay as they are.
- "Clear Board" is an action, unchanged (owner, 2026-11-12 12:05 CST). It turns the switch off with nothing held. Each unpinned window then shows in Windows That Stay Put with the reason "Fill is off". Clear Board keeps no list of the windows it cleared, so turning the switch back on refills the board (bundle approval, 2026-11-11 16:31 CST: "all seem approved").

The look is in `docs/design/mockups/board-feedback-notes.md` (Fill controls).

**Why.** When the owner sent a window to Windows That Stay Put, the next window in fill order took its cell at once, so the board could never be cleared for sorting (owner feedback, 16:10 CST). Off must not move windows: when it sent every unpinned window to Windows That Stay Put, wherever it was, the owner lost the layout they had (owner, 2026-11-12 09:57 CST). Pinning every window put a pin mark on every tile, and the owner wants the tiles to look the same (owner, 2026-11-12 12:05 CST).

Open owner review: the Tile Windows Choices page
