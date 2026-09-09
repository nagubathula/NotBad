# Changelog

All notable changes to **NotBad** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-09-10

### Added
- **Code Fence Syntax Highlighting**: Lightweight, palette-aware pure Dart syntax tokenizer for code blocks (` ```dart `, ` ```python `, ` ```json `, etc.) supporting keywords, strings, numbers, comments, types, and annotations without webviews or browser runtimes.
- **Daily Writing Goal & Ambient Progress Ring**: Configurable session targets (`Set Daily Writing Goal…`) with a minimal circular progress ring inside the Statistics (`ⓘ`) popover and floating toolbar.
- **E-Ink & Monochrome High-Contrast Mode**: Pure high-contrast `#FFFFFF` on `#000000` (or `#000000` on `#FFFFFF`) display preset with crisp hairline borders, optimized for E-Ink monitors and high-contrast writing environments.
- **Git Gutter Indicators in Sidebar**: Automatic Git repository detection with whisper-quiet status badges next to writing files (`•` for modified, `+` for untracked notes).
- **Publication-Ready Printable PDF Export**: Dedicated document export with `@media print` CSS rules, clean Charter/Georgia serif typography, page margins, and auto-invoked browser print/PDF dialog.
- **Multi-Platform Release Pipeline**: GitHub Actions release workflow building automated artifacts for **Windows** (`.zip` and `.exe` installer), **Linux** (`.tar.gz`), and **macOS** (`.zip`).
- **Logo Presentation**: Brand logo integrated across READMEs and repository assets.

### Changed
- **Architectural Decomposition**: Refactored `editor_screen.dart` by extracting discrete, testable sub-widgets: `FindReplaceBar`, `WindowTitleBar`, `HoverToc`, and `FloatingToolbar`.
- Scrubbed all external product references from documentation and case study files.

---

## [1.0.0] - 2026-09-08

### Added
- Initial public release of NotBad — lightweight, cross-platform Markdown writer for Windows, macOS, and Linux.
- Pure-Flutter editor engine with native Markdown parsing via custom `TextEditingController`.
- In-place syntax concealing with Caret-Line Reveal.
- Three view modes: Styled Marks Hidden, Styled with Marks, Plain Markdown.
- Focus mode with typewriter scrolling (caret vertically centered).
- File sidebar with directory watcher and keyboard navigation.
- Fuzzy Command Palette (`Ctrl+K`) and Open Document search (`Ctrl+Shift+O`).
- Floating receding formatting pill toolbar with live statistics popover.
- Warm Paper (`#F7F6F3`) light theme and Neutral Warm (`#2D2D2D`) dark theme with 6 accent colors.
- Autosave, session restore, external file change detection, and untitled draft recovery.
