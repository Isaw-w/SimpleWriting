# SimpleWriting

**Write it yourself.**

SimpleWriting is a Mac writing app. You write every word. It checks your grammar, shows the mistake, and names the rule — you make the fix.

The words are yours, start to finish.

## What it does

- **You do the writing.** Every word on the page is yours.
- **Grammar you fix yourself.** It shows the mistake and names the rule. You make the correction.
- **Local and private.** Your notes stay on your Mac.
- **Math mode.** A switch in the toolbar turns a note into a math notebook — see below. Grammar check works here too.

## Get it

Download `SimpleWriting.app` from [Releases](../../releases/latest). The first time, right-click it → **Open**.

For grammar, open **Settings** (⌘,) and add any OpenAI-compatible API — base URL, model, key. It works as an editor with or without a key.

## Markdown

Type Markdown and it becomes formatting: headings, bold, italic, strikethrough, code, code blocks, lists, task boxes, tables, quotes, rules, and math (KaTeX, offline). It is stored as plain Markdown and round-trips exactly. Paste Markdown and it keeps its shape.

## Math mode

Flip the **Note | Math** switch in the toolbar to turn any note into a math notebook. It is fully offline, and your prose notes sit right beside the math (with grammar check).

- **Inline math.** Write `$y = x^2$` in a note and it renders in place. Click it to edit the source again.
- **Compute.** Type `$$` for a field that evaluates as you go — `2 + 2` shows `= 4`, `\pi \cdot 3^2` shows `9\pi`.
- **2D graphs & geometry** (`/2d`). One expression per line:
  - `y = sin(x)` — plot a function
  - `A = (2, 1)` — a draggable point; `circle(A, 1.5)`, `segment(A, B)`, `line(A, B)` follow it
  - `vector(A, B)` or `vector(3, -2)` — vectors
  - `polygon(A, B, C)`, `angle(A, B, C)`, `midpoint(A, B)`, `perpendicular(line(A,B), C)`, sliders, and more
- **3D surfaces** (`/3d`). Enter `z = x^2 - y^2` or `z = sin(x)*cos(y)`; drag to orbit, scroll to zoom.

## Build it

```bash
git clone https://github.com/Isaw-w/SimpleWriting.git
cd SimpleWriting
./build.sh
```

macOS 13 or later.

## License

[MIT](LICENSE) © 2026 Jack Crusher
