# Config Bad File Notice: design notes

Mockup: `config-bad-file-notice.html`, beside this file. Task: coordinator brief, 2026-11-23, under
decision `run-undo` (owner, 2026-11-23 13:07 CST). Coordinator pick: the button is "Show old
file", which opens the .bad file's folder with it selected. Debt: `config-bad-file-no-undo`.
Words: `run-undo-notes.md`, section "Config notices: wording".

Deep links: `#s=<state>`, plus `t=light|dark`, `hide=<option,...>` and `labels=0`. States:
`today`, `toast`, `toast-names`, `cases`, `shown`, `missing`, `board-keep`, `board-btn`. Option
keys for `hide`: `plain`, `filename`, `boardkeep`, `boardbtn`.

Focus ids: `today-note`, `bad-plain`, `bad-names`, `explorer`, `bad-missing`, `board-keep`,
`board-btn`.

Size: no device list for this repo (`layout.py devices`), so the brief's size: a 364 px pop-up and
a 380 px centre at 100 % scale, as `run-undo.html`. The File Explorer window is Windows' own; the
drawing only shows what the press asks for.

What happens today: `Get-TileConfigText` (config.ps1) finds a config.json that does not parse and
calls `Set-TileBad`, which moves it to `config.json.bad` (or `config.json.<time>.bad` when one is
there) and writes a note. The starter scenes load. The board shows the note until dismissed
(`X-Tile-Note`, `noteFrom` in app.html). The tray shows the same words as a balloon only when its
own read found the file (`$TileNote` is per process; tray.ps1, the tick).

## Choices

1. **No Undo.** Undo would put the old file back, and the old file does not parse, so the next
   read would set it aside again and load the starters again. Undo needs a file the app can read;
   only a fix by hand makes one. So the toast offers the file, not an Undo, and says nothing about
   Undo. Gain: no button that cannot work. Loss: recovery stays a hand fix.
   Departs from: the debt's fix line, which copies the .bad file back. The builder rewrites it.
2. **A toast, whichever process found the file.** Through the pending record, so a bad file found
   by the board's server or by `tile.ps1` also reaches the tray. Today only the tray's own read
   shows a balloon. Pick: yes.
3. **Body words.**
   - Plain Words (option `plain`): "Your scenes file could not be read, so it was set aside. Your
     old scenes are still in it." No file name (rule `ux-machine-text-hidden`); Show Old File shows
     it. Pick: yes.
   - File Names (option `filename`): "config.json could not be read. Your old scenes are in
     config.json.bad." Gain: shorter, and the name you need to fix it. Loss: machine text; a time
     in the name makes it long.
4. **Show Old File.** Opens File Explorer at the config folder with the .bad file selected. The
   path comes from the pending record, never from the link. The toast stays as it was. Gain: one
   press to the file you would fix. Pick: yes (coordinator).
5. **The file is gone at the press.** The toast says so in place, with Open Folder (rule
   `ux-no-dead-end`). Pick: yes.
6. **Its own tag** (`tw-bad`), and the record is on disk, so the button works after a tray
   restart. The bad file is most often found at tray start, so the start-up clear must run before
   this toast shows. No timer. Pick: yes.
7. **state.json keeps today's note.** `Set-TileBad` also sets aside a state.json that does not
   parse. It loses only the recent log, so it keeps its note and balloon, with no toast (audit,
   decision `run-undo`). Pick: yes.
8. **The board's note.**
   - Board Note as Today (option `boardkeep`): today's words and Dismiss. The toast and the note
     take their words from one home, `Set-TileBad`. Pick: yes.
   - Show Old File on the Board (option `boardbtn`): the note gains the same button. Loss: a new
     server route that opens File Explorer.
