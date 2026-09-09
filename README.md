# Write

A dead-simple Markdown writing app for macOS. One window, one column of text,
and nothing else in the way. It follows the system's light and dark appearance
without a setting of its own.

This is a native macOS port of [Omawrite](https://github.com/omacom/omawrite),
which is written in Qt Quick and C++ for Omarchy. The typography, palette,
Markdown styling and editing behaviour come from there; the shell is AppKit.

## Build

Requires macOS 13 or later and the Xcode command line tools.

```sh
./bin/build          # builds .build/Write.app
./bin/run            # builds and launches it
./bin/install        # builds and copies to /Applications
./bin/test           # runs the unit tests
```

There is no Xcode project. `Package.swift` is the whole build, and `bin/build`
wraps the resulting executable in an app bundle with `Resources/Info.plist`, the
icon and the bundled fonts. Open the package directly in Xcode (`File > Open`
on the repository folder) if you prefer to work there.

## Writing

The Return key is the one thing worth knowing about. In prose it leaves a blank
line, so paragraphs are separated the way Markdown wants them. In a list or a
quote it continues the list, numbering as it goes, and on an empty item it ends
the list. `⇧⏎` is a plain line break, and inside a fenced code block Return is
left alone. Backspace against a paragraph break removes the whole break, so it
undoes exactly one Return.

The markers around **bold**, *italic* and [link](https://example.com) text are
collapsed to nothing once they are closed — the text styles itself and the
source stays plain Markdown. The caret steps over the collapsed markers rather
than disappearing into them.

Pasting a URL over selected text turns it into a Markdown link instead of
replacing it.

## Shortcuts

| | |
|---|---|
| `⌘N` | New document |
| `⌘O` | Open |
| `⌘S` / `⇧⌘S` | Save / Save As |
| `⌘P` | Print |
| `⌘Z` / `⇧⌘Z` | Undo / Redo |
| `⌘F` | Find |
| `⌥⌘F` | Find and Replace |
| `⌘G` / `⇧⌘G` | Next / previous match |
| `⌘B` / `⌘I` / `⌘K` | Bold / italic / link |
| `⌘+` / `⌘-` / `⌘0` | Bigger / smaller / actual size |
| `⌃⌘F` | Full screen |
| `⌘/` | This list |

## What macOS handles

Omawrite implements crash recovery, external-change detection and window
geometry itself. On macOS those belong to `NSDocument`, so `Write` uses them
instead of reimplementing them:

- **Drafts and recovery.** The app autosaves in place, so an unsaved draft
  survives a crash or a force quit and comes back with the window.
- **Versions.** File > Revert To walks back through earlier saves.
- **Files changed by other apps.** An untouched document reloads silently. One
  with unsaved work asks whether to keep your version or reload.
- **Window position, Open Recent, Rename, Move To, Duplicate.** Standard.

Two behaviours are deliberately different from Omawrite. Omawrite follows the
desktop's text-size setting; macOS has no such knob, so the size lives under
`⌘+` / `⌘-` / `⌘0` instead. And Omawrite reads the current Omarchy theme's
colours from `colors.toml`; there is no equivalent here, so the palette is the
one Omawrite falls back to.

## Layout

```
Sources/WriteKit/     Markdown scanning, word count, link and file-name rules.
                      Foundation only, so it is unit tested without a UI.
Sources/Write/        The app: document, window, editor, highlighter, menus.
Tests/WriteKitTests/  Tests for everything in WriteKit.
Resources/            Info.plist, the icon, and the bundled fonts.
bin/                  build, run, test, install, and the icon generator.
```

The editor is an `NSTextView` over a TextKit 1 stack whose `NSTextStorage` is
owned by the document. `MarkdownHighlighter` is the storage's delegate and
restyles the paragraphs an edit touched. Everything it needs to know about
Markdown comes from `MarkdownSyntax`, which is also what the text view uses to
step the caret over collapsed markers — one scan, one set of rules.

## Licence

MIT, carried over from Omawrite; see `LICENSE`.

The bundled iA Writer Mono S is licensed under the SIL Open Font License 1.1
(`Resources/Fonts/OFL.txt`). The font is copyright Information Architects Inc.
and is based on IBM Plex, copyright IBM Corp.
