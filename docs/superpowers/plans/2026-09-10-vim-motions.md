# Vim Motions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Write a modal editor: documents open in normal mode with vim motions, `d`/`c`/`y` operators, counts, visual mode, one register and `.` repeat; insert mode is the editor as it exists today.

**Architecture:** All decisions live in pure `WriteKit` code — `VimMotions` turns a motion into a target position or an operator range over a `String`; `VimState.reduce` is a pure `(state, key, context) → (state, [VimCommand])` state machine. A thin `VimController` in the app executes `VimCommand`s against `MarkdownTextView`, whose `keyDown` routes keys to it. Nothing existing changes shape; the highlighter's marker reveal keeps working because caret moves still go through `setSelectedRange`.

**Tech Stack:** Swift 5.9 package, AppKit, XCTest. Build/test with `./bin/test` (or `swift test --filter <TestClass>`). No Xcode project.

**Spec:** `docs/superpowers/specs/2026-09-10-vim-motions-design.md`

## Global Constraints

- Positions are UTF-16 offsets (`NSRange`, `NSString.character(at:)`), like every other `WriteKit` API.
- `WriteKit` must not import AppKit. Only `Foundation`.
- Vim mode is always on; there is no preference.
- Every motion honours a count; counts are capped at 10 000.
- Tests mirror the style of `Tests/WriteKitTests/WriteKitTests.swift` (one `XCTestCase` per unit, descriptive `testXxx` names, doc comments explaining the mechanism where it is not obvious). New `WriteKit` test classes go in new files under `Tests/WriteKitTests/`; AppKit tests go under `Tests/WriteTests/`.
- Commit after every task with a message in the repo's style: a sentence-case summary line, a blank line, a short paragraph on *why*, and the trailer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Comments in code explain *why*, not *what*, and match the density of neighbouring files.

## File structure

| File | Responsibility |
|---|---|
| `Sources/WriteKit/VimMotions.swift` (new) | Line helpers, character classes, `VimMotion`, `target(of:from:in:count:)`, `operandRange(of:from:in:count:)`, `lineRange(at:in:count:)`, `clampToLine` |
| `Sources/WriteKit/VimState.swift` (new) | `VimMode`, `VimKey`, `VimCommand`, `VimRegister`, `VimChange`, `VimState`, `VimContext`, `VimState.reduce` |
| `Sources/Write/VimController.swift` (new) | Owns a `VimState`; maps `NSEvent` → `VimKey`; executes `VimCommand`s on `MarkdownTextView`; exposes `modeText` |
| `Sources/Write/MarkdownTextView.swift` (modify) | `keyDown` routing, block caret in `drawInsertionPoint` |
| `Sources/Write/FooterView.swift` (modify) | A `mode` label left of the existing status label |
| `Sources/Write/EditorViewController.swift` (modify) | Creates the controller, wires it to the footer |
| `Sources/Write/ShortcutsPanel.swift`, `README.md` (modify) | Document the modes |
| `Tests/WriteKitTests/VimMotionsTests.swift`, `VimStateTests.swift` (new) | Pure tests |
| `Tests/WriteTests/VimControllerTests.swift` (new) | Real `MarkdownTextView` driven by synthesized key events |

---

### Task 1: Line helpers and the simple motions (`h` `l` `0` `^` `$`)

**Files:**
- Create: `Sources/WriteKit/VimMotions.swift`
- Test: `Tests/WriteKitTests/VimMotionsTests.swift`

**Interfaces:**
- Produces: `public enum VimMotion`, `public enum VimMotions` with `lineStart(of:in:)`, `lineEnd(of:in:)`, `firstNonBlank(ofLineAt:in:)`, `lineIsEmpty(containing:in:)`, `clampToLine(_:in:)`, `target(of:from:in:count:) -> Int?`. All take `text: String`; internally convert once with `text as NSString`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/WriteKitTests/VimMotionsTests.swift
import XCTest
@testable import WriteKit

final class VimMotionsTests: XCTestCase {
    // Positions are UTF-16 offsets into these fixtures.
    private let twoLines = "abc def\nghi"          // "\n" is at 7
    private let indented = "  lead\n\nlast"         // empty line at 7, "last" starts at 8

    func testLineBoundaries() {
        XCTAssertEqual(VimMotions.lineStart(of: 5, in: twoLines), 0)
        XCTAssertEqual(VimMotions.lineEnd(of: 5, in: twoLines), 7)
        XCTAssertEqual(VimMotions.lineStart(of: 9, in: twoLines), 8)
        XCTAssertEqual(VimMotions.lineEnd(of: 9, in: twoLines), 11)
        XCTAssertEqual(VimMotions.firstNonBlank(ofLineAt: 0, in: indented), 2)
        XCTAssertTrue(VimMotions.lineIsEmpty(containing: 7, in: indented))
        XCTAssertFalse(VimMotions.lineIsEmpty(containing: 8, in: indented))
    }

    func testNormalModeCaretCannotRestPastTheLastCharacter() {
        XCTAssertEqual(VimMotions.clampToLine(7, in: twoLines), 6, "on the newline → last char")
        XCTAssertEqual(VimMotions.clampToLine(11, in: twoLines), 10, "past the end → last char")
        XCTAssertEqual(VimMotions.clampToLine(7, in: indented), 7, "an empty line keeps its position")
        XCTAssertEqual(VimMotions.clampToLine(3, in: twoLines), 3)
    }

    func testLeftAndRightStopAtTheLineEnds() {
        XCTAssertEqual(VimMotions.target(of: .right, from: 0, in: twoLines), 1)
        XCTAssertEqual(VimMotions.target(of: .right, from: 0, in: twoLines, count: 3), 3)
        XCTAssertEqual(VimMotions.target(of: .right, from: 5, in: twoLines, count: 9), 6, "count runs off the end")
        XCTAssertNil(VimMotions.target(of: .right, from: 6, in: twoLines), "already on the last char")
        XCTAssertEqual(VimMotions.target(of: .left, from: 3, in: twoLines, count: 2), 1)
        XCTAssertNil(VimMotions.target(of: .left, from: 8, in: twoLines), "start of a line")
    }

