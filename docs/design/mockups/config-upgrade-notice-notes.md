# Config Upgrade Notice: design notes

Mockup: `config-upgrade-notice.html`, beside this file. Task: coordinator brief, 2026-11-23, under
decision `run-undo` (owner, 2026-11-23 13:07 CST: every automated act ships a notification with
Undo). Debt: `config-upgrade-no-undo`. Words: `run-undo-notes.md`, section "Config notices:
wording".

Deep links: `#s=<state>`, plus `t=light|dark`, `hide=<option,...>` and `labels=0`. With no `t`,
the page follows the system theme. `#s=all` shows every state. States: `today`, `toast`,
`toast-names`, `cases`, `undone`, `partial`, `inuse`, `gone`, `board-none`, `board-note`. Option
keys for `hide`: `plain`, `nametitle`, `boardquiet`, `boardnote`.

Focus ids: `today-none`, `upgrade-plain`, `upgrade-names`, `undone-clean`, `undone-partial`,
`undone-inuse`, `undone-gone`, `board-none`, `board-note`.

Size: `layout.py devices` gives no device list for this repo, so the toast is drawn as
`run-undo.html` draws it: 100 % display scale, a 364 px pop-up and a 380 px notification centre.
Windows owns the toast's frame and colours and follows its own light or dark theme.

What happens today: `Update-TileConfig` (config.ps1) runs on the first read of a config whose
`version` is below the starters'. It adds each starter scene whose `since` is newer, adds missing
fields, gives each scene an `auto` block with every switch off, and saves. Nothing is shown.

## Choices

1. **A toast when the upgrade added a scene.** An upgrade that adds only fields (with every switch
   off) changes nothing you see, so it gets no toast. Gain: notice only for what you can see.
   Loss: none. Pick: yes.
2. **Title.**
   - Plain Title (option `plain`): "Starter scenes added"; the body names them. Gain: the title
     stays short at any count. Pick: yes.
   - Names in the Title (option `nametitle`): "Review and Listen added", as a run toast names its
     scene. Loss: five names wrap the title onto two lines.
3. **"Their triggers are off."** Says that nothing new runs on its own. True today: each added
   scene's switches start off (`Update-TileConfig`, the `auto` block). Gain: the toast answers
   "will this move my windows?". Loss: one more sentence. Pick: yes.
4. **What Undo removes.** Each added scene that is still exactly as the update added it. The
   pending record keeps each scene as added; "unchanged" means deep-equal to that copy, so a board
   edit, a layout saved on a setup, or a trigger turned on all count as a change. Gain: your edits
   win, as in run-undo choice 9. Loss: an edit you would like thrown away keeps the scene. Pick:
   yes.
5. **A scene on screen now stays.** If you applied an added scene by hand, it is the active scene
   in state.json. Removing it would leave the tray with an active id no scene has. Gain: no broken
   state. Loss: one more partial case. Pick: yes.
6. **Removed scenes do not come back.** The config's `version` stays at the new value, and
   `Update-TileConfig` adds only scenes whose `since` is newer than it. Undo removes scenes only;
   the added fields stay, since they change nothing you see. Pick: yes.
7. **The answer shows in the same toast** (rule `ux-answer-at-press`), as run-undo choice 8: a clean
   Undo updates quietly; a partial one, or "already gone", pops up. Pick: yes.
8. **How long Undo is offered.** Until pressed, or until a later upgrade's toast replaces it (same
   tag). No timer, as run-undo choice 12. The record is on disk, so a tray restart keeps it. Gain:
   an upgrade during an install restart can still be undone. Loss: none. Pick: yes.
9. **Its own tag.** `tw-upgrade`, not the run tag `tw-run`. Otherwise the first scene run after an
   install would replace the upgrade toast before you read it. Pick: yes.
10. **The board's note.**
    - Toast Only (option `boardquiet`): no board note; the scenes show in the list, as today.
      Gain: one notice, one home. Pick: yes.
    - Board Note Too (option `boardnote`): `Add-TileNote` names the scenes, with Undo, until
      dismissed. Gain: seen when the board is open. Loss: two notices for one act; the page's
      Undo needs a server route.

A click on an old toast after a later upgrade replaced it is not drawn. It says the Undo is out
of date, as run-undo choice 10 does for runs.
