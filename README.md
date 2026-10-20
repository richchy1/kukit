# Kukit

*Cook it.* A study timer, course tracker, assignment planner, grade calculator and Markdown notebook for university students, with a cooking theme: studying is cooking up your future, finishing a task is preparing an ingredient, finishing a focus session means you cooked something. Native SwiftUI for **Mac (Apple Silicon)** and **iPhone**. Everything is stored on your device; there are no accounts and no servers.

## Features

- **Dashboard** — "What's cooking today?": the timer, today's ingredients (tasks), a suggested cooking order for your courses, and daily progress (goal ring, streak, tasks done, week chart). Two columns on a wide Mac window, one column on iPhone.
- **Focus timer** — Classic 25/5, Deep Work 50/10, your own saved techniques, or a stopwatch. Start, pause, resume, finish (saves the time) or cancel (saves nothing). Sessions are logged per course, alerts arrive even when the app is closed, and a "session complete" card offers a break or another round. Mac menu bar timer; iPhone mini-player.
- **Focus music** — a 50-minute background track that plays only during focus time (see below).
- **Chef Kukit** — the mascot, drawn in SwiftUI, with seven moods (ready, working, break, celebrating a session, celebrating the daily goal, "no tasks", idle) and a small, tested system of contextual kitchen-flavoured messages. The jokes can be switched off in Settings.
- **Courses** — workspace cards with a color, study time, task progress, grade and a one-tap "Start Cooking"; course colors carry through the timer, tasks, notes and stats.
- **Tasks** — homework, quizzes, projects, labs, exams with due dates, priorities and reminders; Today / Upcoming / Week / By-course views, overdue and completed sections, quick add. Optional one-way push to Apple Reminders (and exams to Calendar).
- **Grades** — weighted categories, real and planned scores, current / projected / best / worst grade, a front-and-center "What do I need on the final?" answer, a points-breakdown chart, credit-weighted GPA. The **grading scale is fully editable** (Korean 4.5 by default).
- **Notes** — nested Markdown pages in a serif "notebook" style with live preview, checklists, tables, `[[page links]]`, templates, links to tasks, and search across notes, tasks and courses.
- **Stats** — daily goal, streaks, per-day and per-course charts, and a few achievements (first session, daily goal, personal best, streaks, total hours) computed from your logged sessions.
- **Backup** — export/import everything as one JSON file (merge or replace), CSV export of sessions and grades.
- **Appearance** — a warm cream light theme and a warm charcoal dark theme, rounded type, Dynamic Type, Reduce Motion support, hover states on Mac and light haptics on iPhone.

## Focus music

The music file is `Kukit/Shared/Resources/Audio/focus-music.m4a`: the first 50 minutes (2,999.9 s, AAC 128 kbps) of a longer recording, cut **without re-encoding** so the quality is unchanged. It loops, but a session always decides when it ends.

| Timer event | Music |
|---|---|
| Start a focus session | starts from the beginning (if music and "Start with every focus session" are on) |
| Pause | pauses |
| Resume | resumes (if "Resume when a paused session resumes" is on and you hadn't paused it yourself) |
| Finish, cancel, or the phase ends | stops and rewinds |
| A break begins | stops |
| Next focus round | starts again from the beginning |
| Relaunching with a session still running | stays silent until you press play |

Controls: a compact player on the focus card (play/pause, mute, volume), a music badge in the mini-player, a menu-bar popover control, and **Settings ▸ Focus music** (on/off, volume, mute, auto-start, resume-with-timer). If the file can't be loaded the timer carries on and a small notice appears. On iPhone the audio session is `playback` with the background-audio mode so the music continues with the screen locked during a session; interruptions (calls, Siri) pause it and it resumes only if the system allows and a focus phase is still running. Unplugging headphones pauses it.

To use a different track:

```sh
ffmpeg -i your-recording.mp4 -map 0:a:0 -t 2999.9 -c:a copy -map_metadata -1 -movflags +faststart \
  Kukit/Shared/Resources/Audio/focus-music.m4a
```

(Use `-c:a aac -b:a 128k` instead of `-c:a copy` if the source isn't AAC.) Keep your original long recording out of the repo (`*.mp4` is git-ignored). Only use audio you have the right to bundle and share.

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
Kukit/Shared/DesignSystem/  palette, components, Chef Kukit (Canvas-drawn mascot)
Kukit/Shared/Audio/         music playback abstraction + controller
Kukit/Tests/                SwiftData model, backup, scale and music tests (hosted macOS target)
scripts/make-dmg.sh         Release build + DMG
```

## Tests

```sh
cd Packages/KukitCore && swift test                                              # logic tests (timer, grades, reminders, Markdown, chef messages, music policy, achievements)
xcodebuild -scheme Kukit-macOS -destination 'platform=macOS,arch=arm64' test      # model, backup and music-lifecycle tests
```

## Roadmap

Live Activity and widgets, a global hotkey, repeating tasks, drop-lowest grading rules, iPad layout, iCloud sync between Mac and iPhone.
