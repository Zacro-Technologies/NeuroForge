# Native Mac exit QA — 5 September 2026

A disposable copy of the compiled Debug app uses a unique bundle identifier/preferences domain, no URL registrations, a UUID-scoped test store and disabled CloudKit/shared widget publishing. Executable and debug-library hashes match the build; only bundle display/identity metadata differs. See Native_Mac_Exit_Manifest.json. This is unsigned macOS 27 beta host evidence, not signed/stable-OS certification.

An isolated Sessions.json path was temporarily replaced by an empty directory while its exact predecessor was retained beside it. A new draft value of123 remained visible in save recovery. Autosave can produce that recovery UI independently; this does **not** prove Command-W or Quit callbacks ran.

After restoring the predecessor file, Retry saved123 (verified in the journal). Repeated Command-W, Command-Q and the native Quit menu left the active session sheet open without a save error. Explicit Pause → Save & close returned to Today with Continue at question1of5. Command-Q then terminated the app. The successful exit path while a session sheet is active remains a real acceptance failure. DEBUG event-only tracing and a shared per-window proxy/owned-sheet close path are being added before repeating this workflow.

The separate overlapping-proxy detach defect is confirmed by source lifetime analysis; this one-window run did not exercise overlap. No learner data or preferences were changed. The temporary blocked path was restored, and the copied app exited through its own Quit command.
