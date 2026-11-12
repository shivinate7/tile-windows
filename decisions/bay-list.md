# Bay list

Kind: build
Plan: docs/design/mockups/bay-columns-notes.md#options (windows)
Plan: docs/design/mockups/bay-columns-notes.md#options (windows), Reason Said Once (item 4)

**Question.** How does the Windows That Stay Put list use its width, and how does it show why each window stays put?

**Ruling (owner, 2026-11-12 11:14 CST; Reason Said Once approved, 12:05 CST).**
- Flowing Columns: the list packs down, then across, into as many columns as fit. A column that opens partway through a category starts with a rule in that category's colour, and no column is left with one window of a category.
- Reason Said Once: a reason that every window in a group shares, such as "Fill is off", shows once for the group instead of under each window. A window whose reason differs, such as "Minimized", keeps its own line.

Flowing Columns is the pick (notes option 1). Category Blocks (option 2) is not chosen. Show N More (option 3) is unchanged. Reason Said Once is notes item 4. The look is in `docs/design/mockups/bay-columns-notes.md`, drawn in `docs/design/mockups/bay-columns.html`.

Departs from: main's one column per category (`app.html` line 287) and the reason under each chip (`renderBay()`).

Open, for the owner:
- Group = a category; shared = the reason more than half of the windows the list shows share, so in the capped "Show N More" state only the visible windows count; on by default (coordinator picks, 2026-11-12 13:45 CST and 14:06 CST, pending owner confirm). A window with no reason line ("Not in this scene") counts as not sharing and shows as on main. The shared reason sits on the heading's own row after the category name, so a heading is one row tall.
- The gains quoted in notes item 4 (271px at 1440, 390px at 1024) were for the "more than half" rule. The ruling's rule is unmeasured.

**Why.** The list used three narrow columns and left most of its width empty, and the same reason repeated under almost every window.
