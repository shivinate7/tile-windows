# A Free Layout move can save a second pin for one window

Decision: layout free (`layout-free`). Found at f55111d. Recorded 2026-11-20 21:42 CST. Line numbers are at f55111d.

`freeStep` adds a pin when its area has none (app.html:2475), and does not look for a pin the window already has. `freeAssign` adds one only when `pinNow` finds none (app.html:2662-2663). `pinNow` (app.html:1705) reads only the pin that the placed preview shows for the window, so a window whose pin is behind or not placed gets a second one. Both paths are pre-existing on main.

Harm: a saved scene holds two pins for one window. How the engine places that window is unmeasured.

Likelihood: unmeasured.

Recovery: unmeasured.

Fix: make `freeStep` and `freeAssign` look for the window's pins in `x.pins`, not in the placed preview. Write a red case first: a window with a pin that is behind, then a Free Layout move, then check the saved layout holds one pin for the window.
