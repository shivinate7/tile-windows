# Inert Trigger Switch: design notes

Mockup: `inert-trigger-switch.html`, beside this file. Debt `inert-trigger-switch` (found in the
triggers review, round 3, 2026-10-22; decision `triggers`). Designer kind: informed.

A trigger switch can be On where it does nothing, such as "Use This Scene for Calls of Its Size"
on a scene that is not Listen or Meetings. Only a note under the switch says so. The rail chip
looks like a working one and the rail count includes it.

Deep links: `#s=<item>`, plus `t=light|dark`, `hide=<option,...>` and `labels=0` (hides the Today and
New labels). With no `t`, the page follows the system theme. Items for `s`: `chips`, `switch`,
`counts`, `only`, `f1440`, `f1024`, `all`. Option keys for `hide`: `plain`, `strike`, `dim`,
`quiet`, `working`. Each option has a checkbox on the page that hides it.

Sizes: `layout.py devices` gives no device list for this repo, so the sizes are the brief's: 1440
wide (rail 232 px, inspector 268 px) and 1024 wide (below 1180 px the scenes are a strip of 176 px
cards over the board, inspector 252 px; `app.html` `@media (max-width:1180px)`). Themes: light and
dark, from the app's own tokens. The page shell and every product rule it draws are copied from
`app.html`; only `.inert` and `.xstate` are new.

Focus ids for the waiting page: `chip-tag`, `chip-plain`, `chip-strike`, `sw-inert`, `sw-dim`,
`count-sentence`, `count-quiet`, `xsum-on`, `xsum-working`, `only-chip`.

## What "inert" is

`needNote(f, s)` in `app.html` already knows three cases where an On switch does nothing:
- `setup` with no `setupKey` ("Pick a setup, or this does nothing.").
- `size` or `offer` on a scene that is neither `meetingSize.big` nor `meetingSize.small`.
- `activity` when no entry of `cfg.activity` points at the scene.

The mockup treats exactly these as inert. Today they show a note and nothing else. A switch in a
working state with a conflict note (`conflictNote`: "Also used by ..., first in the rail wins") is
not inert and is not drawn.

## Choices

