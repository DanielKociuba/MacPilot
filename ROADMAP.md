# MacPilot: from prototype to daily utility

## Product promise

Understand your Mac and finish everyday maintenance in one calm, native app. Make the first minute useful, explain every system change, and keep personal data local.

The initial audience is Mac users who want a small set of useful tools without a subscription dashboard full of alarming “health” warnings. Download demand is a hypothesis to validate with real users, not a claim that adding enough features will guarantee adoption.

## Milestone 1 — trustworthy daily foundation (this preview)

- Adaptive overview, CPU history, and clear measurement labels.
- Reviewed, selected cache moves to Trash with failure reporting.
- Clipboard capture off at launch, search, pause, per-item removal, and clear.
- Timed Keep Awake and explicit Finder restart confirmation.
- One canonical source directory and macOS build/test CI.

## Milestone 2 — reasons to return

Prioritize based on feedback from 10–20 testers who use the app for a week:

1. **Menu-bar panel and keyboard launcher:** reach existing tools without navigating a full window. Add discoverable shortcuts and user-selected favorites.
2. **Large-file explorer:** scan a user-selected folder, show progress/cancel and a size breakdown, reveal files in Finder, and make any move to Trash explicit. Keep it separate from app-cache cleanup.
3. **Per-app resource view:** show which apps are consuming CPU and memory with careful sampling and clear units; avoid presenting memory use alone as a problem.
4. **Preferences and onboarding:** explain permission requests at the moment a feature needs them, provide login-item control, and preserve user choices without persisting clipboard content by default.

Avoid adding an uninstaller, duplicate deletion, window manager, network monitor, and automation engine all at once. Each needs a meaningful reliability and permission story. Build one complete workflow before starting another.

## Milestone 3 — public download

- Distinct app icon and consistent visual identity; review the MacPilot name for potential conflicts before investing in branding.
- Developer ID signing, hardened runtime, notarization, and stapling. Credentials belong in repository secrets, never source files.
- Reproducible release packaging and release notes, a clean install/uninstall path, and a verified update mechanism.
- Verify Apple Silicon and Intel support; do not label an architecture as supported until its build and runtime have been tested.
- Landing page with genuine screenshots, a short walkthrough, supported macOS versions, privacy details, and one clear download.
- Accessibility review: VoiceOver, keyboard-only navigation, contrast, large text, reduced motion, and both color appearances.
- Performance measurements on idle, clipboard capture, active monitoring, and large cache scans. Publish measured results rather than untested “lightweight” claims.

## Manual preview acceptance checklist

- Launch on a clean macOS 13+ account; clipboard capture is off and no cache scan begins automatically.
- Resize all four panels and inspect light/dark appearance; all controls remain reachable using the keyboard and VoiceOver.
- Verify CPU readings against Activity Monitor over time, available storage against macOS capacity semantics, and battery behavior on battery/AC and desktop hardware.
- Scan caches with inaccessible folders; verify partial sizes/errors are visible. Cancel the confirmation and verify nothing moves. Test a move with disposable test caches; confirm contents appear in Trash and no “space freed” claim is made.
- Start and stop each Keep Awake duration; verify automatic expiry and process exit when quitting MacPilot. Verify a failed start is not shown as active.
- Enable clipboard capture, copy repeated/multiline/large text, search, remove, pause, clear, and restart. Check concealed pasteboard types with a test harness; do not use real passwords.
- Change hidden-file visibility only after Finder transfers finish. Confirm cancel leaves the setting unchanged and successful changes are visible in Finder.
- Download a CI ZIP on a second Mac and record Gatekeeper behavior. Public release remains blocked until signing/notarization is complete.

## Success criteria

Ask testers which tool they used again, what other app it replaced, and what confused them. Track voluntarily shared feedback: successful first task, return use after seven days, permission failures, and defects. Keep telemetry absent unless a separate transparent opt-in design is agreed.

Choose pricing only after repeat usefulness is established. The immediate goal is a reliable preview people choose to keep installed.
