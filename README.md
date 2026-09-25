# LUAM — Lift up and Markdown

A native macOS Markdown editor and reader: source on the left, live preview on
the right, an outline of your headings in the sidebar. CommonMark and GitHub
Flavored Markdown, with math, Mermaid diagrams, and export to HTML and PDF.

## Requirements

- macOS 26 or later
- Xcode 27 or later (to build it — LUAM isn't distributed as a download)

## Install

### With the install script (recommended)

```bash
git clone https://github.com/3vangelos-humanoo/LUAM.git
cd LUAM
Scripts/install-app.sh
```

The script builds a Release version, quits LUAM if it's running, installs it
into `/Applications` (or `~/Applications` if `/Applications` isn't writable)
and opens it. If the build fails it stops without touching an installed copy
and points you to the log in `build/DerivedData.log`.

To update later, pull and run the script again:

```bash
git pull
Scripts/install-app.sh
```

### With Xcode

1. Open `LUAM.xcodeproj`.
2. Choose the **LUAM** scheme and **My Mac** as the destination.
3. **Product ▸ Run** (⌘R) to try it, or **Product ▸ Archive** and then
   **Distribute App ▸ Copy App** to get a `LUAM.app` you can move into
   Applications yourself.

### Make LUAM open Markdown files

In Finder, select any `.md` file, press ⌘I, choose **LUAM** under
**Open with**, and click **Change All…**.

### Uninstall

Quit LUAM and move `LUAM.app` from Applications to the Trash. Settings live in
`~/Library/Preferences/com.esismanidis.LUAM.plist` if you want those gone too.

### Troubleshooting

- **"LUAM can't be opened because Apple cannot check it"** — only happens if
  you copied a built app from another Mac. Right-click the app, choose
  **Open**, and confirm once. Apps you build yourself aren't affected.
- **Build fails with signing errors** — LUAM is signed locally ("Sign to Run
  Locally"), so no Apple developer account is needed. If Xcode insists on a
  team, pick your personal team under the target's **Signing & Capabilities**.
- **`xcode-select` points at the Command Line Tools** — run
  `sudo xcode-select -s /Applications/Xcode.app` so the script finds Xcode.

## Using LUAM

| | |
|---|---|
| **View** | ⌘1 source · ⌘2 split · ⌘3 preview · ⌃⌘S outline · ⌘+ / ⌘- / ⌘0 text size |
| **Writing** | ⇧⌘F focus mode · ⌥⌘Y typewriter scrolling |
| **Format** | ⌘B bold · ⌘I italic · ⇧⌘X strikethrough · ⇧⌘K code · ⌘K link |
| **Blocks** | ⌃⌘1–6 headings · ⌃⌘0 body text · ⇧⌘' quote · ⇧⌘L bullets · ⌥⌘L numbers · ⇧⌘T tasks · ⌥⌘T align table |
| **File** | ⇧⌘E export HTML · ⌥⌘E export PDF · ⌘P print · ⌥⌘C copy as HTML |

While typing, Return continues lists and quotes, Tab / ⇧Tab indent (or move
between table cells), and brackets and quotes close themselves. Dropping
files onto the editor inserts links; pasting a screenshot into a saved
document stores it in an `assets` folder next to it and links it. Task
checkboxes in the preview can be clicked.

Math goes in `$…$` or `$$…$$` (or a ` ```math ` block) and is typeset with
KaTeX; ` ```mermaid ` blocks become diagrams. Both libraries are bundled, so
this works offline. `Samples/` has documents that show everything off.

Themes, text sizes, auto-pairing, spell checking and scroll syncing are in
**LUAM ▸ Settings…** (⌘,).

## Development

```bash
Scripts/run-parser-tests.sh   # parser and editing tests, no Xcode build needed
Scripts/typecheck-app.sh      # typechecks the whole app with swiftc
```

The tests also run in Xcode with **Product ▸ Test** (⌘U).

## Third-party code

LUAM bundles [KaTeX](https://katex.org) 0.18.9 and
[Mermaid](https://mermaid.js.org) 11.17.2, both under the MIT license — see
`LUAM/Preview/Vendor/KaTeX-LICENSE.txt` and `Mermaid-LICENSE.txt`.
