# Setup Added Notice: design notes

Mockup: `setup-added-notice.html`, beside this file. Task: coordinator brief, 2026-11-23, under
decision `run-undo` (owner, 2026-11-23 13:07 CST). Coordinator pick: the button is "Don't add this
setup", and it remembers the no. Debt: `plug-in-adds-setup-no-undo`. Words: `run-undo-notes.md`,
section "Config notices: wording".

Deep links: `#s=<state>`, plus `t=light|dark`, `hide=<option,...>` and `labels=0`. States:
`today`, `toast`, `toast-quiet`, `toast-rename`, `cases`, `declined`, `declined-plain`,
`stale-layout`, `stale-gone`, `board-none`, `board-note`. Option keys for `hide`: `popup`,
`quietadd`, `rename`, `addback`, `nobutton`, `boardquiet`, `boardnote`.

Focus ids: `today-strip`, `setup-toast`, `setup-quiet`, `setup-rename`, `declined-addback`,
`declined-plain`, `stale-layout`, `stale-gone`, `board-none`, `board-note`.

Size: no device list for this repo (`layout.py devices`), so the brief's size: a 364 px pop-up and
a 380 px centre at 100 % scale, as `run-undo.html`. The board frame is 600 px, drawn from
`app.html`'s tokens and its `.toast.warn`.

What happens today: the board reads the snapshot on load and on Refresh. `Add-SnapshotSetup`
(serve.ps1) calls `Register-TileSetup` (config.ps1) under the lock and saves. It adds each monitor
the config does not know, named by shape, and the setup they make, named by its monitors
("Laptop + Portrait"; the first is "Desk"). No note. The strip then says the scene "follows" the
closest setup (`app.html`, the strip's `follows` line). The tray never registers a setup, so this
act happens only while you are on the board.

## Choices

1. **A toast when a read adds a setup.** Title "`<setup>` setup added". Body: what the board does
   with it ("Scenes follow Desk on it until you change them", from `Get-SetupFollows`). A detail
   line names a monitor that is new to the app. Gain: the act is no longer silent. Loss: a toast
   while you are already on the board. Pick: yes.
2. **No toast for the first setup.** The first setup ever (Desk) is what the board needs to work,
   and audit row 12 of `run-undo` gives a first run no Undo. It also keeps a bad-file reset, which
   empties `setups`, from showing a second toast. Pick: yes.
3. **Pop-up or centre only.**
   - Pop-Up (option `popup`): as a run toast. Gain: you see it. Pick: yes.
   - Centre Only (option `quietadd`): `SuppressPopup`, since you are on the board. Loss: easy to
     miss, which is close to today's silence.
4. **Don't Add This Setup.** Removes the setup and each monitor that this add made (a monitor in
   another setup stays), and adds the setup's key to a declined list, so the next read does not add
   it again. Leaves every layout alone (the debt's fix line). Gain: one press undoes the act.
   Loss: the board autosaves each edit (`run-undo` audit row 3) through `Save-SceneLayout`, which
   registers the setup. You are on the board when this toast shows, so your next board change on
   these monitors adds the setup back with no word, and the no is gone (choice 7). Pick: yes
   (coordinator).
   Departs from: `Forget-Known` (serve.ps1) refuses to forget the setup in use (409). This button
   removes the setup in use, because nothing has been built on it yet (choice 6). Not blocking.
5. **The answer, and the way back** (rule `ux-no-dead-end`). The toast updates in place.
   - Add It Back Button (option `addback`): the updated toast has Add It Back, which clears the
     no and adds the setup again. Gain: one press reverses it. Pick: yes.
   - No Button After (option `nobutton`): the body says "You can add it in Monitors and Setups."
     Loss: prose that names a place is not a control.
   Either way, Monitors and Setups needs a way to clear a no once the toast is gone, such as a
   "Not added" row with Add. Not drawn. `Owner grant: yes`, since it adds a control to the dialog
   (decision `monitor-setups`, item 13).
6. **Changed since.** If you changed a scene's layout on the setup, or aimed a scene at it, the
   press does nothing and says so, with Open Tile Windows. Gain: your work wins, as run-undo choice
   9. Loss: to remove it you unplug, then Forget it. Pick: yes.
7. **A board edit on a declined setup.** `Save-SceneLayout` registers the setup, and every board
   change autosaves, so "remembers the no" holds only until your next edit on those monitors.
   `Owner grant: yes`, since it decides what the coordinator's "remembers the no" means.
   - Silent Re-Add: the edit adds the setup and clears the no, with no word. Loss: the no seems
     not to stick.
   - Strip Says So: while a declined setup is plugged in, the strip reads "Not added. A board
     change here adds it." Gain: the re-add is your informed act. Pick: yes. Not drawn.
   - Refuse Edits: board changes on a declined setup are refused until Add It Back. Loss: the
     board stops working on those monitors.
8. **Rename button** (option `rename`). Opens the board at Monitors and Setups, on this setup's
   name. A toast button cannot carry typed text (protocol activation). Gain: rename where you meet
   the name. Loss: a second button and a new link verb; a click on the body already opens the
   board. Pick: no.
9. **Its own tag per setup** (`tw-setup-<key hash>`), so a scene run does not replace it. The
   record is on disk, so the button works after a tray restart, until pressed or the setup is
   gone. No timer. Pick: yes.
10. **The board's note.**
    - Toast Only (option `boardquiet`): no board note; the strip already names the setup and what
      the scene follows. Pick: yes.
    - Board Note Too (option `boardnote`): `Add-TileNote` writes the same words with the same
      button. Gain: said where you are looking. Loss: two notices for one act, and a new server
      route for the button.
