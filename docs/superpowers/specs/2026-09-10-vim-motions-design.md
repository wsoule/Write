# Vim motions for Write

Write becomes a modal editor: every document opens in normal mode, `i` starts
writing, and the daily vim vocabulary — motions, counts, `d`/`c`/`y`, visual
mode, `.` — works the way fingers expect. Insert mode is exactly the editor
that exists today; nothing about Markdown editing changes.

Always on. There is no setting.

## Scope

In: normal, insert, visual and visual-line modes; the motions and operators
listed below; counts; one unnamed register; `.` repeat; a mode indicator; a
block caret in normal and visual mode.

Out (later, cleanly additive): text objects (`iw`, `ip`, `i"`), `/` and `?`
search, named registers, marks, `:` commands, `~`, `J`, `>>`/`<<`, `r`, `R`.

## Modes

| Mode | Enter | Leave |
|---|---|---|
| Normal | on open; `Esc` from any other mode | `i a I A o O c v V` |
| Insert | `i a I A o O`, or `c` after its motion | `Esc` — the caret steps back one column, as in vim, unless it is at the start of a line |
| Visual | `v` | `Esc`, or an operator |
| Visual-line | `V` | `Esc`, or an operator |

`Esc` in normal mode clears any pending count, operator or prefix. An
unrecognised key in normal or visual mode beeps and clears pending state.

Insert mode passes every key to the existing editor: SmartReturn, Backspace
merging paragraphs, paste-as-link, `⌘B`/`⌘I`/`⌘L`, find, everything. Command
key shortcuts (`⌘S`, `⌘K`, `⌘F` …) keep working in every mode; vim only
claims unmodified keys and `^R`.

## Motions

All motions accept a count. Positions are UTF-16 offsets into the document,
like the rest of `WriteKit`.

