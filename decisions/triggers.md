# Scene triggers

**Question.** Which triggers apply scenes on their own?

**Ruling (2026-10-22, owner, after an interview over 16 researched ideas).** Every trigger can be turned off per scene. The owner tests each one and disables any they dislike.

Build:
- **Schedules.** The schedule trigger exists. Add a guard: skip a scheduled apply during a call.
- **Return to the desk.** After an unlock that follows a lock of 5+ minutes, re-apply the active scene. The first unlock of the day applies Default. Also after 10+ minutes idle without a lock, once input resumes.
- **New window finds its place.** When a window of a scene app appears and holds for 3 s, re-flow the active scene. Never within 10 s of a manual move or while a mouse button is down. Skip windows under 400×300.
- **Activity snap.** When the owner works in one kind of app for about a minute (for example Claude, Procore or NetSuite in Chrome, PowerPoint or Excel) and the layout does not suit it, snap to the scene that does. Replaces the narrower "deck means Review" and "Procore means Approvals" ideas.
- **Meeting size picks the call scene.** A weekday-morning Claude scheduled task writes today's meetings (start, end, attendee count, Teams or not) to a file in the app folder. A call with 25+ attendees applies a "Listen" scene; smaller calls apply Meetings.
- **Focus in gaps.** When the next busy meeting is 60+ minutes away and the owner touched the PC in the last 2 minutes, apply Focus.
- **Before a meeting, offer.** 2 minutes before a busy Teams meeting, show a toast that offers to arrange. It moves nothing unless clicked.
- **A scene per monitor set.** Pick the display scene whose monitor set matches. Laptop only means a new "Solo" scene.
- **No external monitor for 30 s.** Apply the laptop scene. Replaces the power-unplugged idea.
- **Thursday prep.** Thursday 14:30 applies a governance-prep scene (Procore in Chrome, Outlook).
- **Grid follows the Claude count.** 4+ Claude windows means the denser ultrawide grid; 3 or fewer means a roomier one. Owner tests it.

Measure first: **Screen share means Present.** During the owner's next real share, read the window list once (no moves) to find the signal. Build only after that.

No: an end-of-day "Wrap" scene at 16:00.

Deferred: bring a Claude window forward when its session waits on the owner. It needs a hook in claude-settings.

**Why.** Grounded in a read-only study of the owner's calendar, sent-mail times, Chrome history (domains only), Claude sessions and open windows on 2026-10-22.