    func testLineStartFirstNonBlankAndLineEnd() {
        XCTAssertEqual(VimMotions.target(of: .lineStart, from: 5, in: indented), 0)
        XCTAssertEqual(VimMotions.target(of: .firstNonBlank, from: 5, in: indented), 2)
        XCTAssertEqual(VimMotions.target(of: .lineEnd, from: 0, in: twoLines), 6)
        XCTAssertEqual(VimMotions.target(of: .lineEnd, from: 0, in: twoLines, count: 2), 10, "2$ ends the next line")
        XCTAssertEqual(VimMotions.target(of: .lineEnd, from: 7, in: indented), 7, "empty line")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter VimMotionsTests`
Expected: compile error — `cannot find 'VimMotions' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/WriteKit/VimMotions.swift
import Foundation

/// The motions normal mode understands. `displayLineDown`/`Up` (`j`/`k`)
/// depend on layout and are carried out by the text view; everything else is
/// pure string arithmetic here.
public enum VimMotion: Equatable {
    case left, right
    case wordForward(big: Bool), wordBackward(big: Bool), wordEnd(big: Bool)
    case lineStart, firstNonBlank, lineEnd
    case documentStart, documentEnd, line(Int)
    case paragraphBackward, paragraphForward
    case find(Character, forward: Bool, till: Bool)
    case displayLineDown, displayLineUp
}

public enum VimMotions {
    static let newline: unichar = 0x0A

    // MARK: - Lines

    public static func lineStart(of position: Int, in text: String) -> Int {
        lineStart(of: position, in: text as NSString)
    }

    public static func lineEnd(of position: Int, in text: String) -> Int {
        lineEnd(of: position, in: text as NSString)
    }

    public static func firstNonBlank(ofLineAt position: Int, in text: String) -> Int {
        firstNonBlank(ofLineAt: position, in: text as NSString)
    }

    public static func lineIsEmpty(containing position: Int, in text: String) -> Bool {
        let t = text as NSString
        return lineStart(of: position, in: t) == lineEnd(of: position, in: t)
    }

    /// Normal mode's caret sits on a character, never after the last one
    /// (an empty line is the exception: its caret sits on the terminator).
    public static func clampToLine(_ position: Int, in text: String) -> Int {
        let t = text as NSString
        let p = min(max(position, 0), t.length)
        let start = lineStart(of: p, in: t)
        let end = lineEnd(of: p, in: t)
        return p >= end && end > start ? end - 1 : p
    }

    static func lineStart(of position: Int, in t: NSString) -> Int {
        var i = min(max(position, 0), t.length)
        while i > 0, t.character(at: i - 1) != newline { i -= 1 }
        return i
    }

    /// The index of the line's newline, or `length` on the last line.
    static func lineEnd(of position: Int, in t: NSString) -> Int {
        var i = min(max(position, 0), t.length)
        while i < t.length, t.character(at: i) != newline { i += 1 }
        return i
    }

    static func firstNonBlank(ofLineAt position: Int, in t: NSString) -> Int {
        var i = lineStart(of: position, in: t)
        let end = lineEnd(of: position, in: t)
        while i < end, isBlank(t.character(at: i)) { i += 1 }
        return i
    }

    static func isBlank(_ c: unichar) -> Bool {
        c == 0x20 || c == 0x09
    }

    // MARK: - Targets

    /// Where `motion` lands from `position`, or nil when it cannot move at
    /// all. The result may be `text.length` (past the end) or sit on a
    /// newline; normal mode clamps with `clampToLine`, operators use it as is.
    public static func target(of motion: VimMotion, from position: Int, in text: String,
                              count: Int = 1) -> Int? {
        let t = text as NSString
        let n = max(1, min(count, 10_000))
        let p = min(max(position, 0), t.length)

        switch motion {
        case .left:
            let start = lineStart(of: p, in: t)
            return p > start ? max(start, p - n) : nil
        case .right:
            let last = max(lineStart(of: p, in: t), lineEnd(of: p, in: t) - 1)
            return p < last ? min(last, p + n) : nil
        case .lineStart:
            return lineStart(of: p, in: t)
        case .firstNonBlank:
            return firstNonBlank(ofLineAt: p, in: t)
        case .lineEnd:
            var line = p
            for _ in 1..<n {
                let end = lineEnd(of: line, in: t)
                guard end < t.length else { break }
                line = end + 1
            }
            let end = lineEnd(of: line, in: t)
            return end > lineStart(of: line, in: t) ? end - 1 : end
        default:
            return nil   // filled in by later tasks
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter VimMotionsTests`
Expected: 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/WriteKit/VimMotions.swift Tests/WriteKitTests/VimMotionsTests.swift
git commit -m "Vim motions: line helpers, h l 0 ^ \$

The first slice of a modal editor. Everything about where a motion
lands is decided over a plain string in WriteKit so it can be tested
without a window.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Word motions (`w` `b` `e` `W` `B` `E`)

**Files:**
- Modify: `Sources/WriteKit/VimMotions.swift`
- Test: `Tests/WriteKitTests/VimMotionsTests.swift`

**Interfaces:**
- Produces: `.wordForward/.wordBackward/.wordEnd(big:)` handled by `target`; internal `CharClass` and `charClass(_:big:)`.

- [ ] **Step 1: Write the failing tests** (append inside `VimMotionsTests`)

```swift
    // "foo.bar baz\n\nqux" — punctuation run, blank, empty line, more.
    //  0123456789012 3 4567
    private let words = "foo.bar baz\n\nqux"

    func testWordForwardUsesVimWordClasses() {
        XCTAssertEqual(VimMotions.target(of: .wordForward(big: false), from: 0, in: words), 3, "stops on the dot")
        XCTAssertEqual(VimMotions.target(of: .wordForward(big: false), from: 3, in: words), 4)
        XCTAssertEqual(VimMotions.target(of: .wordForward(big: true), from: 0, in: words), 8, "W skips punctuation")
        XCTAssertEqual(VimMotions.target(of: .wordForward(big: false), from: 8, in: words), 12, "w stops on an empty line")
        XCTAssertEqual(VimMotions.target(of: .wordForward(big: false), from: 12, in: words), 13)
        XCTAssertEqual(VimMotions.target(of: .wordForward(big: false), from: 0, in: words, count: 3), 8)
        XCTAssertEqual(VimMotions.target(of: .wordForward(big: false), from: 13, in: words), 16, "last word → past the end, for operators")
        XCTAssertNil(VimMotions.target(of: .wordForward(big: false), from: 16, in: words))
    }

    func testWordEndLandsOnTheLastCharacterOfAWord() {
        XCTAssertEqual(VimMotions.target(of: .wordEnd(big: false), from: 0, in: words), 2)
        XCTAssertEqual(VimMotions.target(of: .wordEnd(big: false), from: 2, in: words), 3, "from a word's end, on to the next run")
        XCTAssertEqual(VimMotions.target(of: .wordEnd(big: true), from: 0, in: words), 6)
        XCTAssertEqual(VimMotions.target(of: .wordEnd(big: false), from: 8, in: words), 15, "e crosses the empty line without stopping")
        XCTAssertNil(VimMotions.target(of: .wordEnd(big: false), from: 15, in: words))
    }

    func testWordBackward() {
        XCTAssertEqual(VimMotions.target(of: .wordBackward(big: false), from: 15, in: words), 13)
        XCTAssertEqual(VimMotions.target(of: .wordBackward(big: false), from: 13, in: words), 12, "b stops on the empty line")
        XCTAssertEqual(VimMotions.target(of: .wordBackward(big: false), from: 12, in: words), 8)
        XCTAssertEqual(VimMotions.target(of: .wordBackward(big: false), from: 6, in: words), 4, "from inside a word, to its start")
        XCTAssertEqual(VimMotions.target(of: .wordBackward(big: true), from: 8, in: words), 0)
        XCTAssertEqual(VimMotions.target(of: .wordBackward(big: false), from: 15, in: words, count: 10), 0, "count runs off the start")
        XCTAssertNil(VimMotions.target(of: .wordBackward(big: false), from: 0, in: words))
    }

    func testUnicodeLettersAreWordCharacters() {
        let text = "café über"
        XCTAssertEqual(VimMotions.target(of: .wordForward(big: false), from: 0, in: text), 5)
        XCTAssertEqual(VimMotions.target(of: .wordEnd(big: false), from: 0, in: text), 3)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter VimMotionsTests`
Expected: the four new tests fail (`target` returns nil for word motions).

- [ ] **Step 3: Write the implementation** — add to `VimMotions`, and replace the `default: return nil` in `target` with the three new cases.

```swift
    // MARK: - Words

    /// Vim's three classes: blank, a run of punctuation, a run of word
    /// characters. `big` (W/B/E) collapses the last two.
    enum CharClass { case blank, punctuation, word }

    static func charClass(_ c: unichar, big: Bool) -> CharClass {
        if c == newline || isBlank(c) { return .blank }
        if big { return .word }
        guard let scalar = Unicode.Scalar(c) else { return .word }   // surrogate half: part of a word
        if scalar == "_" || CharacterSet.alphanumerics.contains(scalar) { return .word }
        return .punctuation
    }

    /// An empty line is a word of its own for `w` and `b`.
    static func isEmptyLine(at i: Int, in t: NSString) -> Bool {
        i < t.length && t.character(at: i) == newline && (i == 0 || t.character(at: i - 1) == newline)
    }

    static func wordForwardOnce(from p: Int, in t: NSString, big: Bool) -> Int? {
        let n = t.length
        guard p < n else { return nil }
        var i = p
        let startClass = charClass(t.character(at: i), big: big)
        if startClass != .blank {
            while i < n, t.character(at: i) != newline,
                  charClass(t.character(at: i), big: big) == startClass { i += 1 }
        }
        while i < n, charClass(t.character(at: i), big: big) == .blank {
            if i != p, isEmptyLine(at: i, in: t) { return i }
            i += 1
        }
        return i == p ? nil : i
    }

    static func wordEndOnce(from p: Int, in t: NSString, big: Bool) -> Int? {
        let n = t.length
        var i = p + 1
        while i < n, charClass(t.character(at: i), big: big) == .blank { i += 1 }
        guard i < n else { return nil }
        let c = charClass(t.character(at: i), big: big)
        while i + 1 < n, t.character(at: i + 1) != newline,
              charClass(t.character(at: i + 1), big: big) == c { i += 1 }
        return i
    }

    static func wordBackwardOnce(from p: Int, in t: NSString, big: Bool) -> Int? {
        guard p > 0 else { return nil }
        var i = p - 1
        while i > 0, charClass(t.character(at: i), big: big) == .blank {
            if isEmptyLine(at: i, in: t) { return i }
            i -= 1
        }
        if charClass(t.character(at: i), big: big) == .blank { return 0 }
        let c = charClass(t.character(at: i), big: big)
        while i > 0, t.character(at: i - 1) != newline,
              charClass(t.character(at: i - 1), big: big) == c { i -= 1 }
        return i
    }

    /// Applies a single-step motion `count` times, keeping the last position
    /// that moved so a count that runs off the end still goes as far as it can.
    static func repeated(_ count: Int, from p: Int, _ step: (Int) -> Int?) -> Int? {
        var position = p
        var moved = false
        for _ in 0..<count {
            guard let next = step(position) else { break }
            position = next
            moved = true
        }
        return moved ? position : nil
    }
```

In `target(of:from:in:count:)`:

```swift
        case .wordForward(let big):
            return repeated(n, from: p) { wordForwardOnce(from: $0, in: t, big: big) }
        case .wordEnd(let big):
            return repeated(n, from: p) { wordEndOnce(from: $0, in: t, big: big) }
        case .wordBackward(let big):
            return repeated(n, from: p) { wordBackwardOnce(from: $0, in: t, big: big) }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter VimMotionsTests`
Expected: 8 tests, 0 failures. If `testWordForwardUsesVimWordClasses` fails on the `from: 13 → 16` case, check that `wordForwardOnce` returns `i` (which equals `n`) rather than nil when it walks off the end.

- [ ] **Step 5: Commit**

```bash
git add Sources/WriteKit/VimMotions.swift Tests/WriteKitTests/VimMotionsTests.swift
git commit -m "Vim motions: w b e and their blank-delimited forms

Vim's word classes rather than AppKit's, so punctuation runs are words,
empty lines stop w and b, and accented letters are letters.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Document, paragraph and find motions (`gg` `G` `{` `}` `f` `t` `F` `T`)

**Files:**
- Modify: `Sources/WriteKit/VimMotions.swift`
- Test: `Tests/WriteKitTests/VimMotionsTests.swift`

- [ ] **Step 1: Write the failing tests** (append inside `VimMotionsTests`)

```swift
    private let paragraphs = "one\ntwo\n\n  three\nfour\n\nfive"
    //                        0123 4567 8 9   13   18   22 23 24

    func testDocumentStartEndAndLineNumbers() {
        XCTAssertEqual(VimMotions.target(of: .documentStart, from: 20, in: paragraphs), 0)
        XCTAssertEqual(VimMotions.target(of: .documentEnd, from: 0, in: paragraphs), 24, "G → first non-blank of the last line")
        XCTAssertEqual(VimMotions.target(of: .line(4), from: 0, in: paragraphs), 11, "4G → first non-blank of line 4")
        XCTAssertEqual(VimMotions.target(of: .line(99), from: 0, in: paragraphs), 24, "past the end → last line")
    }

    func testParagraphMotionsStopOnEmptyLines() {
        XCTAssertEqual(VimMotions.target(of: .paragraphForward, from: 0, in: paragraphs), 8)
        XCTAssertEqual(VimMotions.target(of: .paragraphForward, from: 8, in: paragraphs), 23, "from an empty line, past the next paragraph")
        XCTAssertEqual(VimMotions.target(of: .paragraphForward, from: 24, in: paragraphs), 28, "no more → past the end")
        XCTAssertEqual(VimMotions.target(of: .paragraphBackward, from: 26, in: paragraphs), 23)
        XCTAssertEqual(VimMotions.target(of: .paragraphBackward, from: 23, in: paragraphs), 8)
        XCTAssertEqual(VimMotions.target(of: .paragraphBackward, from: 5, in: paragraphs), 0, "first paragraph → document start")
        XCTAssertEqual(VimMotions.target(of: .paragraphForward, from: 0, in: paragraphs, count: 2), 23)
    }

    func testFindWithinTheLine() {
        let line = "a-b-c-d\ne-f"
        XCTAssertEqual(VimMotions.target(of: .find("-", forward: true, till: false), from: 0, in: line), 1)
        XCTAssertEqual(VimMotions.target(of: .find("-", forward: true, till: false), from: 0, in: line, count: 3), 5)
        XCTAssertEqual(VimMotions.target(of: .find("-", forward: true, till: true), from: 0, in: line), 0 + 0, "t stops just before; already there → nil")
        XCTAssertEqual(VimMotions.target(of: .find("c", forward: true, till: true), from: 0, in: line), 3)
        XCTAssertEqual(VimMotions.target(of: .find("a", forward: false, till: false), from: 6, in: line), 0)
        XCTAssertEqual(VimMotions.target(of: .find("a", forward: false, till: true), from: 6, in: line), 1)
        XCTAssertNil(VimMotions.target(of: .find("e", forward: true, till: false), from: 0, in: line), "does not cross lines")
        XCTAssertNil(VimMotions.target(of: .find("z", forward: true, till: false), from: 0, in: line))
    }
```

Replace the odd `0 + 0` assertion above with the real expectation: `t-` from 0 on `"a-b-c-d"` lands on 0, which is no movement, so it returns nil:

```swift
        XCTAssertNil(VimMotions.target(of: .find("-", forward: true, till: true), from: 0, in: line), "t to an adjacent char is no movement")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter VimMotionsTests`
Expected: the three new tests fail.

- [ ] **Step 3: Write the implementation** — add cases to `target` and these helpers.

```swift
        case .documentStart:
            return firstNonBlank(ofLineAt: 0, in: t)
        case .documentEnd:
            return firstNonBlank(ofLineAt: t.length, in: t)
        case .line(let number):
            return firstNonBlank(ofLineAt: startOfLine(number: number, in: t), in: t)
        case .paragraphForward:
            return repeated(n, from: p) { paragraphForwardOnce(from: $0, in: t) }
        case .paragraphBackward:
            return repeated(n, from: p) { paragraphBackwardOnce(from: $0, in: t) }
        case .find(let character, let forward, let till):
            return find(character, from: p, in: t, forward: forward, till: till, count: n)
```

```swift
    // MARK: - Lines by number, paragraphs, find

    /// The start of 1-based line `number`, or of the last line when there
    /// are fewer.
    static func startOfLine(number: Int, in t: NSString) -> Int {
        var start = 0
        var remaining = max(1, number) - 1
        while remaining > 0 {
            let end = lineEnd(of: start, in: t)
            guard end < t.length else { break }
            start = end + 1
            remaining -= 1
        }
        return start
    }

    static func lineIsEmpty(containing i: Int, in t: NSString) -> Bool {
        lineStart(of: i, in: t) == lineEnd(of: i, in: t)
    }

    /// `}`: past the current paragraph to the next empty line, or past the
    /// end of the text when there is none.
    static func paragraphForwardOnce(from p: Int, in t: NSString) -> Int? {
        let n = t.length
        guard p < n else { return nil }
        var i = p
        while i < n, lineIsEmpty(containing: i, in: t) { i = lineEnd(of: i, in: t) + 1 }
        while i < n, !lineIsEmpty(containing: i, in: t) { i = lineEnd(of: i, in: t) + 1 }
        return min(i, n)
    }

    /// `{`: back over the current paragraph to the previous empty line, or
    /// to the start of the text.
    static func paragraphBackwardOnce(from p: Int, in t: NSString) -> Int? {
        guard p > 0 else { return nil }
        var i = lineStart(of: p, in: t)
        func previous(_ start: Int) -> Int? { start > 0 ? lineStart(of: start - 1, in: t) : nil }
        guard var cursor = previous(i) else { return 0 }
        i = cursor
        while lineIsEmpty(containing: cursor, in: t), let before = previous(cursor) { cursor = before }
        while !lineIsEmpty(containing: cursor, in: t), let before = previous(cursor) { cursor = before }
        return lineIsEmpty(containing: cursor, in: t) ? cursor : 0
    }

    static func find(_ character: Character, from p: Int, in t: NSString,
                     forward: Bool, till: Bool, count: Int) -> Int? {
        let wanted = String(character) as NSString
        guard wanted.length == 1 else { return nil }
        let unit = wanted.character(at: 0)
        var i = p
        var found = 0
        if forward {
            let end = lineEnd(of: p, in: t)
            while found < count {
                i += 1
                guard i < end else { return nil }
                if t.character(at: i) == unit { found += 1 }
            }
            let target = till ? i - 1 : i
            return target > p ? target : nil
        } else {
            let start = lineStart(of: p, in: t)
            while found < count {
                i -= 1
                guard i >= start else { return nil }
                if t.character(at: i) == unit { found += 1 }
            }
            let target = till ? i + 1 : i
            return target < p ? target : nil
        }
    }
```

Note `paragraphBackwardOnce` has a redundant `i = cursor` line after the guard; drop it — `i` is only needed for the initial `lineStart`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter VimMotionsTests`
Expected: 11 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/WriteKit/VimMotions.swift Tests/WriteKitTests/VimMotionsTests.swift
git commit -m "Vim motions: gg G { } and f t F T

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Operator ranges (`operandRange`, `lineRange`)

**Files:**
- Modify: `Sources/WriteKit/VimMotions.swift`
- Test: `Tests/WriteKitTests/VimMotionsTests.swift`

**Interfaces:**
- Produces: `public struct VimOperandRange { range: NSRange; linewise: Bool }`, `VimMotions.operandRange(of:from:in:count:) -> VimOperandRange?`, `VimMotions.lineRange(at:in:count:) -> VimOperandRange`, `VimMotions.linesRange(from:to:in:) -> VimOperandRange`. The reducer (Task 6) uses these for every operator.

- [ ] **Step 1: Write the failing tests** (append inside `VimMotionsTests`)

```swift
    func testExclusiveInclusiveAndLinewiseRanges() {
        let text = "foo bar\nbaz"
        // dw: exclusive — the next word's first char survives.
        XCTAssertEqual(VimMotions.operandRange(of: .wordForward(big: false), from: 0, in: text),
                       VimOperandRange(range: NSRange(location: 0, length: 4), linewise: false))
        // de: inclusive — the word's last char goes too.
        XCTAssertEqual(VimMotions.operandRange(of: .wordEnd(big: false), from: 0, in: text),
                       VimOperandRange(range: NSRange(location: 0, length: 3), linewise: false))
        // d$: inclusive to the end of the line, never the newline.
        XCTAssertEqual(VimMotions.operandRange(of: .lineEnd, from: 4, in: text),
                       VimOperandRange(range: NSRange(location: 4, length: 3), linewise: false))
        // db: backwards ranges are normalised.
        XCTAssertEqual(VimMotions.operandRange(of: .wordBackward(big: false), from: 6, in: text),
                       VimOperandRange(range: NSRange(location: 4, length: 2), linewise: false))
        // dG: linewise from this line to the end.
        XCTAssertEqual(VimMotions.operandRange(of: .documentEnd, from: 1, in: text),
                       VimOperandRange(range: NSRange(location: 0, length: 11), linewise: true))
    }

    func testDeleteWordOnTheLastWordOfALineStopsAtTheLine() {
        // Vim's special case: dw never eats the newline.
        let text = "foo bar\nbaz"
        XCTAssertEqual(VimMotions.operandRange(of: .wordForward(big: false), from: 4, in: text),
                       VimOperandRange(range: NSRange(location: 4, length: 3), linewise: false))
    }

    func testFailedMotionGivesNoRange() {
        XCTAssertNil(VimMotions.operandRange(of: .left, from: 0, in: "abc"))
        XCTAssertNil(VimMotions.operandRange(of: .find("z", forward: true, till: false), from: 0, in: "abc"))
    }

    func testLineRangesIncludeTheNewlineOrEatThePrecedingOne() {
        let text = "one\ntwo\nthree"
        XCTAssertEqual(VimMotions.lineRange(at: 5, in: text),
                       VimOperandRange(range: NSRange(location: 4, length: 4), linewise: true), "dd on a middle line")
        XCTAssertEqual(VimMotions.lineRange(at: 0, in: text, count: 2),
                       VimOperandRange(range: NSRange(location: 0, length: 8), linewise: true), "2dd")
        XCTAssertEqual(VimMotions.lineRange(at: 10, in: text),
                       VimOperandRange(range: NSRange(location: 7, length: 6), linewise: true), "dd on the last line takes the newline before it")
        XCTAssertEqual(VimMotions.lineRange(at: 0, in: "only"),
                       VimOperandRange(range: NSRange(location: 0, length: 4), linewise: true))
        XCTAssertEqual(VimMotions.linesRange(from: 9, to: 1, in: text),
                       VimOperandRange(range: NSRange(location: 0, length: 13), linewise: true), "dk from the last line")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter VimMotionsTests`
Expected: compile error — `cannot find 'VimOperandRange' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
/// What an operator acts on: the range and whether it is whole lines.
public struct VimOperandRange: Equatable {
    public let range: NSRange
    public let linewise: Bool

    public init(range: NSRange, linewise: Bool) {
        self.range = range
        self.linewise = linewise
    }
}
```

Add to `VimMotions`:

```swift
    // MARK: - Operator ranges

    /// The text an operator covers when combined with `motion`, following
    /// vim's exclusive / inclusive / linewise rules. Nil when the motion
    /// cannot move, in which case the operator is cancelled.
    public static func operandRange(of motion: VimMotion, from position: Int, in text: String,
                                    count: Int = 1) -> VimOperandRange? {
        let t = text as NSString
        let p = min(max(position, 0), t.length)

        switch motion {
        case .documentStart, .documentEnd, .line, .displayLineDown, .displayLineUp:
            let n = max(1, min(count, 10_000))
            switch motion {
            case .displayLineDown:
                return linesRange(from: p, to: startOfLine(number: lineNumber(of: p, in: t) + n, in: t), in: text)
            case .displayLineUp:
                return linesRange(from: p, to: startOfLine(number: max(1, lineNumber(of: p, in: t) - n), in: text as NSString), in: text)
            default:
                guard let target = target(of: motion, from: p, in: text, count: count) else { return nil }
                return linesRange(from: p, to: target, in: text)
            }
        default:
            guard var target = target(of: motion, from: p, in: text, count: count) else { return nil }
            let inclusive: Bool
            switch motion {
            case .wordEnd, .lineEnd: inclusive = true
            case .find(_, _, let till): inclusive = !till || true   // f and t are inclusive
            default: inclusive = false
            }
            if case .find(_, let forward, _) = motion, !forward {
                // F and T are exclusive.
                return VimOperandRange(range: NSRange(location: target, length: p - target), linewise: false)
            }
            if case .wordForward = motion, target > lineEnd(of: p, in: t) {
                // dw on the last word of a line stops at the line, never
                // the newline.
                target = lineEnd(of: p, in: t)
            }
            if case .lineEnd = motion, lineIsEmpty(containing: target, in: t) {
                return VimOperandRange(range: NSRange(location: p, length: 0), linewise: false)
            }
            var lo = min(p, target)
            var hi = max(p, target)
            if inclusive { hi = min(hi + 1, t.length) }
            if hi > lo, t.character(at: hi - 1) == newline, !inclusive { hi -= 0 }   // exclusive never includes a newline it ends on
            lo = max(0, lo)
            return VimOperandRange(range: NSRange(location: lo, length: hi - lo), linewise: false)
        }
    }

    /// Whole lines from the one at `position`, `count` of them: for `dd`,
    /// `yy`, `cc`. Takes the trailing newline, or the preceding one on the
    /// last line, so deleting a line never leaves an empty one behind.
    public static func lineRange(at position: Int, in text: String, count: Int = 1) -> VimOperandRange {
        let t = text as NSString
        let n = max(1, min(count, 10_000))
        let start = lineStart(of: position, in: t)
        return linesRange(from: start, to: startOfLine(number: lineNumber(of: start, in: t) + n - 1, in: t), in: text)
    }

    /// Whole lines spanning the two positions, in either order.
    public static func linesRange(from a: Int, to b: Int, in text: String) -> VimOperandRange {
        let t = text as NSString
        var lo = lineStart(of: min(a, b), in: t)
        var hi = lineEnd(of: max(a, b), in: t)
        if hi < t.length {
            hi += 1
        } else if lo > 0 {
            lo -= 1
        }
        return VimOperandRange(range: NSRange(location: lo, length: hi - lo), linewise: true)
    }

    /// 1-based, like `G` counts.
    static func lineNumber(of position: Int, in t: NSString) -> Int {
        var number = 1
        var i = 0
        let p = min(max(position, 0), t.length)
        while i < p {
            if t.character(at: i) == newline { number += 1 }
            i += 1
        }
        return number
    }
```

Clean-ups the implementer must make while writing this (the sketch above has two smells left in deliberately so they are noticed): the `inclusive = !till || true` line is just `inclusive = true`, and the `if hi > lo … hi -= 0` line is a no-op — delete it. `lineIsEmpty(containing:in:)` for `NSString` was added in Task 3; keep one definition.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter VimMotionsTests`
Expected: 15 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/WriteKit/VimMotions.swift Tests/WriteKitTests/VimMotionsTests.swift
git commit -m "Vim motions: the ranges operators act on

Exclusive, inclusive and linewise per vim, including dw stopping at the
end of its line and dd on the last line taking the newline before it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: The state machine — types and normal-mode movement

**Files:**
- Create: `Sources/WriteKit/VimState.swift`
- Test: `Tests/WriteKitTests/VimStateTests.swift`

**Interfaces:**
- Produces (used verbatim by Tasks 6–10):

```swift
public enum VimMode: Equatable { case normal, insert, visual, visualLine }
public enum VimKey: Equatable { case char(Character), escape, returnKey, backspace, control(Character) }
public enum VimCommand: Equatable {
    case moveCaret(to: Int)
    case moveDisplayLines(Int)               // positive = down
    case select(NSRange)                     // visual mode selection
    case replace(NSRange, with: String, caretAt: Int)
    case insertText(String)                  // at the caret; used by `.` for insert sessions and counts on i/a/…
    case smartReturn(after: Bool)            // o (true) / O (false)
    case setMode(VimMode)
    case undo, redo, beep
}
public struct VimRegister: Equatable { public let text: String; public let linewise: Bool }
public struct VimContext { public let text: String; public let caret: Int; public init(text:caret:) }
public struct VimState: Equatable { public var mode: VimMode; … ; public var pendingText: String; public init() }
extension VimState { public static func reduce(_ state: VimState, key: VimKey, context: VimContext) -> (VimState, [VimCommand]) }
```

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/WriteKitTests/VimStateTests.swift
import XCTest
@testable import WriteKit

final class VimStateTests: XCTestCase {
    /// Feeds `keys` through the reducer against a fixed document and returns
    /// every command produced plus the final state.
    private func run(_ keys: String, text: String, caret: Int,
                     from state: VimState = VimState()) -> (VimState, [VimCommand]) {
        var state = state
        var commands: [VimCommand] = []
        for character in keys {
            let key: VimKey = character == "\u{1B}" ? .escape : .char(character)
            let (next, produced) = VimState.reduce(state, key: key,
                                                   context: VimContext(text: text, caret: caret))
            state = next
            commands += produced
        }
        return (state, commands)
    }

    private let esc = "\u{1B}"

    func testOpensInNormalMode() {
        XCTAssertEqual(VimState().mode, .normal)
    }

    func testMotionsMoveTheCaret() {
        let (_, commands) = run("l", text: "abc", caret: 0)
        XCTAssertEqual(commands, [.moveCaret(to: 1)])
        XCTAssertEqual(run("w", text: "foo bar", caret: 0).1, [.moveCaret(to: 4)])
        XCTAssertEqual(run("$", text: "foo bar", caret: 0).1, [.moveCaret(to: 6)])
        XCTAssertEqual(run("G", text: "a\nb", caret: 0).1, [.moveCaret(to: 2)])
    }

    func testCountsMultiplyMotions() {
        XCTAssertEqual(run("3l", text: "abcdef", caret: 0).1, [.moveCaret(to: 3)])
        XCTAssertEqual(run("12l", text: String(repeating: "x", count: 30), caret: 0).1, [.moveCaret(to: 12)])
        XCTAssertEqual(run("2G", text: "a\nb\nc", caret: 0).1, [.moveCaret(to: 2)])
        XCTAssertEqual(run("0", text: "abc", caret: 2).1, [.moveCaret(to: 0)], "0 alone is a motion")
        XCTAssertEqual(run("10l", text: String(repeating: "x", count: 30), caret: 0).1, [.moveCaret(to: 10)], "0 after a digit is a digit")
    }

    func testDisplayLinesAreDelegated() {
        XCTAssertEqual(run("j", text: "a\nb", caret: 0).1, [.moveDisplayLines(1)])
        XCTAssertEqual(run("3k", text: "a\nb", caret: 0).1, [.moveDisplayLines(-3)])
    }

    func testPrefixesAwaitTheirSecondKey() {
        let (pending, none) = run("g", text: "abc", caret: 2)
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(pending.pendingText, "g")
        XCTAssertEqual(run("gg", text: "a\nb", caret: 2).1, [.moveCaret(to: 0)])
        XCTAssertEqual(run("fc", text: "abc", caret: 0).1, [.moveCaret(to: 2)])
        XCTAssertEqual(run("tc", text: "abc", caret: 0).1, [.moveCaret(to: 1)])
        XCTAssertEqual(run("fb;", text: "abab", caret: 0).1, [.moveCaret(to: 1), .moveCaret(to: 3)], "; repeats")
        XCTAssertEqual(run("fb;,", text: "abab", caret: 0).1, [.moveCaret(to: 1), .moveCaret(to: 3), .moveCaret(to: 1)], ", reverses")
    }

    func testEscapeClearsPendingStateAndUnknownKeysBeep() {
        let (state, commands) = run("3d" + esc, text: "abc", caret: 0)
        XCTAssertEqual(state.pendingText, "")
        XCTAssertTrue(commands.isEmpty)
        XCTAssertEqual(run("Q", text: "abc", caret: 0).1, [.beep])
        XCTAssertEqual(run("gQ", text: "abc", caret: 0).1, [.beep], "g followed by nonsense")
    }

    func testAMotionThatCannotMoveDoesNothing() {
        XCTAssertTrue(run("h", text: "abc", caret: 0).1.isEmpty)
        XCTAssertTrue(run("l", text: "abc", caret: 2).1.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter VimStateTests`
Expected: compile error — `cannot find 'VimState' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/WriteKit/VimState.swift
import Foundation

public enum VimMode: Equatable {
    case normal, insert, visual, visualLine
}

/// A key as vim sees it. Command-key shortcuts never reach the reducer.
public enum VimKey: Equatable {
    case char(Character)
    case escape
    case returnKey
    case backspace
    case control(Character)
}

/// Everything the reducer can ask the text view to do. This is the whole
/// surface between the pure state machine and AppKit.
public enum VimCommand: Equatable {
    case moveCaret(to: Int)
    case moveDisplayLines(Int)
    case select(NSRange)
    case replace(NSRange, with: String, caretAt: Int)
    case insertText(String)
    case smartReturn(after: Bool)
    case setMode(VimMode)
    case undo
    case redo
    case beep
}

public struct VimRegister: Equatable {
    public let text: String
    public let linewise: Bool

    public init(text: String, linewise: Bool) {
        self.text = text
        self.linewise = linewise
    }
}

/// The last change, for `.`: either the normal-mode keys that made it, or an
/// insert session (how it was entered and what was typed).
public enum VimChange: Equatable {
    case keys([VimKey], count: Int?)
    case insert(entry: VimKey, text: String, count: Int?)
}

/// What the reducer needs to know about the document right now.
public struct VimContext {
    public let text: String
    public let caret: Int

    public init(text: String, caret: Int) {
        self.text = text
        self.caret = caret
    }
}

struct VimFind: Equatable {
    let character: Character
    let forward: Bool
    let till: Bool
}

enum VimPrefix: Equatable {
    case g
    case find(forward: Bool, till: Bool)
}

public struct VimState: Equatable {
    public var mode: VimMode = .normal
    /// Digits typed since the last operator (or since the start).
    var count: Int?
    /// Digits typed before the operator, for `2dw`.
    var operatorCount: Int?
    var pendingOperator: Character?
    var prefix: VimPrefix?
    var lastFind: VimFind?
    var visualAnchor: Int?
    public var register: VimRegister?
    var lastChange: VimChange?
    /// Keys typed since pending state began, replayed into `lastChange`.
    var pendingKeys: [VimKey] = []
    /// The current insert session, for `.`: nil once it stops being a
    /// straightforward run of typed characters.
    var insertEntry: VimKey?
    var insertCount: Int?
    var insertedText: String? = ""

    public init() {}

    /// What the footer shows after the mode: "d2", "f", "3".
    public var pendingText: String {
        var text = ""
        if let operatorCount { text += String(operatorCount) }
        if let pendingOperator { text.append(pendingOperator) }
        if let count { text += String(count) }
        switch prefix {
        case .g?: text += "g"
        case .find(let forward, let till)?: text += till ? (forward ? "t" : "T") : (forward ? "f" : "F")
        case nil: break
        }
        return text
    }

    var effectiveCount: Int {
        let total = (operatorCount ?? 1) * (count ?? 1)
        return max(1, min(total, 10_000))
    }

    var hasExplicitCount: Bool { count != nil || operatorCount != nil }

    mutating func clearPending() {
        count = nil
        operatorCount = nil
        pendingOperator = nil
        prefix = nil
        pendingKeys = []
    }
}

extension VimState {
    public static func reduce(_ state: VimState, key: VimKey, context: VimContext) -> (VimState, [VimCommand]) {
        var next = state
        let commands: [VimCommand]
        switch state.mode {
        case .normal:
            commands = next.reduceNormal(key, context: context)
        case .insert, .visual, .visualLine:
            commands = []   // Tasks 7 and 8
        }
        return (next, commands)
    }

    // MARK: - Normal mode

    mutating func reduceNormal(_ key: VimKey, context: VimContext) -> [VimCommand] {
        pendingKeys.append(key)

        if let prefix {
            self.prefix = nil
            guard case .char(let c) = key else { return fail() }
            switch prefix {
            case .g:
                guard c == "g" else { return fail() }
                return motion(hasExplicitCount ? .line(effectiveCount) : .documentStart, context: context)
            case .find(let forward, let till):
                lastFind = VimFind(character: c, forward: forward, till: till)
                return motion(.find(c, forward: forward, till: till), context: context)
            }
        }

        switch key {
        case .escape:
            clearPending()
            return []
        case .control(let c) where c == "r":
            clearPending()
            return [.redo]
        case .char(let c):
            return reduceNormalCharacter(c, context: context)
        case .returnKey:
            return motion(.displayLineDown, context: context)
        case .backspace:
            return motion(.left, context: context)
        case .control:
            return fail()
        }
    }

    private mutating func reduceNormalCharacter(_ c: Character, context: VimContext) -> [VimCommand] {
        if let digit = c.wholeNumberValue, c.isASCII, digit != 0 || count != nil {
            count = min(10_000, (count ?? 0) * 10 + digit)
            return []
        }

        switch c {
        case "h": return motion(.left, context: context)
        case "l": return motion(.right, context: context)
        case "j": return motion(.displayLineDown, context: context)
        case "k": return motion(.displayLineUp, context: context)
        case "w": return motion(.wordForward(big: false), context: context)
        case "W": return motion(.wordForward(big: true), context: context)
        case "b": return motion(.wordBackward(big: false), context: context)
        case "B": return motion(.wordBackward(big: true), context: context)
        case "e": return motion(.wordEnd(big: false), context: context)
        case "E": return motion(.wordEnd(big: true), context: context)
        case "0": return motion(.lineStart, context: context)
        case "^": return motion(.firstNonBlank, context: context)
        case "$": return motion(.lineEnd, context: context)
        case "{": return motion(.paragraphBackward, context: context)
        case "}": return motion(.paragraphForward, context: context)
        case "G": return motion(hasExplicitCount ? .line(effectiveCount) : .documentEnd, context: context)
        case "g": prefix = .g; return []
        case "f": prefix = .find(forward: true, till: false); return []
        case "F": prefix = .find(forward: false, till: false); return []
        case "t": prefix = .find(forward: true, till: true); return []
        case "T": prefix = .find(forward: false, till: true); return []
        case ";", ",":
            guard let find = lastFind else { return fail() }
            let forward = c == ";" ? find.forward : !find.forward
            return motion(.find(find.character, forward: forward, till: find.till), context: context)
        default:
            return fail()
        }
    }

    /// Runs a motion: moves the caret in plain normal mode; Task 6 extends
    /// this to apply a pending operator.
    mutating func motion(_ motion: VimMotion, context: VimContext) -> [VimCommand] {
        let count = effectiveCount
        clearPending()
        switch motion {
        case .displayLineDown: return [.moveDisplayLines(count)]
        case .displayLineUp: return [.moveDisplayLines(-count)]
        default:
            guard let target = VimMotions.target(of: motion, from: context.caret, in: context.text, count: count) else {
                return []
            }
            return [.moveCaret(to: VimMotions.clampToLine(target, in: context.text))]
        }
    }

    mutating func fail() -> [VimCommand] {
        clearPending()
        return [.beep]
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter VimStateTests`
Expected: 8 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/WriteKit/VimState.swift Tests/WriteKitTests/VimStateTests.swift
git commit -m "Vim state machine: normal-mode movement, counts and prefixes

A pure reducer from (state, key, document) to commands, so every key
sequence is testable without AppKit. Operators, insert and visual
modes follow.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Operators, register, put

**Files:**
- Modify: `Sources/WriteKit/VimState.swift`
- Test: `Tests/WriteKitTests/VimStateTests.swift`

- [ ] **Step 1: Write the failing tests** (append inside `VimStateTests`)

```swift
    func testDeleteWithAMotion() {
        let (state, commands) = run("dw", text: "foo bar", caret: 0)
        XCTAssertEqual(commands, [.replace(NSRange(location: 0, length: 4), with: "", caretAt: 0)])
        XCTAssertEqual(state.register, VimRegister(text: "foo ", linewise: false))
        XCTAssertEqual(run("d2w", text: "a b c d", caret: 0).1, [.replace(NSRange(location: 0, length: 4), with: "", caretAt: 0)])
        XCTAssertEqual(run("2dw", text: "a b c d", caret: 0).1, [.replace(NSRange(location: 0, length: 4), with: "", caretAt: 0)])
        XCTAssertEqual(run("2d2w", text: "a b c d e", caret: 0).1, [.replace(NSRange(location: 0, length: 8), with: "", caretAt: 0)])
    }

    func testDeleteLinesLandsOnTheFirstNonBlankOfWhatMovesUp() {
        let (state, commands) = run("dd", text: "one\n  two\nthree", caret: 1)
        XCTAssertEqual(commands, [.replace(NSRange(location: 0, length: 4), with: "", caretAt: 2)])
        XCTAssertEqual(state.register, VimRegister(text: "one", linewise: true))
        XCTAssertEqual(run("dd", text: "one\ntwo", caret: 5).1,
                       [.replace(NSRange(location: 3, length: 4), with: "", caretAt: 0)], "last line: the caret clamps into what is left")
        XCTAssertEqual(run("dj", text: "a\nb\nc", caret: 0).1, [.replace(NSRange(location: 0, length: 4), with: "", caretAt: 0)])
        XCTAssertEqual(run("dk", text: "a\nb\nc", caret: 2).1, [.replace(NSRange(location: 0, length: 4), with: "", caretAt: 0)])
    }

    func testChangeDeletesThenEnters InsertAndTreatsCwLikeCe() {
        XCTAssertEqual(run("cw", text: "foo bar", caret: 0).1,
                       [.replace(NSRange(location: 0, length: 3), with: "", caretAt: 0), .setMode(.insert)])
        XCTAssertEqual(run("cw", text: "foo  bar", caret: 3).1,
                       [.replace(NSRange(location: 3, length: 2), with: "", caretAt: 3), .setMode(.insert)], "cw on blanks is a plain dw")
        XCTAssertEqual(run("cc", text: "one\n  two\nthree", caret: 6).1,
                       [.replace(NSRange(location: 4, length: 5), with: "", caretAt: 4), .setMode(.insert)], "cc empties the line, keeps it")
        XCTAssertEqual(run("cw", text: "foo bar", caret: 0).0.mode, .insert)
    }

    func testYankMovesTheCaretToTheStartOfTheRangeOnly() {
        let (state, commands) = run("yw", text: "foo bar", caret: 0)
        XCTAssertEqual(commands, [])
        XCTAssertEqual(state.register, VimRegister(text: "foo ", linewise: false))
        XCTAssertEqual(run("yb", text: "foo bar", caret: 6).1, [.moveCaret(to: 4)])
        XCTAssertEqual(run("yy", text: "one\ntwo", caret: 5).0.register, VimRegister(text: "two", linewise: true))
        XCTAssertEqual(run("yy", text: "one\ntwo", caret: 5).1, [])
    }

    func testXDeletesUnderTheCaretAndXBeforeIt() {
        XCTAssertEqual(run("x", text: "abc", caret: 2).1, [.replace(NSRange(location: 2, length: 1), with: "", caretAt: 1)], "x on the last char steps back")
        XCTAssertEqual(run("3x", text: "abcdef", caret: 1).1, [.replace(NSRange(location: 1, length: 3), with: "", caretAt: 1)])
        XCTAssertEqual(run("9x", text: "abc\nd", caret: 1).1, [.replace(NSRange(location: 1, length: 2), with: "", caretAt: 0)], "never past the line")
        XCTAssertEqual(run("X", text: "abc", caret: 2).1, [.replace(NSRange(location: 1, length: 1), with: "", caretAt: 1)])
        XCTAssertTrue(run("x", text: "a\n\nb", caret: 2).1.isEmpty, "empty line: nothing to delete")
    }

    func testPutCharwiseAndLinewise() {
        var state = VimState()
        state.register = VimRegister(text: "XY", linewise: false)
        XCTAssertEqual(run("p", text: "abc", caret: 0, from: state).1,
                       [.replace(NSRange(location: 1, length: 0), with: "XY", caretAt: 2)])
        XCTAssertEqual(run("P", text: "abc", caret: 1, from: state).1,
                       [.replace(NSRange(location: 1, length: 0), with: "XY", caretAt: 2)])
        XCTAssertEqual(run("2p", text: "abc", caret: 0, from: state).1,
                       [.replace(NSRange(location: 1, length: 0), with: "XYXY", caretAt: 4)])
        XCTAssertEqual(run("p", text: "a\n\nb", caret: 2, from: state).1,
                       [.replace(NSRange(location: 2, length: 0), with: "XY", caretAt: 3)], "on an empty line, at the caret")

        state.register = VimRegister(text: "  new", linewise: true)
        XCTAssertEqual(run("p", text: "one\ntwo", caret: 1, from: state).1,
                       [.replace(NSRange(location: 3, length: 0), with: "\n  new", caretAt: 6)], "below, caret on first non-blank")
        XCTAssertEqual(run("P", text: "one\ntwo", caret: 5, from: state).1,
                       [.replace(NSRange(location: 4, length: 0), with: "  new\n", caretAt: 6)], "above")
        XCTAssertTrue(run("p", text: "abc", caret: 0).1.isEmpty, "empty register")
    }

    func testOperatorPendingThenNonMotionBeeps() {
        XCTAssertEqual(run("dq", text: "abc", caret: 0).1, [.beep])
        XCTAssertEqual(run("dc", text: "abc", caret: 0).1, [.beep])
        XCTAssertTrue(run("dl", text: "abc", caret: 2).1.isEmpty, "motion fails → operator cancelled quietly")
    }
```

Fix the test name typo when writing it: `testChangeDeletesThenEntersInsertAndTreatsCwLikeCe`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter VimStateTests`
Expected: the new tests fail (operators currently `.beep`).

- [ ] **Step 3: Write the implementation**

In `reduceNormalCharacter`, before the motion `switch`, add:

```swift
        switch c {
        case "d", "c", "y":
            if pendingOperator == c {
                return operateOnLines(c, context: context)
            }
            if pendingOperator != nil { return fail() }
            pendingOperator = c
            operatorCount = count
            count = nil
            return []
        case "x":
            return deleteCharacters(forward: true, context: context)
        case "X":
            return deleteCharacters(forward: false, context: context)
        case "p":
            return put(after: true, context: context)
        case "P":
            return put(after: false, context: context)
        case "u":
            clearPending()
            return [.undo]
        default:
            break
        }
```

Replace `motion(_:context:)` with a version that applies a pending operator, and add the helpers:

```swift
    mutating func motion(_ motion: VimMotion, context: VimContext) -> [VimCommand] {
        let count = effectiveCount
        if let op = pendingOperator {
            var effective = motion
            // cw on a non-blank is ce: vim's oldest special case.
            if op == "c", case .wordForward(let big) = motion,
               context.caret < (context.text as NSString).length,
               !VimMotions.isBlankOrNewline((context.text as NSString).character(at: context.caret)) {
                effective = .wordEnd(big: big)
            }
            guard let operand = VimMotions.operandRange(of: effective, from: context.caret,
                                                        in: context.text, count: count) else {
                clearPending()
                return []
            }
            return apply(op, to: operand, context: context)
        }

        clearPending()
        switch motion {
        case .displayLineDown: return [.moveDisplayLines(count)]
        case .displayLineUp: return [.moveDisplayLines(-count)]
        default:
            guard let target = VimMotions.target(of: motion, from: context.caret, in: context.text, count: count) else {
                return []
            }
            return [.moveCaret(to: VimMotions.clampToLine(target, in: context.text))]
        }
    }

    /// dd / cc / yy.
    private mutating func operateOnLines(_ op: Character, context: VimContext) -> [VimCommand] {
        let operand = VimMotions.lineRange(at: context.caret, in: context.text, count: effectiveCount)
        return apply(op, to: operand, context: context)
    }

    private mutating func apply(_ op: Character, to operand: VimOperandRange, context: VimContext) -> [VimCommand] {
        let text = context.text as NSString
        var range = operand.range
        var yanked = text.substring(with: range)
        if operand.linewise {
            // The register holds lines without their terminator; put adds it back.
            yanked = yanked.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
        }
        register = VimRegister(text: yanked, linewise: operand.linewise)
        let change = VimChange.keys(pendingKeys, count: hasExplicitCount ? effectiveCount : nil)
        clearPending()

        switch op {
        case "y":
            let caret = operand.linewise ? context.caret : min(context.caret, range.location)
            return caret == context.caret ? [] : [.moveCaret(to: caret)]
        case "c":
            lastChange = change
            if operand.linewise {
                // Keep the line, empty it.
                let start = VimMotions.lineStart(of: range.location, in: context.text)
                let end = VimMotions.lineEnd(of: max(range.location, range.upperBound - 1), in: context.text)
                range = NSRange(location: start, length: end - start)
            }
            return [.replace(range, with: "", caretAt: range.location), .setMode(.insert)]
        default:
            lastChange = change
            let remaining = text.replacingCharacters(in: range, with: "")
            let caret = operand.linewise
                ? VimMotions.firstNonBlank(ofLineAt: min(range.location, (remaining as NSString).length), in: remaining)
                : range.location
            return [.replace(range, with: "", caretAt: VimMotions.clampToLine(caret, in: remaining))]
        }
    }

    private mutating func deleteCharacters(forward: Bool, context: VimContext) -> [VimCommand] {
        let count = effectiveCount
        let change = VimChange.keys(pendingKeys, count: hasExplicitCount ? count : nil)
        clearPending()
        let text = context.text
        let start = VimMotions.lineStart(of: context.caret, in: text)
        let end = VimMotions.lineEnd(of: context.caret, in: text)
        let range = forward
            ? NSRange(location: context.caret, length: min(count, end - context.caret))
            : NSRange(location: max(start, context.caret - count), length: min(count, context.caret - start))
        guard range.length > 0 else { return [] }
        register = VimRegister(text: (text as NSString).substring(with: range), linewise: false)
        lastChange = change
        let remaining = (text as NSString).replacingCharacters(in: range, with: "")
        return [.replace(range, with: "", caretAt: VimMotions.clampToLine(range.location, in: remaining))]
    }

    private mutating func put(after: Bool, context: VimContext) -> [VimCommand] {
        let count = effectiveCount
        let change = VimChange.keys(pendingKeys, count: hasExplicitCount ? count : nil)
        clearPending()
        guard let register, !register.text.isEmpty else { return [] }
        lastChange = change
        let text = context.text
        let payload = String(repeating: register.text, count: count)
        if register.linewise {
            if after {
                let end = VimMotions.lineEnd(of: context.caret, in: text)
                let inserted = "\n" + String(repeating: register.text + "\n", count: count).dropLast()
                return [.replace(NSRange(location: end, length: 0), with: String(inserted),
                                 caretAt: end + 1 + leadingBlankCount(of: register.text))]
            }
            let start = VimMotions.lineStart(of: context.caret, in: text)
            let inserted = String(repeating: register.text + "\n", count: count)
            return [.replace(NSRange(location: start, length: 0), with: inserted,
                             caretAt: start + leadingBlankCount(of: register.text))]
        }
        let empty = VimMotions.lineIsEmpty(containing: context.caret, in: text)
        let at = after && !empty ? context.caret + 1 : context.caret
        let length = (payload as NSString).length
        return [.replace(NSRange(location: at, length: 0), with: payload, caretAt: at + length - 1)]
    }

    private func leadingBlankCount(of line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }
```

Add to `VimMotions` (it is `internal`, same module):

```swift
    static func isBlankOrNewline(_ c: unichar) -> Bool {
        c == newline || isBlank(c)
    }
```

Also add `p` to the count-after-caret rule: `.replace` for charwise `p` when the caret is on the last character of a line must insert *after* it, which is `caret + 1` even though `clampToLine` would forbid the caret resting there — the reducer inserts at `caret + 1` and the caret lands on the last put character, which is valid.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter VimStateTests`
Expected: 15 tests, 0 failures. If `testDeleteLinesLandsOnTheFirstNonBlankOfWhatMovesUp`'s last-line case gives `caretAt: 3` rather than `0`, the clamp is being applied to the pre-delete text; it must use `remaining`.

- [ ] **Step 5: Commit**

```bash
git add Sources/WriteKit/VimState.swift Tests/WriteKitTests/VimStateTests.swift
git commit -m "Vim state machine: d c y operators, x X, the register and p P

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Insert mode entry and exit, `u`, `.` repeat

**Files:**
- Modify: `Sources/WriteKit/VimState.swift`
- Test: `Tests/WriteKitTests/VimStateTests.swift`

- [ ] **Step 1: Write the failing tests** (append inside `VimStateTests`)

```swift
    func testInsertEntryCommands() {
        XCTAssertEqual(run("i", text: "abc", caret: 1).1, [.setMode(.insert)])
        XCTAssertEqual(run("a", text: "abc", caret: 1).1, [.moveCaret(to: 2), .setMode(.insert)])
        XCTAssertEqual(run("a", text: "abc", caret: 2).1, [.moveCaret(to: 3), .setMode(.insert)], "a on the last char goes past it")
        XCTAssertEqual(run("I", text: "  abc", caret: 4).1, [.moveCaret(to: 2), .setMode(.insert)])
        XCTAssertEqual(run("A", text: "abc\nd", caret: 0).1, [.moveCaret(to: 3), .setMode(.insert)])
        XCTAssertEqual(run("o", text: "abc", caret: 0).1, [.moveCaret(to: 3), .smartReturn(after: true), .setMode(.insert)])
        XCTAssertEqual(run("O", text: "abc", caret: 1).1, [.moveCaret(to: 0), .smartReturn(after: false), .setMode(.insert)])
        XCTAssertEqual(run("di", text: "abc", caret: 0).1, [.beep], "no operator before an insert command")
    }

    func testEscapeLeavesInsertAndStepsBack() {
        let (state, commands) = run("i" + esc, text: "abc", caret: 2)
        XCTAssertEqual(state.mode, .normal)
        XCTAssertEqual(commands, [.setMode(.insert), .setMode(.normal), .moveCaret(to: 1)])
        XCTAssertEqual(run("i" + esc, text: "abc", caret: 0).1, [.setMode(.insert), .setMode(.normal)], "not at a line start")
        XCTAssertEqual(run("i" + esc, text: "abc", caret: 3).1, [.setMode(.insert), .setMode(.normal), .moveCaret(to: 2)], "from past the end onto the last char")
    }

    func testTypedTextIsRecordedForRepeat() {
        let (state, _) = run("ihey" + esc, text: "", caret: 0)
        XCTAssertEqual(state.lastChange, .insert(entry: .char("i"), text: "hey", count: nil))
        let (_, replay) = run(".", text: "abc", caret: 1, from: state)
        XCTAssertEqual(replay, [.setMode(.insert), .insertText("hey"), .setMode(.normal), .moveCaret(to: 3)])
    }

    func testCountedInsertRepeatsTheText() {
        let (_, commands) = run("3ihi" + esc, text: "", caret: 0)
        XCTAssertEqual(commands, [.setMode(.insert), .setMode(.normal), .insertText("hihi"), .moveCaret(to: 0)].filter { _ in true }.isEmpty ? [] : commands, "see below")
    }

    func testRepeatReplaysOperatorsWithTheirCount() {
        let (state, _) = run("d2w", text: "a b c d", caret: 0)
        XCTAssertEqual(run(".", text: "c d e f", caret: 0, from: state).1,
                       [.replace(NSRange(location: 0, length: 4), with: "", caretAt: 0)])
        XCTAssertEqual(run("3.", text: "a b c d e f", caret: 0, from: state).1,
                       [.replace(NSRange(location: 0, length: 6), with: "", caretAt: 0)], "a new count replaces the old one")
        XCTAssertTrue(run(".", text: "abc", caret: 0).1.isEmpty, "nothing to repeat")
    }

    func testUndoAndRedo() {
        XCTAssertEqual(run("u", text: "abc", caret: 0).1, [.undo])
        let (_, commands) = VimState.reduce(VimState(), key: .control("r"), context: VimContext(text: "abc", caret: 0))
        XCTAssertEqual(commands, [.redo])
    }
```

Replace the confused `testCountedInsertRepeatsTheText` above with this exact expectation — `3ihi<Esc>` yields insert mode, then on Esc the extra two copies and the step back:

```swift
    func testCountedInsertRepeatsTheText() {
        let (_, commands) = run("3ihi" + esc, text: "", caret: 0)
        XCTAssertEqual(commands, [.setMode(.insert), .insertText("hihi"), .setMode(.normal)])
    }
```

(The step back is omitted because the context caret stays at 0 in this fixture; the controller supplies the real caret after the inserts.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter VimStateTests`
Expected: the new tests fail.

- [ ] **Step 3: Write the implementation**

In `reduceNormalCharacter`'s first `switch` (from Task 6), add:

```swift
        case "i", "a", "I", "A", "o", "O":
            guard pendingOperator == nil else { return fail() }
            return enterInsert(with: c, context: context)
        case ".":
            return repeatLastChange(context: context)
```

Helpers:

```swift
    // MARK: - Insert mode

    private mutating func enterInsert(with c: Character, context: VimContext) -> [VimCommand] {
        let count = hasExplicitCount ? effectiveCount : nil
        clearPending()
        insertEntry = .char(c)
        insertCount = count
        insertedText = ""
        mode = .insert

        let text = context.text
        let caret = context.caret
        let length = (text as NSString).length
        switch c {
        case "i": return [.setMode(.insert)]
        case "a":
            let end = VimMotions.lineEnd(of: caret, in: text)
            return [.moveCaret(to: min(caret + 1, end)), .setMode(.insert)]
        case "I": return [.moveCaret(to: VimMotions.firstNonBlank(ofLineAt: caret, in: text)), .setMode(.insert)]
        case "A": return [.moveCaret(to: VimMotions.lineEnd(of: caret, in: text)), .setMode(.insert)]
        case "o": return [.moveCaret(to: VimMotions.lineEnd(of: caret, in: text)), .smartReturn(after: true), .setMode(.insert)]
        default:  return [.moveCaret(to: VimMotions.lineStart(of: caret, in: text)), .smartReturn(after: false), .setMode(.insert)]
        }
        _ = length
    }

    mutating func reduceInsert(_ key: VimKey, context: VimContext) -> [VimCommand] {
        switch key {
        case .escape:
            return leaveInsert(context: context)
        case .char(let c):
            insertedText?.append(c)
        case .returnKey:
            insertedText?.append("\n")
        case .backspace:
            if let text = insertedText, !text.isEmpty {
                insertedText?.removeLast()
            } else {
                insertedText = nil
            }
        case .control:
            insertedText = nil
        }
        return []
    }

    private mutating func leaveInsert(context: VimContext) -> [VimCommand] {
        var commands: [VimCommand] = [.setMode(.normal)]
        if let text = insertedText, let count = insertCount, count > 1, !text.isEmpty {
            commands.insert(.insertText(String(repeating: text, count: count - 1)), at: 0)
        }
        if let entry = insertEntry, let text = insertedText, !text.isEmpty {
            lastChange = .insert(entry: entry, text: text, count: insertCount)
        }
        mode = .normal
        insertEntry = nil
        insertCount = nil
        insertedText = ""

        // Vim steps back onto the last typed character.
        let caret = context.caret
        let start = VimMotions.lineStart(of: caret, in: context.text)
        if caret > start {
            commands.append(.moveCaret(to: VimMotions.clampToLine(caret - 1, in: context.text)))
        }
        return commands
    }

    // MARK: - Repeat

    private mutating func repeatLastChange(context: VimContext) -> [VimCommand] {
        let newCount = hasExplicitCount ? effectiveCount : nil
        clearPending()
        guard let change = lastChange else { return [] }
        switch change {
        case .keys(let keys, let count):
            let digits = (newCount ?? count).map { Array(String($0)).map { VimKey.char($0) } } ?? []
            var replay = self
            replay.clearPending()
            var commands: [VimCommand] = []
            for key in digits + keys.filter({ !$0.isDigit }) {
                commands += replay.reduceNormal(key, context: context)
            }
            replay.lastChange = change
            self = replay
            return commands
        case .insert(let entry, let text, let count):
            var commands = enterInsert(with: entryCharacter(entry), context: context)
            let times = newCount ?? count ?? 1
            commands.append(.insertText(String(repeating: text, count: times)))
            commands.append(.setMode(.normal))
            mode = .normal
            insertEntry = nil
            insertedText = ""
            lastChange = change
            // The controller reports the caret after the insert; step back
            // one so the caret rests on the last inserted character.
            let landing = context.caret + (text as NSString).length * times
            commands.append(.moveCaret(to: max(0, landing - 1)))
            return commands
        }
    }

    private func entryCharacter(_ key: VimKey) -> Character {
        if case .char(let c) = key { return c }
        return "i"
    }
```

Extend `VimKey`:

```swift
extension VimKey {
    var isDigit: Bool {
        if case .char(let c) = self { return c.isASCII && c.isNumber }
        return false
    }
}
```

And in `reduce`, route insert mode: `case .insert: commands = next.reduceInsert(key, context: context)`.

Clean-ups to make while implementing: the `_ = length` / `let length` lines in `enterInsert` are leftovers — delete them. In `repeatLastChange`'s `.insert` branch the `.moveCaret` landing calculation is only right for `i`/`a`-style entries where the insert happens at the caret; the `o`/`O` entry inserts after a SmartReturn, so for those two entries omit the final `.moveCaret` and let the controller's `leaveInsert`-style clamp handle it (the controller clamps the caret with `VimMotions.clampToLine` after every command batch in normal mode — see Task 9). The `testTypedTextIsRecordedForRepeat` expectation reflects the `i` case.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter VimStateTests`
Expected: 21 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/WriteKit/VimState.swift Tests/WriteKitTests/VimStateTests.swift
git commit -m "Vim state machine: insert mode entry and exit, undo, dot repeat

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Visual and visual-line modes

**Files:**
- Modify: `Sources/WriteKit/VimState.swift`
- Test: `Tests/WriteKitTests/VimStateTests.swift`

- [ ] **Step 1: Write the failing tests** (append inside `VimStateTests`)

```swift
    func testVisualModeExtendsASelectionWithMotions() {
        let (state, commands) = run("vw", text: "foo bar baz", caret: 0)
        XCTAssertEqual(state.mode, .visual)
        XCTAssertEqual(commands, [.setMode(.visual), .select(NSRange(location: 0, length: 1)),
                                  .moveCaret(to: 4), .select(NSRange(location: 0, length: 5))])
        XCTAssertEqual(run("ve", text: "foo bar", caret: 0).1.last, .select(NSRange(location: 0, length: 3)))
        XCTAssertEqual(run("vb", text: "foo bar", caret: 5).1.last, .select(NSRange(location: 4, length: 2)), "backwards from the anchor")
    }

    func testVisualOperatorsActOnTheSelection() {
        let (state, commands) = run("vwd", text: "foo bar baz", caret: 0)
        XCTAssertEqual(state.mode, .normal)
        XCTAssertEqual(commands.last, .replace(NSRange(location: 0, length: 5), with: "", caretAt: 0))
        XCTAssertEqual(state.register, VimRegister(text: "foo b", linewise: false))
        XCTAssertEqual(run("vwy", text: "foo bar", caret: 0).1.last, .moveCaret(to: 0))
        XCTAssertEqual(run("vwc", text: "foo bar", caret: 0).1.suffix(2),
                       [.replace(NSRange(location: 0, length: 5), with: "", caretAt: 0), .setMode(.insert)])
        XCTAssertEqual(run("vx", text: "abc", caret: 1).1.last, .replace(NSRange(location: 1, length: 1), with: "", caretAt: 1))
    }

    func testVisualLineSelectsWholeLines() {
        let (state, commands) = run("V", text: "one\ntwo\nthree", caret: 5)
        XCTAssertEqual(state.mode, .visualLine)
        XCTAssertEqual(commands, [.setMode(.visualLine), .select(NSRange(location: 4, length: 4))])
        XCTAssertEqual(run("Vjd", text: "one\ntwo\nthree", caret: 0).1.last,
                       .replace(NSRange(location: 0, length: 8), with: "", caretAt: 0))
        XCTAssertEqual(run("Vjd", text: "one\ntwo\nthree", caret: 0).0.register, VimRegister(text: "one\ntwo", linewise: true))
    }

    func testVisualEscapeAndSwap() {
        let (state, commands) = run("vw" + esc, text: "foo bar", caret: 0)
        XCTAssertEqual(state.mode, .normal)
        XCTAssertEqual(commands.last, .setMode(.normal))
        XCTAssertEqual(run("vwo", text: "foo bar", caret: 0).1.last, .select(NSRange(location: 0, length: 5)), "o swaps anchor and caret")
        XCTAssertEqual(run("vwo", text: "foo bar", caret: 0).0.visualAnchor, 4)
    }

    func testVisualPutReplacesTheSelection() {
        var state = VimState()
        state.register = VimRegister(text: "Z", linewise: false)
        XCTAssertEqual(run("vlp", text: "abc", caret: 0, from: state).1.last,
                       .replace(NSRange(location: 0, length: 2), with: "Z", caretAt: 0))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter VimStateTests`
Expected: the five new tests fail.

- [ ] **Step 3: Write the implementation**

In `reduceNormalCharacter`'s first `switch`, add:

```swift
        case "v", "V":
            guard pendingOperator == nil else { return fail() }
            clearPending()
            mode = c == "v" ? .visual : .visualLine
            visualAnchor = context.caret
            return [.setMode(mode), selection(caret: context.caret, context: context)]
```

Route in `reduce`: `case .visual, .visualLine: commands = next.reduceVisual(key, context: context)`.

```swift
    // MARK: - Visual mode

    /// The selection from the anchor to `caret`, inclusive of the caret's
    /// character; whole lines in visual-line mode.
    private func selection(caret: Int, context: VimContext) -> VimCommand {
        .select(visualRange(caret: caret, context: context).range)
    }

    private func visualRange(caret: Int, context: VimContext) -> VimOperandRange {
        let anchor = visualAnchor ?? caret
        if mode == .visualLine {
            return VimMotions.linesRange(from: anchor, to: caret, in: context.text)
        }
        let length = (context.text as NSString).length
        let lo = min(anchor, caret)
        let hi = min(max(anchor, caret) + 1, length)
        return VimOperandRange(range: NSRange(location: lo, length: hi - lo), linewise: false)
    }

    mutating func reduceVisual(_ key: VimKey, context: VimContext) -> [VimCommand] {
        pendingKeys.append(key)
        switch key {
        case .escape:
            return leaveVisual(commands: [])
        case .char(let c):
            if let digit = c.wholeNumberValue, c.isASCII, digit != 0 || count != nil {
                count = min(10_000, (count ?? 0) * 10 + digit)
                return []
            }
            switch c {
            case "d", "x", "y", "c":
                let operand = visualRange(caret: context.caret, context: context)
                let op: Character = c == "x" ? "d" : c
                pendingOperator = nil
                let commands = apply(op, to: operand, context: context)
                let goesToInsert = op == "c"
                return leaveVisual(commands: commands, keepInsert: goesToInsert)
            case "p":
                let operand = visualRange(caret: context.caret, context: context)
                clearPending()
                guard let register else { return leaveVisual(commands: []) }
                lastChange = nil
                let replacement = register.linewise ? register.text + "\n" : register.text
                let commands = [VimCommand.replace(operand.range, with: replacement, caretAt: operand.range.location)]
                return leaveVisual(commands: commands)
            case "o":
                guard let anchor = visualAnchor else { return [] }
                visualAnchor = context.caret
                clearPending()
                return [.moveCaret(to: anchor), selection(caret: anchor, context: context)]
            case "v":
                return mode == .visual ? leaveVisual(commands: []) : switchVisual(to: .visual, context: context)
            case "V":
                return mode == .visualLine ? leaveVisual(commands: []) : switchVisual(to: .visualLine, context: context)
            default:
                break
            }
            // Anything else is a motion that extends the selection.
            let before = self
            let moves = reduceNormalCharacter(c, context: context)
            // reduceNormalCharacter may have set a prefix (g, f); keep waiting.
            if prefix != nil { return [] }
            guard moves != [.beep] else { self = before; return [.beep] }
            return followMoves(moves, context: context)
        case .control(let c) where c == "r":
            return [.redo]
        default:
            return [.beep]
        }
    }

    private mutating func switchVisual(to newMode: VimMode, context: VimContext) -> [VimCommand] {
        mode = newMode
        return [.setMode(newMode), selection(caret: context.caret, context: context)]
    }

    private mutating func leaveVisual(commands: [VimCommand], keepInsert: Bool = false) -> [VimCommand] {
        visualAnchor = nil
        if !keepInsert {
            mode = .normal
            clearPending()
            return commands + [.setMode(.normal)]
        }
        return commands
    }

    /// After a motion in visual mode: a plain caret move becomes a move plus
    /// the new selection; display-line moves are re-selected by the
    /// controller once it knows where the caret landed.
    private func followMoves(_ moves: [VimCommand], context: VimContext) -> [VimCommand] {
        moves.flatMap { move -> [VimCommand] in
            if case .moveCaret(let to) = move {
                return [move, selection(caret: to, context: context)]
            }
            return [move]
        }
    }
```

Two adjustments the implementer must make in code from earlier tasks so this compiles and behaves: (1) `reduceNormalCharacter` handles `"o"` as insert entry; in visual mode `"o"` is intercepted above before it gets there — keep that order. (2) The prefix handling (`g`, `f`) lives in `reduceNormal`, not `reduceNormalCharacter`; move the `if let prefix { … }` block into a shared `resolvePrefix(_:context:) -> [VimCommand]?` that both `reduceNormal` and `reduceVisual` call first, so `vfx` and `vgg` work. In `apply` for `"c"` with a visual (non-linewise) operand, the mode must end up `.insert`: set `mode = .insert` inside `apply`'s `"c"` branch (Task 6 code only emitted `.setMode(.insert)`; make it also assign `mode = .insert`, which the Task 6 test `run("cw"…).0.mode == .insert` already requires).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter VimStateTests`
Expected: 26 tests, 0 failures. Then `./bin/test` — everything (WriteKit, WriteTests) green.

- [ ] **Step 5: Commit**

```bash
git add Sources/WriteKit/VimState.swift Tests/WriteKitTests/VimStateTests.swift
git commit -m "Vim state machine: visual and visual-line modes

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: `VimController` and key routing in the text view

**Files:**
- Create: `Sources/Write/VimController.swift`
- Modify: `Sources/Write/MarkdownTextView.swift` (add `vim` property and `keyDown`)
- Modify: `Sources/Write/EditorViewController.swift` (create the controller after the text view)
- Test: `Tests/WriteTests/VimControllerTests.swift`

**Interfaces:**
- Consumes: `VimState.reduce`, `VimCommand`, `VimMotions.clampToLine`, `MarkdownTextView.apply(_ edit: TextEdit)` (exists; make it `internal` not `private` if it is private), `MarkdownTextView.insertNewline(_:)` (SmartReturn).
- Produces: `final class VimController { init(textView:); var state: VimState { get }; var modeText: String; var onModeChange: (() -> Void)?; func handle(_ event: NSEvent) -> Bool }` and `MarkdownTextView.vim: VimController?`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/WriteTests/VimControllerTests.swift
import AppKit
import XCTest
@testable import Write

final class VimControllerTests: XCTestCase {
    private var document: WriteDocument!
    private var window: NSWindow!
    private var textView: MarkdownTextView!

    override func setUp() {
        document = WriteDocument()
        let editor = EditorViewController(document: document)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = editor
        window.layoutIfNeeded()
        textView = Self.findTextView(in: editor.view)
        window.makeFirstResponder(textView)
    }

    private static func findTextView(in view: NSView) -> MarkdownTextView? {
        (view as? MarkdownTextView) ?? view.subviews.lazy.compactMap { findTextView(in: $0) }.first
    }

    /// Types `keys` the way the window would deliver them. "\u{1B}" is Esc,
    /// "\r" is Return, "\u{12}" is ^R.
    private func type(_ keys: String) {
        for character in keys {
            let event: NSEvent?
            switch character {
            case "\u{1B}":
                event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil,
                                         characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                                         isARepeat: false, keyCode: 53)
            case "\u{12}":
                event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .control, timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil,
                                         characters: "\u{12}", charactersIgnoringModifiers: "r",
                                         isARepeat: false, keyCode: 15)
            default:
                event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil,
                                         characters: String(character), charactersIgnoringModifiers: String(character),
                                         isARepeat: false, keyCode: 0)
            }
            textView.keyDown(with: event!)
        }
    }

    private var text: String { document.textStorage.string }
    private var caret: Int { textView.selectedRange().location }

    func testOpensInNormalModeWhereTypingDoesNotInsert() {
        XCTAssertEqual(textView.vim?.state.mode, .normal)
        type("hello")
        XCTAssertEqual(text, "")
    }

    func testInsertTypesAndEscapeStepsBack() {
        type("ihello\u{1B}")
        XCTAssertEqual(text, "hello")
        XCTAssertEqual(textView.vim?.state.mode, .normal)
        XCTAssertEqual(caret, 4, "on the last typed character")
    }

    func testDeleteLineIsOneUndoStep() {
        type("ione\rtwo\rthree\u{1B}")
        type("kdd")
        XCTAssertEqual(text, "one\n\n\nthree")
        type("u")
        XCTAssertEqual(text, "one\n\ntwo\n\nthree")
    }

    func testOpenLineContinuesAList() {
        type("i- item\u{1B}")
        type("o")
        XCTAssertEqual(text, "- item\n- ")
        XCTAssertEqual(textView.vim?.state.mode, .insert)
    }

    func testYankAndPut() {
        type("ifoo bar\u{1B}0")
        type("ywP")
        XCTAssertEqual(text, "foo foo bar")
        type("yyp")
        XCTAssertEqual(text, "foo foo bar\nfoo foo bar")
    }

    func testVisualLineDelete() {
        type("ia\rb\rc\u{1B}gg")
        type("Vjd")
        XCTAssertEqual(text, "b\n\nc", "V j takes the first paragraph and its blank line")
    }

    func testWordMotionRevealsMarkersItLandsOn() {
        type("iplain **bold** end\u{1B}0")
        type("w")
        let font = document.textStorage.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, textView.font?.pointSize, "the ** markers are revealed with the caret beside them")
    }

    func testCommandShortcutsAreNotSwallowed() {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil,
                                     characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1)!
        XCTAssertFalse(textView.vim!.handle(event))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter VimControllerTests`
Expected: compile error — `value of type 'MarkdownTextView' has no member 'vim'`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Write/VimController.swift
import AppKit
import WriteKit

/// Runs the vim state machine against the text view.
///
/// The reducer decides everything; this class only turns key events into
/// `VimKey`s and `VimCommand`s into calls on `MarkdownTextView`.
final class VimController {
    private(set) var state = VimState()
    private unowned let textView: MarkdownTextView

    /// Called whenever the footer's mode text may have changed.
    var onModeChange: (() -> Void)?

    init(textView: MarkdownTextView) {
        self.textView = textView
    }

    var modeText: String {
        let mode: String
        switch state.mode {
        case .normal: mode = "NORMAL"
        case .insert: mode = "INSERT"
        case .visual: mode = "VISUAL"
        case .visualLine: mode = "V-LINE"
        }
        let pending = state.pendingText
        return pending.isEmpty ? mode : "\(mode) \(pending)"
    }

    var showsBlockCaret: Bool { state.mode != .insert }

    /// Whether the event was consumed. Command-key shortcuts and, in insert
    /// mode, everything but Esc pass through to the text view.
    func handle(_ event: NSEvent) -> Bool {
        guard let key = Self.key(for: event) else { return false }

        let context = VimContext(text: textView.string, caret: textView.selectedRange().location)
        let (next, commands) = VimState.reduce(state, key: key, context: context)
        let wasInsert = state.mode == .insert
        state = next

        if wasInsert, key != .escape {
            // Recorded for `.`; the text view does the typing.
            return false
        }
        for command in commands { execute(command) }
        settleCaret()
        onModeChange?()
        return true
    }

    private static func key(for event: NSEvent) -> VimKey? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.option) { return nil }
        if event.keyCode == 53 { return .escape }
        if flags.contains(.control) {
            guard let c = event.charactersIgnoringModifiers?.first else { return nil }
            return .control(c)
        }
        guard let characters = event.characters, let first = characters.first else { return nil }
        switch first {
        case "\r", "\n": return .returnKey
        case "\u{7F}", "\u{08}": return .backspace
        default:
            // Arrow keys and friends arrive as private-use characters; vim
            // has no use for them in normal mode.
            guard first.unicodeScalars.first.map({ $0.value < 0xF700 }) ?? false else { return nil }
            return .char(first)
        }
    }

    // MARK: - Commands

    private func execute(_ command: VimCommand) {
        switch command {
        case .moveCaret(let to):
            move(to: to)
        case .moveDisplayLines(let lines):
            for _ in 0..<abs(lines) {
                lines > 0 ? textView.moveDown(nil) : textView.moveUp(nil)
            }
            if state.mode == .visual || state.mode == .visualLine {
                // Re-anchor the selection now that the caret has landed.
                let (next, commands) = VimState.reduce(state, key: .char("o"),
                                                       context: VimContext(text: textView.string, caret: textView.selectedRange().location))
                // `o` swaps anchor and caret twice to recompute; simpler: ask the state for the selection directly.
                _ = next; _ = commands
                reselectVisual()
            }
        case .select(let range):
            textView.setSelectedRange(range)
        case .replace(let range, let replacement, let caretAt):
            textView.apply(TextEdit(range: range, replacement: replacement,
                                    selection: NSRange(location: caretAt, length: 0)))
        case .insertText(let text):
            textView.insertText(text, replacementRange: textView.selectedRange())
        case .smartReturn:
            textView.insertNewline(nil)
        case .setMode:
            textView.setNeedsDisplay(textView.bounds)   // caret shape changes
        case .undo:
            textView.undoManager?.undo()
        case .redo:
            textView.undoManager?.redo()
        case .beep:
            NSSound.beep()
        }
    }

    private func move(to position: Int) {
        let clamped = min(max(0, position), (textView.string as NSString).length)
        textView.setSelectedRange(NSRange(location: clamped, length: 0))
        textView.scrollRangeToVisible(NSRange(location: clamped, length: 0))
    }

    /// Normal mode's caret sits on a character; after any command batch,
    /// keep it there. `O` also needs the caret put back on the opened line.
    private func settleCaret() {
        guard state.mode == .normal else { return }
        let caret = textView.selectedRange().location
        let clamped = VimMotions.clampToLine(caret, in: textView.string)
        if clamped != caret || textView.selectedRange().length > 0 {
            textView.setSelectedRange(NSRange(location: clamped, length: 0))
        }
    }

    private func reselectVisual() {
        // The reducer computes selections from its anchor; feed it a no-op
        // motion by re-selecting through the public API.
        let caret = textView.selectedRange().location
        let (next, commands) = VimState.reduce(state, key: .char("o"), context: VimContext(text: textView.string, caret: caret))
        _ = next; _ = commands
    }
}
```

The `moveDisplayLines` visual re-selection above is a sketch that does not work; implement it properly: add to `VimState` a public method the controller can call —

```swift
extension VimState {
    /// The visual selection for a caret that moved outside the reducer
    /// (display-line moves are made by the text view).
    public func visualSelection(caret: Int, text: String) -> NSRange? {
        guard mode == .visual || mode == .visualLine else { return nil }
        return visualRange(caret: caret, context: VimContext(text: text, caret: caret)).range
    }
}
```

and in `execute(.moveDisplayLines)` replace the whole `if state.mode == .visual …` block with:

```swift
            if let range = state.visualSelection(caret: textView.selectedRange().location, text: textView.string) {
                textView.setSelectedRange(range)
            }
```

Delete `reselectVisual()`. For `.smartReturn(after: false)` (`O`), after `insertNewline` the caret is on the original line; move it onto the new empty line: record `let start = textView.selectedRange().location` before, then after `insertNewline(nil)` call `move(to: start)` when `after == false`.

`MarkdownTextView` additions:

```swift
    /// The modal layer. Set by the editor once the view exists.
    var vim: VimController?

    override func keyDown(with event: NSEvent) {
        if let vim, vim.handle(event) { return }
        super.keyDown(with: event)
    }
```

Make `apply(_ edit: TextEdit)` `internal` (drop `private` if present). In `EditorViewController.init`, right after `textView.highlighter = document.highlighter`:

```swift
        textView.vim = VimController(textView: textView)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter VimControllerTests`
Expected: 8 tests, 0 failures. Likely first failures and their causes:
- `testInsertTypesAndEscapeStepsBack` caret 5 instead of 4 → Esc handling returned before `execute`; the `wasInsert && key != .escape` guard must let Esc through.
- `testOpenLineContinuesAList` → `insertNewline` must run with the caret at the line end (`.moveCaret` precedes `.smartReturn` in the reducer's output; make sure commands execute in order).
- `testWordMotionRevealsMarkersItLandsOn` → the caret move must go through `setSelectedRange` (it does via `move(to:)`); if it fails, check `settleCaret` isn't moving the caret off the span.

Then `./bin/test`: everything green.

- [ ] **Step 5: Commit**

```bash
git add Sources/Write/VimController.swift Sources/Write/MarkdownTextView.swift Sources/Write/EditorViewController.swift Tests/WriteTests/VimControllerTests.swift
git commit -m "Vim mode in the editor

keyDown hands unmodified keys to the state machine outside insert mode;
insert mode is the editor as it was. Commands come back as caret moves,
edits through apply(_:) so undo grouping is unchanged, and SmartReturn
for o and O so lists continue.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Block caret and the footer mode indicator

**Files:**
- Modify: `Sources/Write/MarkdownTextView.swift` (`drawInsertionPoint`)
- Modify: `Sources/Write/FooterView.swift` (add `mode`)
- Modify: `Sources/Write/EditorViewController.swift` (wire `onModeChange`)
- Test: `Tests/WriteTests/VimControllerTests.swift`

- [ ] **Step 1: Write the failing tests** (append inside `VimControllerTests`; `FooterView` needs a way to read the mode — add `var mode: String` with a `didSet` that updates its label)

```swift
    func testFooterShowsTheModeAndPendingKeys() {
        let footer = Self.findFooter(in: window.contentViewController!.view)!
        XCTAssertEqual(footer.mode, "NORMAL")
        type("i")
        XCTAssertEqual(footer.mode, "INSERT")
        type("\u{1B}d2")
        XCTAssertEqual(footer.mode, "NORMAL d2")
        type("\u{1B}v")
        XCTAssertEqual(footer.mode, "VISUAL")
    }

    private static func findFooter(in view: NSView) -> FooterView? {
        (view as? FooterView) ?? view.subviews.lazy.compactMap { findFooter(in: $0) }.first
    }

    func testCaretIsABlockOutsideInsertMode() {
        XCTAssertTrue(textView.vim!.showsBlockCaret)
        type("i")
        XCTAssertFalse(textView.vim!.showsBlockCaret)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter VimControllerTests`
Expected: compile error — `value of type 'FooterView' has no member 'mode'`.

- [ ] **Step 3: Write the implementation**

`FooterView`: add a label before `statusLabel` in the stack.

```swift
    private let modeLabel = FooterView.label(alignment: .left)

    /// NORMAL, INSERT and friends, with any pending keys.
    var mode: String = "" {
        didSet { modeLabel.stringValue = mode }
    }
```

In `setUp()`, change the stack to `NSStackView(views: [saveButton, openButton, modeLabel, statusLabel])`, and in `apply(fontSize:)` set `modeLabel.font = font` alongside the others. Give the mode label the accent colour so it reads as status, not prose: `modeLabel.textColor = Palette.accent`.

`EditorViewController`, after creating the controller:

```swift
        textView.vim?.onModeChange = { [weak self] in
            guard let self else { return }
            self.footer.mode = self.textView.vim?.modeText ?? ""
        }
        footer.mode = textView.vim?.modeText ?? ""
```

`MarkdownTextView.drawInsertionPoint`: widen the rect to a character cell and fill at half alpha outside insert mode; on erase, redraw the text underneath instead of painting background over the glyph.

```swift
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let caret = glyphAlignedCaret(rect)
        guard vim?.showsBlockCaret == true, let font = fontAtInsertionPoint() else {
            super.drawInsertionPoint(in: caret, color: color, turnedOn: flag)
            return
        }
        let block = NSRect(x: caret.minX, y: caret.minY,
                           width: Fonts.characterWidth(of: font), height: caret.height)
        if flag {
            color.withAlphaComponent(0.45).setFill()
            block.fill()
        } else {
            // Redraw the glyph under the block rather than blanking it.
            setNeedsDisplay(block.insetBy(dx: -1, dy: -1))
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./bin/test`
Expected: all green (WriteKitTests 26 + prior, WriteTests 10 + prior).

- [ ] **Step 5: Build and look**

Run: `./bin/build debug` then open `.build/Write.app` **in the background** (`open -g`) and capture its window with `screencapture -l <windowID>`; do not activate it or send keystrokes with AppleScript — a person may be typing. Verify: the footer reads `NORMAL`; the caret is a translucent block on the first character.

- [ ] **Step 6: Commit**

```bash
git add Sources/Write/MarkdownTextView.swift Sources/Write/FooterView.swift Sources/Write/EditorViewController.swift Tests/WriteTests/VimControllerTests.swift
git commit -m "Vim mode: block caret and a mode readout in the footer

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: Documentation

**Files:**
- Modify: `README.md` (Writing and Shortcuts sections)
- Modify: `Sources/Write/ShortcutsPanel.swift`

- [ ] **Step 1: Update the README**

Add after the "## Writing" heading's first paragraph:

```markdown
Write is modal, like vim. A document opens in **normal** mode: `i` `a` `o`
start writing, `Esc` goes back. `h j k l w b e 0 ^ $ gg G { } f t` move
(with counts: `3w`), `d c y` operate on a motion (`dw`, `d2j`, `yy`),
`x` deletes a character, `p` puts what was last deleted or yanked, `u`
undoes, `.` repeats, `v` and `V` select. `j` and `k` move by display line,
since in prose a line is a paragraph. The footer shows the mode.
```

Add to the shortcuts table: `| \`Esc\` | Normal mode |` and `| \`i\` | Insert mode |`.

- [ ] **Step 2: Update the ⌘/ card**

In `ShortcutsPanel.shortcuts`, add at the top:

```swift
        ("Esc", "Normal mode"),
        ("i / a / o", "Insert mode: here / after / on a new line"),
        ("h j k l  w b e  0 $  gg G", "Move (with counts: 3w)"),
        ("d c y + motion", "Delete / change / yank"),
        ("dd  yy  x  p  u  .", "Line delete / yank, char delete, put, undo, repeat"),
        ("v / V", "Visual / visual line"),
```

- [ ] **Step 3: Build, run tests, commit**

Run: `./bin/test` (all green), then:

```bash
git add README.md Sources/Write/ShortcutsPanel.swift
git commit -m "Document vim mode

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Self-review

**Spec coverage:** modes (T5, T7, T8, T9); motions table — h l (T1), j k (T5/T9 via `moveDisplayLines`), w b e W B E (T2), 0 ^ $ (T1), gg G {} f t F T ; , (T3/T5); normal-caret clamp (T1 + `settleCaret` T9); operators d c y, dd cc yy, x X, p P, u ^R, `.`, i a I A o O (T6/T7), cw→ce (T6), linewise rules (T4); visual modes incl. `o` swap and `p` (T8); register (T6); `.` for inserts with counts (T7); footer + block caret (T10); errors — beep on unknown, quiet on failed motion, counts capped (T5), empty register no-op (T6); testing lists (T1–T10); docs (T11). Not covered: the spec's "an insert session is one undo step" — NSTextView coalesces typing on its own; leave as is and note in the commit for T9. `d}` on the last paragraph deleting to the end — covered by `paragraphForwardOnce` returning `n` and the exclusive range (T3/T4), but add one assertion to T4's `testExclusiveInclusiveAndLinewiseRanges`: `operandRange(of: .paragraphForward, from: 24, in: paragraphs)` equals `NSRange(location: 24, length: 4)`.

**Placeholder scan:** the sketches marked "clean-ups the implementer must make" are intentional and each says exactly what to change; nothing is TBD.

**Type consistency:** `VimOperandRange(range:linewise:)` (T4) is what `apply` (T6) and `visualRange` (T8) consume; `VimCommand` cases are identical in T5's definition, T9's `execute`, and every test; `VimState.pendingText`, `register`, `lastChange`, `visualAnchor`, `mode` are the only members tests read and are declared with those exact names in T5. `MarkdownTextView.apply(_:)` takes a `TextEdit` (existing type). `Fonts.characterWidth(of:)` exists.