| Keys | Motion | Type |
|---|---|---|
| `h` `l` | one character left / right, stopping at the line's ends | exclusive |
| `j` `k` | one **display** line down / up (vim's `gj`/`gk`). Prose lines are paragraphs, so logical-line movement is useless here. Column is remembered across a run of `j`/`k` the way vim does (`curswant`) | linewise for operators (whole paragraphs) |
| `w` `b` `e` | vim word: a run of letters, digits and `_` (Unicode letters count), a run of other non-blank characters, or blank. `w` also stops on an empty line | `w` `b` exclusive, `e` inclusive |
| `W` `B` `E` | blank-delimited words | as above |
| `0` | line start (only when no count is pending; otherwise it is a digit) | exclusive |
| `^` | first non-blank of the line | exclusive |
| `$` | line end; with a count, end of the line *count−1* below | inclusive |
| `gg` `G` | first / last line; `5G` line 5 | linewise |
| `{` `}` | previous / next empty line | exclusive |
| `f` `t` `F` `T` + char | to / till the char on the current line; `;` `,` repeat | `f` `t` inclusive, `F` `T` exclusive |

The caret in normal mode sits *on* a character, so it cannot rest past the
last character of a line (except on an empty line). Entering normal mode
from insert at end of line moves it onto the last character.

## Operators

| Keys | Meaning |
|---|---|
| `d` + motion | delete into the register |
| `c` + motion | delete into the register, then insert. `cw` on a non-blank behaves as `ce`, vim's special case |
| `y` + motion | yank into the register; caret moves to the start of the range |
| `dd` `cc` `yy` | the whole paragraph (with its newline); `3dd` three paragraphs. `cc` empties the paragraph and enters insert on it |
| `x` `X` | `dl` `dh` |
| `p` `P` | put after / before. A linewise register goes on a new line below / above and lands the caret on it; a charwise register goes inline and lands the caret on the last put character |
| `u` `^R` | undo / redo (NSTextView's) |
| `.` | repeat the last change with the same count unless a new count is given |
| `i a I A o O` | enter insert: here / after the caret / at first non-blank / at line end / on a new line below / above. `o` and `O` use SmartReturn, so a list continues |

Motion inclusivity, and the rule that a linewise motion (`j`, `k`, `gg`, `G`)
makes the operator linewise, follow vim. `d}` on the last paragraph deletes
to the end of the document.

Visual mode: motions extend the selection from the anchor; `o` swaps anchor
and caret; `d` `x` `c` `y` act on the selection (linewise in `V`); `p`
replaces the selection with the register. Selection is shown with the
editor's normal selection highlight.

## Register and repeat

One unnamed register: text plus a linewise flag. `d`, `c`, `x`, `y` and
visual operators write it; `p`/`P` read it. It is separate from the system
pasteboard; `⌘C`/`⌘V` are untouched.

`.` replays the last change: an operator with its motion and count, `x`, `p`,
or an insert session (the entry command plus the text typed until `Esc`).
Undo groups: one operator is one undo step; an insert session from entry to
`Esc` is one undo step.

## Presentation

- Footer status (left of the word count) reads `NORMAL`, `INSERT`, `VISUAL`
  or `V-LINE`, followed by pending keys when there are any: `NORMAL d2`,
  `NORMAL f`.
- The caret is a filled block one character cell wide in normal and visual
  mode, the existing thin bar in insert mode. The block sits on the
  character under the caret and uses the caret colour at reduced alpha so
  the glyph stays readable.

## Components

```
WriteKit/VimMotions.swift   pure: (text, position, count) → target, and
                            range(for: motion, from:) with inclusivity
WriteKit/VimState.swift     pure reducer: (state, key) → (state, [VimCommand])
Write/VimController.swift   owns state, register, last change; runs commands
                            against MarkdownTextView; publishes mode text
Write/MarkdownTextView      keyDown routes non-insert keys to the controller,
                            Esc in insert; block caret in drawInsertionPoint
Write/FooterView            status shows the mode
Write/EditorViewController  wires controller ↔ footer
```

`VimCommand` is the whole surface between the pure reducer and AppKit:

```swift
enum VimCommand {
    case moveCaret(to: Int)
    case moveDisplayLines(Int)            // j/k, uses NSTextView's own line movement
    case select(NSRange, linewise: Bool)  // visual mode
    case replace(NSRange, with: String, caretAt: Int)   // d, c, x, p, visual d
    case yank(NSRange, linewise: Bool)
    case smartReturn(after: Bool)         // o / O
    case setMode(VimMode)
    case undo, redo
    case beep
}
```

The reducer knows nothing about the screen except through the text it is
handed; `j`/`k` are delegated because display lines are the layout
manager's. Everything else — every motion, every operator's range, every
count — is decided in `WriteKit` and testable with a string.

Data flow: `keyDown` → `VimController.handle(key)` → `VimState.reduce` →
commands → text view. Caret moves go through `setSelectedRange`, so the
highlighter's marker reveal keeps working in normal mode.

## Errors

- A motion that cannot move (e.g. `l` at line end, `k` on the first line) is a
  no-op; if an operator was pending it is cancelled without editing.
- Unknown key in normal or visual mode: beep, clear pending state.
- Counts are capped at 10 000.
- `p` with an empty register: no-op.

## Testing

`WriteKitTests`:
- `VimMotionsTests` — a table of cases per motion over small fixtures.
  Word motions get the vim edge cases: punctuation runs, `w` onto an empty
  line, `e` from the last char of a word, `b` at document start, Unicode
  letters, counts that run off the end.
- `VimStateTests` — key sequences to commands: `dw`, `d2w`, `2dw`, `3.`,
  `cw` special case, `dd` at last line, `0` as digit vs motion, `f` awaiting
  a char then `;`, `gg`/`G` with counts, `Esc` clearing pending, unknown key
  beeping, visual mode extend then operate.

`WriteTests` (real `MarkdownTextView`, synthesized `NSEvent`s):
- opens in normal, `i` types, `Esc` steps back
- `dd` is one undo step; `u` restores
- `o` on a list item continues the list
- `yy` `p` puts below; `yw` `p` puts inline
- `V` `j` `d` deletes two paragraphs
- `⌘S` and `⌘K` still work in normal mode
- footer reads `NORMAL` then `INSERT`
- markers reveal as the caret walks onto a span with `w`
