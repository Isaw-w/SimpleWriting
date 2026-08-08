#!/usr/bin/env python3
"""Grammar-check evaluation for Amiliya Writer.

Runs a battery of sentences with known errors through the configured model and
reports recall (did it catch the error?) and span tightness (is the flagged
fragment the minimal wrong word/phrase?). Uses the same prompt as GrammarClient.
Reads the model config from the shared Amiliya prefs.
"""
import json, subprocess, urllib.request, sys

SYS = ("You are a careful copy-editor with a light touch. Judge grammar, spelling, and punctuation, "
       "and trust the writer's voice, word choices, and style.\n"
       "Flag a span when it is objectively wrong: subject-verb agreement, verb tense or form, articles, "
       "plurals, pronoun case, homophones (their/there, its/it's, your/you're, affect/effect), missing or "
       "incorrect punctuation, run-on sentences, and misspellings.\n"
       "Accept the writer's choices - do not flag: generic bare nouns and register-level missing articles, "
       "possessive forms including plural possessives (\"models' world\", \"the agent's world\"), and "
       "merely stylistic phrasing.\n"
       "Keep the indicative after verbs of perception, thought, or belief - feel, think, believe, seem, "
       "notice: 'I feel that it is beautiful' is correct as written and needs no change. Reserve the "
       "subjunctive for verbs of demand or necessity (suggest, insist, require, essential that).\n"
       "For each error, copy the smallest exact substring that contains the mistake - the wrong word or "
       "short phrase, long enough to appear only once in the text. Trust the writer and skip anything you "
       "are unsure about.\n"
       'Return raw JSON only: {"errors":[{"fragment":"exact substring, copied verbatim","focus":"grammar|spelling",'
       '"type":"short category","hint":"the rule"}]}\n'
       'Return {"errors":[]} when the writing is grammatically sound.')

# (sentence, [expected error keywords — any returned fragment containing one counts as caught], is_clean)
CASES = [
    ("She go to school every day.",              ["go"],            False),
    ("They have went to the store.",             ["went"],          False),
    ("I saw a elephant at the zoo.",             ["a elephant","a"],False),
    ("He dont like coffee.",                     ["dont"],          False),
    ("Their going to be late again.",            ["their"],         False),
    ("The dog wagged it's tail happily.",        ["it's"],          False),
    ("I have three childs now.",                 ["childs"],        False),
    ("She recieved the letter yesterday.",       ["recieved"],      False),
    ("Its definately going to rain today.",      ["definately"],    False),
    ("We was very happy about it.",              ["was"],           False),
    ("Your welcome to join us.",                 ["your"],          False),
    ("The books is on the table.",               ["is"],            False),
    ("He walk to the store yesterday.",          ["walk"],          False),
    ("The affect of the news was huge.",         ["affect"],        False),
    ("I went to the libary to study.",           ["libary"],        False),
    ("Each of the students have a book.",        ["have"],          False),
    ("Me and him are going fishing.",            ["me and him","him"], False),
    ("The world for a model is mostly text.",    [],                True),   # clean
    ("Writing is a demanding task that involves agency.", [],       True),   # clean
    ("We perceive the world through sight and touch.",    [],       True),   # clean
    ("Let's say this constitutes models' world.",         [],       True),   # clean: plural possessive
]

def cfg(key):
    try:
        return subprocess.check_output(["defaults","read","com.simplewriting.app",key],
                                       stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        return None

def main():
    key = cfg("api.key"); base = cfg("api.baseURL") or "https://api.deepseek.com/beta"; model = cfg("api.model") or "deepseek-chat"
    if not key:
        print("Missing API key in com.simplewriting.app — set it in SimpleWriting → Settings"); sys.exit(1)
    url = base.rstrip("/") + ("" if base.rstrip("/").endswith("/chat/completions") else "/chat/completions")

    caught = missed = false_pos = 0; clean_ok = 0; clean_total = 0
    print(f"model: {model}\n")
    for sentence, expected, is_clean in CASES:
        payload = {"model":model,"messages":[{"role":"system","content":SYS},
                   {"role":"user","content":"Text:\n"+sentence}],
                   "response_format":{"type":"json_object"},"max_tokens":2000,"thinking":{"type":"disabled"}}
        try:
            d = json.load(urllib.request.urlopen(urllib.request.Request(url, data=json.dumps(payload).encode(),
                headers={"Authorization":"Bearer "+key,"Content-Type":"application/json"}), timeout=60))
            frags = [e.get("fragment","") for e in json.loads(d["choices"][0]["message"]["content"]).get("errors",[])]
        except Exception as e:
            print(f"  ERROR calling API: {e}"); frags = []
        low = " | ".join(frags).lower()
        if is_clean:
            clean_total += 1
            ok = len(frags) == 0
            clean_ok += ok
            print(f"[{'✓ clean' if ok else '✗ FALSE+':8}] {sentence}   →  {frags if frags else '(none)'}")
        else:
            hit = any(k.lower() in low for k in expected)
            caught += hit; missed += (not hit)
            print(f"[{'✓ caught' if hit else '✗ MISS':8}] {sentence}   →  {frags}")
    total_err = caught + missed
    print(f"\nRecall (errors caught): {caught}/{total_err} = {caught/total_err*100:.0f}%")
    print(f"Clean sentences left alone: {clean_ok}/{clean_total}")

if __name__ == "__main__":
    main()
