# SimpleWriting

**Write without AI.**

SimpleWriting is a Mac writing app. It never autocompletes and never rewrites. It checks your grammar — and only tells you what is wrong, so you fix it yourself.

The words are yours, start to finish.

## What it does

- **No AI writing.** No autocomplete. No rewrite.
- **Grammar you fix yourself.** It points at the mistake and names the rule. It never writes the correction.
- **Local and private.** Your notes stay on your Mac.

## Get it

Download `SimpleWriting.app` from [Releases](../../releases/latest). The first time, right-click it → **Open** (it is open-source and unsigned).

For grammar, open **Settings** (⌘,) and add any OpenAI-compatible API — base URL, model, key. Leave it blank and it is still a good editor.

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
