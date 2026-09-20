# TODO

Open items only. Resolved/closed items (with full investigation and
verification history) have moved to `docs/todo-archive.md`.

## Pin the AXP2101's 6s emergency power-off to actually power off

Found while investigating the (now-resolved, see `docs/todo-archive.md`)
PWR power-back-on flakiness. The AXP2101's "Function Select when
btn_pwroff_en=1" bit (REG22H bit 0 -- 0=Power-off, 1=Restart) is never
explicitly set by Folloup (`Axp2101::SetButtonPowerOffRestarts()` exists in
`components/axp2101/axp2101.h:56` but has zero call sites), so it sits at
its factory EFUSE default. `waveshare_board.cpp` enables "PWRON > OFFLEVEL
(6s) as a power-off source" (`SetButtonPowerOffEnabled(true)`), and
CLAUDE.md documents that 6s hold as "a hardware escape even if firmware is
wedged" -- but if the EFUSE default for that function-select bit happens to
be "Restart," the emergency 6s hold would reboot the board instead of cutting
power, contradicting that guarantee.

Fix: call `SetButtonPowerOffRestarts(false)` explicitly in
`ConfigurePmicRails` (`components/board/waveshare_board.cpp`) so this
doesn't depend on an unverified factory default. Low-risk, self-contained --
worth doing on its own branch rather than folding into unrelated work.

## Redundant derived state: icon/checked fields duplicate their source bool

`TimelineEntry` (in `notes_page_coordinator.h:16-21` and mirrored in
todos/follow_up) stores both a source-of-truth bool (`follow_up`/
`completed`) and a separately-computed rendered projection
(`tag_icon_asset`/`accessory.checked`), which has to be kept in sync by
hand at 2 call sites per page (`notes_page_coordinator.cpp:81,303`,
matching lines in todos/follow_up). A future third place that flips
`follow_up`/`completed` (e.g. a bulk "mark all done" action) could easily
forget to update the mirror field.

Fix: derive the icon/checked state in `BuildState()` at render time instead
of storing it. The page-trio refactor (see `docs/todo-archive.md`) left
`TimelineEntry` and its mutators page-specific, so this is still open and
would now touch each page's `BuildState()`/`SetEntryFollowUpState`/
`SetEntryChecked` individually rather than a single shared spot.

## IMU auto-sleep motion detection polls instead of using the hardware interrupt path

`main/device_sleep_runtime.cpp:608-637` (`MotionPollingTask`) wakes every
200ms to do a full I2C read + float-math classification purely to detect
stillness for auto-sleep — but `components/qmi8658/qmi8658.cc` already
implements complete hardware any-motion/no-motion detection via INT2
(`ConfigMotion`, `EnableWakeOnMotion`, callbacks at lines ~877-1470), the
same mechanism already wired for the light-sleep wake gesture.
`components/imu_service/imu_service.cpp` never surfaces any of it — only
`ReadSample`. Continuous I2C polling on a battery-powered device where an
event-driven equivalent already exists elsewhere in the same driver.

## `FitLabelText` still independently reimplemented in two places

