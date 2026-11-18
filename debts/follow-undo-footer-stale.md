# Follow then Undo leaves the footer saying it still follows

Decision: monitor setups. Found in monitor setups review round 3, 2026-11-17 22:14 CST.

After Follow Desk Again, then Undo, the status line (`#msg`, written by `status`) still says "<scene> follows <setup> until you change it", while the strip and the card show the scene's own layout. The Undo follow branch (`$("undo").onclick`, `e.k==="follow"`) never resets the status line that `followAgain` set.

Fix: the Undo follow branch resets the status line, and a test reads it after Follow then Undo.
