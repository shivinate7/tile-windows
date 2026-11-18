# No test checks what the setup strip's Refresh does

Decision: monitor setups. Recorded 2026-11-17 19:43 CST.

The strip's Refresh (`srefresh`) has no test of its effect. The 409 case in `test/setup-page.ps1` presses the strip's button (Refresh, in that case) and checks only that no save goes under the old key. Its comment still says Try Again. No test covers the same-key resend, `goneIds`, or `smapHTML`.
