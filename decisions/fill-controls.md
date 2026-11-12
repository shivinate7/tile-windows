# Fill controls

Kind: build
Plan: docs/design/mockups/board-feedback-notes.md#fill-controls (windows)

**Question.** How does the owner clear the board to sort windows by hand, when fill refills every freed cell?

**Ruling (owner, 2026-11-11 16:16 CST; every option in the board-feedback mockup approved as an improvement, not an alternative, 16:31 CST).** Build both.
- "Fill Empty Cells" is a switch per scene in the inspector. On keeps today's behaviour. Off leaves every window where it is (owner, 2026-11-12 09:57 CST): each window that the fill or a zone placed is pinned in its current cell at that moment, so nothing moves. A window the fill put on a closed locked pin's cell is the exception: it goes to Windows That Stay Put, unpinned, and the locked pin keeps its lock (decision `stack-and-lock`: nothing is placed over a locked tile). After that, a freed cell stays empty, and a new window goes to Windows That Stay Put. With the switch off, zones pause too, and their outlines stay on the board. Turning it back on fills only empty cells; the pins it added stay, and the owner can unpin them.
- "Clear Board" is an action. It turns the switch off. Each unpinned window then shows in Windows That Stay Put with the reason "Fill is off". Clear Board keeps no list of the windows it cleared, so turning the switch back on refills the board.

The look is in `docs/design/mockups/board-feedback-notes.md` (Fill controls).

**Why.** When the owner sent a window to Windows That Stay Put, the next window in fill order took its cell at once, so the board could never be cleared for sorting (owner feedback, 16:10 CST). Off must not move windows: when it sent every unpinned window to Windows That Stay Put, wherever it was, the owner lost the layout they had (owner, 2026-11-12 09:57 CST).
