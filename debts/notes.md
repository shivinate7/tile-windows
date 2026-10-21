# Notes

Low findings from the sandbox rebuild review (round 3). Each becomes a debt only after a real incident.

- `sandbox.html` Undo-with-no-Apply test cannot go red: two guards each stop it, and removing both throws before any post. It documents the behaviour; `load()` resetting `sent` is what protects it.
- `sandbox.html` `/apply` fetch has no timeout. A hung server keeps the page locked; Quit still works.
- `sandbox.html` A Refresh still in flight when Apply starts can call `load()` mid-POST and leave `sent` stale.
- `serve.ps1` Port probe then rebind can race another process; `Start()` then throws a clear error.
- Untested: Apply moving a real window; stopping the server with Ctrl+C.
