# Fill controls

Kind: build
Plan: docs/design/mockups/board-feedback-notes.md#fill-controls (windows)

**Question.** How does the owner clear the board to sort windows by hand, when fill refills every freed cell?

**Ruling (owner, 2026-11-11 16:16 CST; every option in the board-feedback mockup approved as an improvement, not an alternative, 16:31 CST).** Build both.
- "Fill Empty Cells" is a switch per scene in the inspector. On keeps today's behaviour. Off places only pinned windows, locked or not, and every other window goes to Windows That Stay Put. With the switch off, zones pause too, and their outlines stay on the board.
- "Clear Board" is an action. It turns the switch off. Each unpinned window then shows in Windows That Stay Put with the reason "Fill is off". Clear Board keeps no list of the windows it cleared, so turning the switch back on refills the board.

The look is in `docs/design/mockups/board-feedback-notes.md` (Fill controls).

**Why.** When the owner sent a window to Windows That Stay Put, the next window in fill order took its cell at once, so the board could never be cleared for sorting (owner feedback, 16:10 CST).
