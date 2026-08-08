# SimpleWriting

**A minimalist macOS writing app that never writes for you.**

SimpleWriting is a clean, distraction-free editor for people who want to write in their *own* words. It will not autocomplete your sentences, rewrite your paragraphs, or generate text. There is no AI ghostwriter here. The one thing it does for you is **check your grammar** — and even then it only points at the mistake and names the rule. You make the fix yourself.

That's the whole philosophy: **you do the writing. You keep the agency. You produce your best possible piece.**

---

## Why

Most modern writing tools now finish your thoughts for you. That is convenient, and it is also how you stop being a writer. SimpleWriting takes the opposite stance:

- **No text generation.** No autocomplete, no "rewrite this," no AI suggestions to accept. The words on the page are yours.
- **Grammar check that teaches, not replaces.** When something is genuinely wrong — subject–verb agreement, a wrong article, a misspelling — it highlights the exact word and explains the rule. It never shows you the corrected sentence. You fix it, so you learn it.
- **It trusts your voice.** Register, style, and imperfect-but-intentional phrasing are left alone. It flags real errors, not your personality.
- **Minimal by design.** One window. Your drafts on the left, your writing on the right. Nothing else asking for your attention.

If you are learning English, practicing your craft, or you simply believe writing is worth doing yourself, this is for you.

## Features

- Distraction-free, WYSIWYG editor (real bold/italic and clean links — no Markdown symbols in your face).
- Local draft history — every piece saved on your machine, nothing in the cloud.
- Grammar check via any **OpenAI-compatible** API (DeepSeek, OpenAI, OpenRouter, Groq, or a local model). Explain-only, never auto-correct.
- Always-on local style highlights (long sentences, adverbs, passive voice, qualifiers) computed on-device.
- Adjustable text size, light theme, native macOS app.
- Your API key stays in your own settings. Your drafts stay on disk.

## Install

**Download:** grab the latest `SimpleWriting.app` from the [Releases](../../releases) page.

Because the app is open-source and ad-hoc signed (not notarized), macOS Gatekeeper will ask the first time:

> **Right-click the app → Open → Open.** You only do this once.

**Or build from source** (requires Xcode command-line tools, macOS 13+):

```bash
git clone https://github.com/Isaw-w/SimpleWriting.git
cd SimpleWriting
./build.sh          # produces SimpleWriting.app
open SimpleWriting.app
```

## Configure the grammar check

Grammar checking talks to any OpenAI-compatible chat API. Open **SimpleWriting → Settings** (⌘,) and fill in:

- **Base URL** — e.g. `https://api.deepseek.com/beta`
- **Model** — e.g. `deepseek-chat`
- **API Key** — your own key

That's it. The local style highlights work with no key at all. If you leave the API fields blank, SimpleWriting is a perfectly good distraction-free editor without the grammar layer.

## How the grammar check works

The checker is deliberately conservative and **explain-only by design**:

- It marks the **smallest** wrong span — a single word or short phrase, never a whole sentence.
- It gives the **rule**, never the rewrite. ("The subject is singular, so the verb should be singular." — not "change *give* to *gives*.")
- It runs at temperature 0 so the same text yields the same result — no flickering, no errors that come and go.
- Style (wordiness, adverbs, passive voice) is highlighted locally and deterministically, on your machine.

## Philosophy, in one line

> Write it yourself. Express your agency. Make your best possible piece.

## License

[MIT](LICENSE) © 2026 Jack Crusher

---

<sub>Keywords: minimalist writing app, distraction-free editor for Mac, writing app without AI, no-AI writing tool, grammar checker macOS, write in your own words, English writing practice app, offline writing app, open-source macOS editor.</sub>
