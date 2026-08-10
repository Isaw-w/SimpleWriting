# SimpleWriting

**Write it yourself.**

SimpleWriting is a Mac writing app. You write every word. It checks your grammar, shows the mistake, and names the rule — you make the fix.

The words are yours, start to finish.

## What it does

- **You do the writing.** Every word on the page is yours.
- **Grammar you fix yourself.** It shows the mistake and names the rule. You make the correction.
- **Local and private.** Your notes stay on your Mac.
- **Math mode.** A switch in the toolbar turns a note into a math notebook. Type equations and it computes the answer, type `/2d` for a graph (functions and draggable geometry), or `/3d` for a surface — all offline, with room for notes beside the math.

## Get it

Download `SimpleWriting.app` from [Releases](../../releases/latest). The first time, right-click it → **Open**.

For grammar, open **Settings** (⌘,) and add any OpenAI-compatible API — base URL, model, key. It works as an editor with or without a key.

## Markdown

Type Markdown and it becomes formatting: headings, bold, italic, strikethrough, code, code blocks, lists, task boxes, tables, quotes, rules, and math (KaTeX, offline). It is stored as plain Markdown and round-trips exactly. Paste Markdown and it keeps its shape.

## Build it

```bash
git clone https://github.com/Isaw-w/SimpleWriting.git
cd SimpleWriting
./build.sh
```

macOS 13 or later.

## License

[MIT](LICENSE) © 2026 Jack Crusher
