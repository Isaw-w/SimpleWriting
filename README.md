# SimpleWriting

**A minimalist macOS editor that helps you write — without AI.**

SimpleWriting is a clean, distraction-free editor for writing in your *own* words. There is no autocomplete and no rewrite. The one thing it does for you is check your grammar — and even then it only tells you what is wrong and lets you fix it yourself.

The whole idea: **use it to build your own agency and write your best possible piece.**

## Philosophy

The words on the page are yours, start to finish. It is for people learning English, practising their craft, or who simply believe writing is worth doing yourself.

> You do the writing. You keep the agency. You produce your best possible piece.

## Features

1. **No AI writing.** No text generation, no autocomplete, no rewrite. Every word on the page is yours.
2. **Grammar you fix yourself.** It tells you when your grammar is wrong — but it will *not* fix it for you. You make the correction by hand, and exercise your own cognitive power.
3. **Local and private.** Everything stays on your Mac, like a notes app. No folders to manage, nothing to export, nothing in the cloud.

## Markdown

Type markdown and it becomes real formatting as you go — the document is stored as clean Markdown and round-trips exactly:

| You type | You get |
|---|---|
| `# ` … `###### ` | Headings 1–6 |
| `**bold**` | **bold** |
| `_italic_` | *italic* |
| `~~strike~~` | strikethrough |
| `` `code` `` | inline `code` |
| `$x^2$` · `$$…$$` | inline & display math (KaTeX) |
| ` ``` ` | a code block |
| `> ` | blockquote |
| `- ` / `* ` / `1. ` | bullet / ordered lists |
| Tab / Shift-Tab | indent / outdent (nested lists), or move between table cells |
| `---` | horizontal rule |
| `\| a \| b \|` … | GFM tables (⇧⌘T inserts one) |

Plus ⌘B / ⌘I / ⌘` for bold / italic / code, ⇧⌘X for strikethrough, ⌘K for a link, Shift-Enter for a line break, ⇧⌘C to toggle a code block, and ⇧⌘T to insert a table. Pasting Markdown text keeps its formatting. Math renders offline with KaTeX.

## Install

1. [Download `SimpleWriting.app`](../../releases/latest) from the Releases page.
2. It's open-source and not notarized, so the first time: **right-click the app → Open → Open.** (You only do this once.)
3. Open **Settings** (⌘,) and add your OpenAI-compatible **Base URL**, **Model**, and **API Key** to turn on the grammar check.

The grammar check works with any OpenAI-compatible API (DeepSeek, OpenAI, OpenRouter, Groq, or a local model). Leave the fields blank and SimpleWriting is still a fine distraction-free editor.

## Build it yourself

Requires the Xcode command-line tools, macOS 13+:

```bash
git clone https://github.com/Isaw-w/SimpleWriting.git
cd SimpleWriting
./build.sh
open SimpleWriting.app
```

## How the grammar check works

It is deliberately conservative and **explain-only**: it marks the smallest wrong span — a single word or short phrase, never a whole sentence — and gives you the rule, not the rewrite ("the subject is singular, so the verb should be singular" — not "change *give* to *gives*"). Checks run at temperature 0, so the same text yields the same result — no errors that come and go.

## License

[MIT](LICENSE) © 2026 Jack Crusher

---

<sub>A minimalist writing app to write without AI on macOS — no autocomplete, no rewrite, only a grammar checker you fix yourself. Distraction-free, local, and private, like a notes app. Open source.</sub>
