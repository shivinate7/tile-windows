# Fill controls

Kind: build
Plan: docs/design/mockups/board-feedback-notes.md#fill-controls (windows)

**Question.** How does the owner clear the board to sort windows by hand, when fill refills every freed cell?

**Ruling (owner, 2026-11-11 16:16 CST).** Build both.
- "Fill Empty Cells" is a switch per scene in the inspector. On keeps today's behaviour. Off places only locked windows, and every other window stays put.
- "Clear Board" is an action. It sends every unlocked window to Windows That Stay Put and turns the switch off.

The look follows the designer's pick in `docs/design/mockups/board-feedback-notes.md`.

**Why.** When the owner sent a window to Windows That Stay Put, the next window in fill order took its cell at once, so the board could never be cleared for sorting (owner feedback, 16:10 CST).
