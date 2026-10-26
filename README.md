# FlowGorithmForMac

A native macOS app (26 Tahoe and later) for writing and running programs as flowcharts, written in Swift and SwiftUI. It opens and saves the `.fprg` files of [Flowgorithm](http://www.flowgorithm.org), so exercises and assignments move freely between the two.

> Independent, clean-room project. It is not affiliated with or endorsed by Flowgorithm or its author, Devin Cook. No code from the original application is used: everything is based on its public documentation and on its observable behavior.

## Features

- **Every shape**: Declare, Assign, Input, Output, If, While, For, Do, Call, Comment, Breakpoint, file I/O (Open, Read, Write, Close) and turtle graphics (Forward, Turn, Home, Clear, Pen).
- **Flowgorithm's semantics**: floating-point division, explicit declarations, `&` for concatenation, case-insensitive names, its own call stack (runaway recursion is an error, not a crash), and all the intrinsic functions (`Sqrt`, `Len`, `ToFixed`, `Random`…). Operators can be written C-style, BASIC-style or as math symbols (`&&`, `and`, `∧`).
- **Editor**: click the `+` on any connector to insert a shape, double-click to edit, drag to move, plus copy, paste, duplicate and undo. Expressions are checked as you type, and errors are explained in plain words.
- **Running**: run, step one shape at a time, pause and stop (⌘R, ⌘', ⌥⌘P, ⌘. and F5–F8 as in Flowgorithm), with adjustable speed and breakpoints. The current shape is highlighted.
- **Panels**: chat-style console (or plain text), a variable watch colored by type with arrays, a turtle graphics canvas, and live source code.
- **Source code** in Python, Java, C++, C#, JavaScript, TypeScript, Swift and Kotlin, plus pseudocode in Italian and in English. Lines stay linked to their shapes.
- **Five color schemes** (Classic, Modern, Pastel, Neon, Black & White), all adapting to light and dark mode.
- **Export** to PNG, PDF and SVG, and printing.
- **Italian and English**, following the system language or chosen in Settings.

## Safe with flowcharts from others

A `.fprg` file can come from anyone, so running one can't harm the Mac:

- Programs read and write files in the flowchart's folder freely. For any other file (another folder, `..`, `~`, a link pointing elsewhere, or every file of a flowchart not saved yet) the app shows the full path and asks first. Folders, devices and files over 32 MB are refused.
- Opening a file never loads external XML entities, and absurdly deep shapes or expressions are refused with a clear error instead of crashing the app.
- Arrays and texts have a memory limit, and the console stays responsive even when a program prints without end.

## Building

You need Xcode 26 or later. Open `FlowGorithmForMac.xcodeproj` and run, or from the terminal:

```sh
xcodebuild -project FlowGorithmForMac.xcodeproj -scheme FlowGorithmForMac -configuration Release -derivedDataPath build/DerivedData build
```

The app lands in `build/DerivedData/Build/Products/Release/FlowGorithmForMac.app`. To package it, run `Scripts/make-dmg.sh <version>`: it writes `dist/FlowGorithmForMac-<version>.dmg` and prints its SHA-256. With a Developer ID, set `SIGN_IDENTITY` and `NOTARY_PROFILE` to sign and notarize the image (see the script).

## Project layout

- `FlowCore/`: a Swift package with no UI. It holds the program model, the `.fprg` reader and writer, the expression parser, the interpreter and the code generators. Run its tests with `swift test` inside the folder.
- `FlowGorithmForMac/`: the SwiftUI app (chart layout and drawing, editors, panels, themes).
- `Scripts/`: helpers. `sync-strings.py` rebuilds the string catalog after a command-line build, and `make-icon-glyph.swift` draws the app icon layers.

## Translations

Command-line builds don't update `Localizable.xcstrings`. After building, run:

```sh
python3 Scripts/sync-strings.py build/DerivedData
```

Italian texts live in `Scripts/translations-it.json`. The script lists any string still missing a translation.