`network_item.cpp` and `select_item.cpp` each still have their own private
copy of `FitLabelText` (truncate-with-ellipsis), with the parameters in a
different order (`text, role, max_width`) than the shared version already
promoted to `render_utils.h` (`role, text, max_width`) — which is exactly
why they didn't collide with it and get caught by the build the way two
other duplicates already were (see the archived "Replace the lock screen's
full-screen clock with a todo summary" item). Finishing the dedup means
normalizing one of the two parameter orders and updating call sites in
whichever files change.

## Replace auto light sleep with a full auto shutdown

Today, after `FOLLOWUP_AUTO_SLEEP_LIGHT_SLEEP_TIMEOUT_SECONDS` of IMU-detected
inactivity (default 1800s / 30 minutes, `main/Kconfig.projbuild:71-79`), the
device enters light sleep: `device_sleep_service::Action::kEnterLightSleep` is
dispatched to `EnterLightSleep()` in `main/device_sleep_runtime.cpp:490-492`,
which stops Wi-Fi, puts the display to sleep, and arms a GPIO wake.

Craig's reasoning: waking back up from light sleep already costs about the
same time as booting from scratch (`RestoreAfterLightSleep()` has to redo a
real Wi-Fi reassociation and a forced SD remount — see the comment on
`ForceDisplaySleep`'s Wi-Fi-reassociation cost in `lock_screen_runtime.cpp`'s
`Show()`), so light sleep isn't actually buying much wake-latency benefit
over a full power-off at that point, while a full shutdown saves
meaningfully more battery. Wanted: once the light-sleep timeout elapses, the
device should fully shut off (same mechanism as a manual shutdown,
`power_service::RequestShutdown()`) instead of entering light sleep — and
this auto-triggered shutdown should freeze on the lock/shutdown screen the
same way a manual shutdown now does (`lock_screen_runtime::ShowForShutdown()`,
added for the "Full shutdown should freeze on the lock screen's todo
summary" item, `docs/todo-archive.md`).

Open questions for whoever designs this:
- Whether to repurpose `FOLLOWUP_AUTO_SLEEP_LIGHT_SLEEP_TIMEOUT_SECONDS` as
  the auto-shutdown timeout directly, or add a distinct Kconfig option —
  "light sleep" and "auto shutdown" are conceptually different features even
  if this item replaces one with the other at the same trigger point.
- The same `BlockerReason`s that already gate light sleep (recording active,
  recording saving, audio playback, storage write, Wi-Fi AP mode, time sync,
  display refresh — `components/device_sleep_service/include/device_sleep_service.h:39-45`,
  checked in `main/device_sleep_runtime.cpp`'s blocker-evaluation function)
  presumably should gate auto-shutdown too.
- The USB-present case: `power_service::RequestShutdown()` doesn't actually
  cut power while VBUS is present — the call returns and the board stays
  running. Auto light sleep today still works fine on USB power (Wi-Fi
  stops, display sleeps, GPIO wake still armed). If auto-shutdown fires
  while on USB, naively reusing `RequestShutdown()` would leave the device
  sitting on the frozen lock/shutdown screen, powered but not actually
  asleep or off, until a button press — a real regression from today's
  behavior on a plugged-in device. Worth deciding whether auto-shutdown
  should only trigger on battery power, falling back to today's light-sleep
  behavior while USB is present.
- This is a real, deliberate UX change beyond just "one more sleep stage":
  today, any button instantly wakes the device from light sleep; after this
  change, once the timeout elapses, waking requires a full boot cycle (PWR
  press through the AXP2101's normal power-on path) instead. That's exactly
  the tradeoff Craig wants (his read: the wake cost is already boot-cost
  today), but it's worth calling out explicitly since it's a bigger
  behavioral change than the wording ("shut off instead of light sleep")
  might suggest at a glance.

Own branch/PR.

## Finish the Followup -> Chroninkle rename

Craig decided (2026-09-13) to rename the project from Followup to
**Chroninkle**, since it's diverged enough from the original Followup
concept to warrant its own identity. The boot splash, `README.md`, and
`docs/user-manual.md` already lead with the new name and logo (the Followup
and ALXV Labs logos it grew from moved to a "Based on" attribution line on
the splash and stayed credited in the README) -- see `CHANGELOG.md`
[Unreleased] and PR #53. Everything below is still Followup/Folloup and
needs its own pass, deliberately deferred rather than done as a drive-by:

- **GitHub repo**: `mach1na/folloup` -> a new name (`chroninkle`?). Update
  the repo description too (`"A Folloup port for SeeedStudio's Sticky"` is
  already stale -- Sticky isn't even the current target). Repoint the local
  `origin` remote explicitly rather than relying on GitHub's redirect.
- **ESP-IDF project name**: `CMakeLists.txt:7` -- `project(folloup_sticky)`.
  This is what shows up as the app name in build output and the `.bin`/`.elf`
  filenames.
- **Kconfig namespace**: 14 `CONFIG_FOLLOWUP_*` symbols (Wi-Fi AP
  prefix/SSID/password, time sync defaults, default timezone, Gemini API
  key, auto-sleep timeouts, todo-archive days, text-reader folder) across
  `main/Kconfig.projbuild`, `sdkconfig.defaults`, and every `.cpp` that reads
  them. This is the most invasive single piece -- renaming it means updating
  every reference plus anyone's local `sdkconfig`, so it wants a dedicated
  branch and a real build+flash test, not folded into another change.
- **Source comments/log strings**: ~53 files under `main/`/`components/`
  (excluding generated files) mention "Followup"/"Folloup", including the
  onboarding carousel's first slide ("Welcome to Followup") and the startup
  log line (`"Followup firmware version %s"` in `app_shell.cpp`). The device's
  Wi-Fi setup hotspot also still broadcasts as `Followup-XXXXXX`
  (`CONFIG_FOLLOWUP_WIFI_AP_PREFIX="Followup"`) until the Kconfig rename
  above lands -- `docs/user-manual.md` calls this out explicitly rather than
  describing a name the device doesn't actually broadcast yet.
- **Internal technical docs**: `docs/app-architecture.md`,
  `docs/gemini-service.md`, `docs/auto-sleep.md`, `docs/asset-generation.md`,
  `docs/versioning.md`, `docs/waveshare-epaper-hardware-spec.md` all describe
  the product as Followup and reference the `CONFIG_FOLLOWUP_*`/`kFollowupLogo`
  symbols by their real (current) names -- rename these alongside the code
  they describe, not before, so they don't end up describing symbols that
  don't exist yet.
- **`webserver/`** (setup portal): page title/copy and `package.json` name
  still say Followup.

Do the Kconfig/CMake/source-comment pass as its own branch with a full
build+flash verification before merging, since it touches identifiers other
code and anyone's saved `sdkconfig` depend on.

## Change the boot-up sound

Craig wants a new startup sound cue to go with the Chroninkle rebrand
(2026-09-13) — he'll make/source the audio himself later.

To swap it: replace `components/system_sound_service/sounds/startup.mp3`
with the new MP3 (same filename, no other changes needed), rebuild, flash.
No asset-generation script/pipeline involved, unlike the boot logo — the
MP3 is embedded directly via `EMBED_FILES` in
`components/system_sound_service/CMakeLists.txt`. Source can be any
standard MP3 (any sample rate/mono-or-stereo); the firmware decodes and
resamples/downmixes to mono 16kHz 16-bit PCM automatically to match the
ES8311 codec's fixed clock, though exporting at 16kHz mono directly avoids
any resampling artifacts. No hard size/duration cap, but it's embedded raw
into the firmware image and fully decoded to PCM in PSRAM on first play
(cached for the app's life, ~32KB/sec of audio) — existing cues are all
short blips, and `startup.mp3` is already the longest at a few seconds, so
keep the replacement in that ballpark.

## Upload books from a phone over Wi-Fi, without OTG/a computer

Getting a book onto the device today means enabling OTG/USB mass-storage
mode and copying files from a computer (`docs/user-manual.md`'s Books
section) — there's no path from a phone, which doesn't do USB
mass-storage host mode easily.

Idea: once the device is joined to a normal (non-AP) Wi-Fi network, serve a
small "upload a book" page from the same HTTP server infrastructure
`wifi_service` already runs for the AP setup portal, reachable at the
device's local IP from any browser on the same network — pick a file on a
phone, it lands in the SD card's `books` folder. Needs: a normal-Wi-Fi-mode
HTTP route (the existing server today only really matters in AP setup
mode), a multipart/file upload handler, a filename sanitizer (reject path
traversal, restrict to the books folder, cap file size), and reuse of
`text_reader_service`'s/`epub_service`'s existing folder conventions so
uploaded files show up in the book list without any extra wiring.

Only works when the phone and device share the same Wi-Fi network (not over
cellular away from home). Own branch.

## One-way export of device notes as `.md` files (phone note-sync groundwork)

Craig has existing notes on his phone as a folder of `.md` files and wants
Chroninkle's own Notes/Todos/Follow-up entries to end up alongside them.
True two-way sync (merge, conflict resolution between phone edits and
device recordings) is a much bigger, separately-scoped problem — start with
one-way **export**: write each transcribed recording out as a `.md` file
(e.g. one per day, or one per recording, TBD) onto the SD card, using the
same local-network HTTP access point as the book-upload idea above so a
phone can pull the files down without a cable. Reuses
`recording_archive_service`'s existing transcript/metadata storage as the
source of truth — this is a read-only export, no new data model needed.
Own branch; natural follow-up to the book-upload item above once that HTTP
serving infrastructure exists.

