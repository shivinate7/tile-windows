# Scene shortcuts and hotkeys

**Asked (2026-10-22, owner).** Apply a favourite scene without opening the app:

- Desktop shortcuts, one per go-to scene, that apply it on double-click.
- Hotkeys for scenes, wired to buttons on the owner's Logitech MX keypad (through Logi Options+, which can bind a button to a key combination or to running a program).

**Notes for the build.** One home: each shortcut and hotkey calls the engine's scene apply (`tile.ps1 -Scene` or the tray agent), never its own layout code. The tray agent could register global hotkeys (RegisterHotKey) so the MX keypad only needs to send a key combination. Apply from a shortcut or hotkey is a user act, so Undo must cover it as it does an Apply in the app.

**Status.** Deferred. Not started.
