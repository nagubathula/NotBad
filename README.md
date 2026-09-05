# NotBad

*A quiet place to write — now on every desktop.*

NotBad is a lightweight, cross-platform Markdown writer for **Windows, macOS, and Linux**, built with Flutter. It is a from-scratch port of [Trace](https://github.com/john-mrty/Trace) (itself built on the engine of [MarkEdit](https://github.com/MarkEdit-app/MarkEdit)), re-imagined as a **pure-Flutter app**: no embedded web view, no CodeMirror. The Markdown-aware editor is implemented natively in Dart, so the app starts fast, stays small (~28 MB), and behaves identically on every platform.

## Features

### Writing
- **Markdown styled as you type** — headings, bold, italic, strikethrough, inline code, code fences, links, lists, task checkboxes, and blockquotes render live in the editor
- **Three view modes** (`Ctrl+Shift+H` cycles):
  1. *Styled, Marks Hidden* — syntax marks (`#`, `**`, `` ` ``…) disappear; the line under your caret reveals its marks so editing stays predictable
  2. *Styled with Marks* — styles applied, marks visible
  3. *Plain Markdown* — pure monospace source
- **Focus mode** (`Ctrl+Shift+F`) — dims everything except the paragraph you're working on
- **Smart lists** — Enter continues bullets, numbering, and `- [ ]` checkboxes; Enter on an empty item exits the list; Tab/Shift+Tab indent
- **Auto-pairing** — type a mark with text selected to wrap it; brackets and backticks auto-close
- Click a checkbox to toggle it; Ctrl+click a link to open it

### Around the writing
- **Command palette** (`Ctrl+K`) — every action, fuzzy-searchable, with recent files
- **Find & replace** (`Ctrl+F` / `Ctrl+H`) — live match counts and highlights
- **File sidebar** (`Ctrl+\`) — keyboard-driven tree of the writing files around your document; watches the folder for changes
- **Hover table of contents** — quiet dashes top-left; hover for the outline, click to jump
- **Copy as Rich Text** (`Ctrl+Alt+C`) — paste into Mail, Docs, or Slack with real formatting
- **Seamless window** — no title-bar band; custom quiet chrome with the document name
- **Session restore & autosave** — reopens your last document at your last caret position
- **One theme, done well** — warm paper light / neutral dark, six accent colors, zoom (`Ctrl+=`/`-`/`0`)
- **Plain `.md` files on disk** — no library, no lock-in, no cloud, no data collection

## Repository layout

| Path | What it is |
|---|---|
| [`notbad-flutter/`](notbad-flutter/) | The Flutter app (all source, tests, and platform runners) |
| [`notbad-flutter/installer/`](notbad-flutter/installer/) | Windows per-user installer / uninstaller scripts |

## Building

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.41+).

```bash
cd notbad-flutter
flutter run -d windows     # or: -d macos / -d linux
flutter build windows      # release build
flutter test               # run the test suite
```

## Installing on Windows

The installer copies the release build to `%LOCALAPPDATA%\NotBad`, adds **"Open with NotBad"** to the right-click menu for `.md`/`.markdown`/`.txt` files, registers it in the "Open with" chooser, and creates a Start Menu shortcut. Per-user only — no admin rights needed.

```bash
cd notbad-flutter
flutter build windows
powershell -ExecutionPolicy Bypass -File installer\install.ps1
```

To remove everything: `powershell -ExecutionPolicy Bypass -File installer\uninstall.ps1`

## Keyboard shortcuts

| | |
|---|---|
| `Ctrl+K` | Command palette |
| `Ctrl+N` / `Ctrl+O` / `Ctrl+S` | New / Open / Save |
| `Ctrl+F` / `Ctrl+H` | Find / Find & replace |
| `Ctrl+B` / `Ctrl+I` | Bold / Italic (wraps word or selection) |
| `Ctrl+\` | File sidebar |
| `Ctrl+Shift+F` | Focus mode |
| `Ctrl+Shift+H` | Cycle view modes |
| `Ctrl+Alt+C` | Copy as Rich Text |
| `Ctrl+=` / `Ctrl+-` / `Ctrl+0` | Zoom in / out / reset |

On macOS, `Cmd` works in place of `Ctrl`.

## What's deliberately not here

From Trace/MarkEdit, these are macOS-only and have no cross-platform equivalent: QuickLook previews, Time Machine file versions, Apple Writing Tools / Foundation Models / Translation, NSSpellChecker completions, and the Tahoe glass chrome. Planned next: true zero-width mark concealment with rendered code panels, typewriter scrolling, `.textbundle` support, and text encodings.

## Credits

Built on the ideas and design of [Trace](https://github.com/john-mrty/Trace) by John Moriarty and [MarkEdit](https://github.com/MarkEdit-app/MarkEdit) by cyanzhong and contributors. MIT licensed, with gratitude.
