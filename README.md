# Kukit

*Cook it.* A study timer, course tracker (and, soon, grade calculator, assignment planner and Markdown notes) for university students. Native SwiftUI for **Mac (Apple Silicon)** and **iPhone**.

## Requirements

- macOS 15+ on Apple Silicon, Xcode 26, an Apple ID signed in to Xcode (a free account is enough)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to regenerate the project

## Layout

```
project.yml                 XcodeGen definition (edit this, then run `xcodegen generate`)
Kukit.xcodeproj             generated project (open this in Xcode)
Packages/KukitCore/         pure Swift logic + tests: TimerEngine, StatsCalculator
Kukit/Shared/               SwiftUI app code used by both platforms
Kukit/macOS/                Mac-only: sidebar root, menu bar timer, entitlements
Kukit/iOS/                  iPhone-only: tab bar root
```

## Run it

1. Open `Kukit.xcodeproj` in Xcode.
2. Select the **Kukit-macOS** or **Kukit-iOS** scheme.
3. Target ▸ **Signing & Capabilities** ▸ choose your **Team** (your Apple ID's Personal Team). Do this for both targets.
4. **Mac:** press ⌘R. **iPhone:** plug it in, turn on *Settings ▸ Privacy & Security ▸ Developer Mode*, choose the phone as the run destination, press ⌘R. With a free account the iPhone build expires after 7 days; run it again from Xcode to refresh it (your data is kept).


## Status

- v0.1 — courses, focus timer (Classic 25/5, Deep Work 50/10, custom techniques, stopwatch), history, stats, Mac menu bar timer, iPhone mini-player
- v0.2 — tasks with due dates, priorities and reminders (local notifications), Today view, week calendar, optional one-way push to Apple Reminders
- v0.3 — grades: weighted categories, scores (real or planned), current and projected grade, "what do I need on the final?", GPA, and fully editable grading scales (Korean 4.5 by default)
- v0.4 — Markdown notes: nested pages, live preview, formatting bar, checklists, `[[page links]]`, templates, link to tasks, search across notes/tasks/courses

## Tests

```sh
cd Packages/KukitCore && swift test          # timer, stats, reminders, grades, GPA
xcodebuild -scheme Kukit-macOS -destination 'platform=macOS,arch=arm64' test   # SwiftData model tests
```