1. **The inert chip: a dashed tag with its reason** (picked; `#s=chips`, focus `chip-tag`). The
   chip takes a row of its own in the rail card: a triangle (the app's `WARN` mark), the chip's name
   in semibold, and a second line with the reason ("Not a call scene", "No setup picked", "No app
   maps here"). Amber fill (`--hi-bg`) and a dashed ink edge. A working chip is untouched.
   Gain: it reads as different at a glance, in shape, mark and words, and not by colour alone; the
   reason is on the card. Lose: the card grows by one line (about 17 px) in each scene with an inert
   chip, and one card in the strip is taller than its neighbours' content. Pick: yes.
   Departs from: `app.html` `renderRail` draws every chip as the same `<i>`. Not blocking.
2. **The three reasons** (`#s=chips`). Short words, one per case of `needNote`: "Not a call scene"
   (size and offer), "No setup picked" (setup), "No app maps here" (activity). The long sentence
   stays in the inspector, unchanged. Chip names keep Title Case and the reasons are status lines in sentence
   case (decision `button-case`). Gain: a chip stays short in a 176 px card. Lose: "call scene"
   is a new word for Listen and Meetings. Pick: yes. A builder may reword it.
3. **Mark only** (option `plain`, focus `chip-plain`). The pill shape stays; a triangle and the dashed
   edge mark it. The reason is the hover title and hidden text. Gain: no taller card. Lose: a touch
   screen has no hover title, so the reason is only in the inspector. Pick: no.
4. **Struck through** (option `strike`, focus `chip-strike`). Muted text, a line through the name, a
   dotted edge, no triangle. Gain: reads as dead at once. Lose: reads as removed more than as On;
   no reason shown; a strike through 11 px text is the hardest chip to read. Pick: no.
5. **The inspector switch: dashed amber track, "On, inactive" line** (picked; `#s=switch`, focus
   `sw-inert`). A checked inert switch gets an amber track with a dashed ink edge and a smaller
   ink knob at the On end. Under the hint a line with a triangle says "On, inactive" (uppercase 11 px,
   the style of the `On` label). That line replaces the word On at the right of the row. The amber
   note under the row is unchanged and still the reason. Gain: the switch itself shows the state, as
   the debt asks. Lose: the status sits under the hint, where the working row has On at the right.
   Pick: yes.
   Departs from: `app.html` `autoUI` puts `On` at the right of every On row. At the right,
   "On, inactive" needs about 62 px and squeezes the title to three lines in the 268 px inspector.
   Not blocking.
6. **Dimmed row** (option `dim`, focus `sw-dim`). The whole row at about half strength, the track
   unchanged. Gain: reads as disabled. Lose: the switch is not disabled; the title and hint lose
   contrast; on a Setup row it also fades the picker, which is the way out. Pick: no.
7. **The rail count counts working triggers only** (picked; `#s=counts`, focus `count-sentence`).
   "4 of 6 scenes have triggers on. The tray agent runs them." A second sentence says how many scenes
   hold a switch that does nothing: "2 scenes have a switch that does nothing." Where no scene has a
   working trigger it reads "No scene has a trigger on yet. Open a scene to switch one on." and
   still adds the second sentence. Gain: the count is what the tray will do. Lose: one more sentence
   in a 208 px column (three lines at 1440). Pick: yes.
   Departs from: `app.html` `hasAny` counts any On extra switch, and `renderRail` takes its count
   from it. Not blocking.
8. **No rail sentence** (option `quiet`, focus `count-quiet`). Only the corrected count. Gain: one
   line less. Lose: a scene with only an inert switch is just missing from the count and only its
   chip says why. Pick: no.
9. **The inspector's Extra Triggers line counts On switches and adds the inactive ones** (picked;
   focus `xsum-on`). "2 on · triangle 1 inactive" in place of "2 on · triangle 1 warning". A conflict note
   (`conflictNote`, "Also used by ..., first in the rail wins") still counts as a warning, so the line can read
   "2 on · triangle 1 inactive · triangle 1 warning", each part shown only when it is not zero. The mockup
   draws only the inactive part. Gain: the person is looking at switches, and two switches show On. Lose:
   this line and the rail count differ on purpose (switches here, working triggers there). Pick: yes.
   Departs from: `app.html` `xSummary` counts every switch and calls every note a "warning". Not
   blocking.
10. **The line counts only working switches** (option `working`, focus `xsum-working`). "1 on ·
    triangle 1 inactive", the same measure as the rail. Gain: one measure. Lose: two switches read On
    and the line says 1. Pick: no.
11. **A scene whose only switch is inert** (`#s=only`, focus `only-chip`). Its card has the dashed
    chip and is not counted. The inspector callout is no longer the amber "Triggers that are on move
    your windows without asking". It reads "No working trigger is on, so this scene changes your
    windows only when you apply it." Gain: the callout is true. Lose: none seen. Pick: yes.
    Departs from: `app.html` `renderInsp` picks the callout from `hasAny`, which counts an inert
    switch. Not blocking.

## For the builder (outside the design folder)

- One home for "inert": split a predicate out of `needNote` (the same three cases) and have
  `hasAny`, `chipsOf`, `xSummary`, `autoUI` and the callout read it. `needNote` keeps the sentences.
- The chip reason words and the "On, inactive" line need text for a screen reader: the mockup uses
  hidden "Warning: " text, as `warnNote` does.
- The inert track and chip have forced-colours rules in the mockup (`CanvasText`, `ButtonText`).
- A `test/run.ps1` case: a scene with an inert switch is not counted by the rail line, and its chip
  carries the inert class.
- `test/setup-page.ps1`'s Shard-Init pin is untouched by this mockup. A builder who adds gates there
  updates it.

## Not drawn

- A switch that loses a tie ("Also used by ..., first in the rail wins") also does nothing, and it
  reads only as a note. The debt names the three `needNote` cases, so it is left out. It could take
  the same chip with the reason "Loses to <scene>". Not blocking.
- A scene's main trigger (schedule, monitors, call) has no inert case in `app.html` today.
