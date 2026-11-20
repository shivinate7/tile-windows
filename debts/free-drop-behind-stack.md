# A list drop on a stacked free space deletes the stack

Decision: stack and lock (`stack-and-lock`), and layout free (`layout-free`). Found in app.html at 0e99075 (PR 58, the free-layout pull request, review round 3, finding F10). Recorded 2026-11-19 22:34 CST. Line numbers are at 0e99075.

A window dropped from the list onto a Free Layout space takes the space's pin. When the holder's pin has a `behind` stack, `freeAssign` (app.html:2370) removes that pin from the scene (app.html:2377), and the stack goes with it. Only the front window goes to the list (`oc`, same line). The windows behind it leave the layout.

Move To reaches the same code through `freeMoveTo` (app.html:2383).

The grid's `swapInto` (app.html:1645-1650) keeps the stack. It hands `gB.behind` to the new pin.

Undo restores the pin and its stack.

Harm: a stack of windows loses its pin, and the windows behind the front one leave the layout. Only Undo brings them back.

Fix: carry the `behind` stack to the new pin, as `swapInto` does. Write a red case first: a list drop on a space whose pin has a stack keeps every window in that stack.
