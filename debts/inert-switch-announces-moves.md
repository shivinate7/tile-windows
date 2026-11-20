# An inert switch says it moves windows

Decision: scene triggers (`triggers`). Found at d2ee88e. Recorded 2026-11-20 16:39 CST. Line numbers are at d2ee88e.

Turning an inert switch On shows "It moves windows without asking once you Save." (app.html:3302) while the row reads "On, inactive". The message has no inert check. The text is the same on main.

Harm: the row says the switch is inactive, and the message says it moves windows.

Likelihood: unmeasured.

Recovery: none in the code.

Fix: show the inactive text, not the move warning, when the switch is inert. Write a red case first: turn an inert switch On and read the message.
