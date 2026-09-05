# NotBad

A lightweight, cross-platform Markdown writer for **Windows, macOS, and Linux**, written in Flutter.

NotBad is a port of [Trace](https://github.com/john-mrty/Trace) (itself built on [MarkEdit](https://github.com/MarkEdit-app/MarkEdit)), re-imagined as a pure-Flutter app: no embedded web view, no CodeMirror — the Markdown-aware editor is implemented natively in Dart, so the app stays small and behaves identically on every desktop.

## Features (Phase 1)

- **Markdown styled as you type** — headings, bold, italic, strikethrough, inline code, code fences, links, lists, task checkboxes, and blockquotes are rendered live in the editor. Syntax marks (`**`, `#`, `` ` ``…) are dimmed toward the background; `Ctrl+Shift+H` brings them back as a source mode.
- **Focus mode** (`Ctrl+Shift+F`) — dims everything except the paragraph you're working on.
- **File sidebar** (`Ctrl+\`) — a tree of the writing files around your document, or rooted at a folder you pick.
- **Command palette** (`Ctrl+K`) — every action, fuzzy-searchable, with recent files.
- **Floating toolbar** — heading, bold, italic, code, syntax visibility, focus mode, and a live word count.
- **One theme, done well** — GitHub light/dark following the system (or pinned), with Trace's six accent colors: Amber, Crimson, Fern, Teal, Azure, Graphite.
- **Plain `.md` files on disk** — open/save/save-as with unsaved-change protection. No library, no lock-in.

Keyboard shortcuts use `Ctrl` on Windows/Linux and also accept `Cmd` on macOS.

## Building

```
flutter run -d windows   # or: -d macos / -d linux
flutter build windows    # release build
```

## Not ported (yet or ever)

From Trace/MarkEdit, these are macOS-only and have no cross-platform equivalent: QuickLook previews, Time Machine file versions, Apple Writing Tools / Foundation Models / Translation, NSSpellChecker completions, and the Tahoe glass window chrome. Planned next phases: find & replace, table of contents, typewriter scrolling, Copy as Rich Text, `.textbundle` support, and text encodings.
