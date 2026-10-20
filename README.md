# Kukit

*Cook it.* A study timer, course tracker, assignment planner, grade calculator and Markdown notebook for university students. Native SwiftUI for **Mac (Apple Silicon)** and **iPhone**. Everything is stored on your device; there are no accounts and no servers.

## Features

- **Focus timer** — Classic 25/5, Deep Work 50/10, your own saved techniques, or a stopwatch. Sessions are logged per course; alerts arrive even when the app is closed. Mac menu bar timer; iPhone mini-player.
- **Courses** — semesters, credits, colors, per-course stats.
- **Tasks** — homework, quizzes, projects, labs, exams with due dates, priorities and reminders; Today view, week calendar, quick add. Optional one-way push to Apple Reminders (and exams to Calendar).
- **Grades** — weighted categories, real and planned scores, current / projected / best / worst grade, "what do I need on the final?", credit-weighted GPA. The **grading scale is fully editable** (Korean 4.5 by default).
- **Notes** — nested Markdown pages with live preview, checklists, tables, `[[page links]]`, templates, links to tasks, and search across notes, tasks and courses.
- **Stats** — daily goal, streaks, per-day and per-course charts.
- **Backup** — export/import everything as one JSON file (merge or replace), CSV export of sessions and grades.

## Privacy

Kukit has no analytics, no ads and no network code. Your data lives in the app's local database on your device. Back it up from Settings ▸ Data.

## Requirements

- macOS 15+ on Apple Silicon and Xcode 26 to build; iOS 18+ on the iPhone
- An Apple ID signed in to Xcode (a free account is enough)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to regenerate the project after editing `project.yml`

## Run it

1. Open `Kukit.xcodeproj` in Xcode.
2. Choose the **Kukit-macOS** or **Kukit-iOS** scheme.
3. Target ▸ **Signing & Capabilities** ▸ pick your **Team** (your Apple ID's Personal Team), for both targets.
4. **Mac:** ⌘R. **iPhone:** plug it in, enable *Settings ▸ Privacy & Security ▸ Developer Mode*, choose the phone as the destination, ⌘R. With a free account the iPhone build expires after 7 days; run it again from Xcode to refresh it (your data is kept).

## Share the Mac app

```sh
./scripts/make-dmg.sh      # builds build/Kukit-<version>.dmg
```

The app is signed ad hoc, so other Macs show an "unidentified developer" warning: open it once with right-click ▸ Open, or *System Settings ▸ Privacy & Security ▸ Open Anyway*. A Developer ID certificate and notarization (Apple Developer Program, US$99/year) remove the warning, and are also needed to put the iPhone app on friends' phones through TestFlight.

## Project layout

```
project.yml                 XcodeGen definition (edit this, then run `xcodegen generate`)
Kukit.xcodeproj             generated project
Packages/KukitCore/         pure Swift logic and its tests: timer, stats, reminders,
                            grades, GPA, Markdown, CSV
Kukit/Shared/               SwiftUI code used by both platforms
Kukit/macOS/                sidebar root, menu bar timer, entitlements
Kukit/iOS/                  tab bar root
Kukit/Tests/                SwiftData model, backup and scale tests (hosted macOS target)
scripts/make-dmg.sh         Release build + DMG
```

## Tests

```sh
cd Packages/KukitCore && swift test                                              # 98 logic tests
xcodebuild -scheme Kukit-macOS -destination 'platform=macOS,arch=arm64' test      # 23 model/backup tests
```

## Roadmap

Live Activity and widgets, a global hotkey, repeating tasks, drop-lowest grading rules, iPad layout, iCloud sync between Mac and iPhone.
