#!/usr/bin/env python3
"""Mutation checks for the WhatsApp ingress/action boundary.

Each mutant reintroduces one unsafe shortcut and must make its focused Python
test suite red. The source files are restored in a finally block after every
case; this script never writes to Supabase, UAZAPI or the VPS.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
MUTANTS = [
    {
        "name": "ambiguous audio becomes registration",
        "file": "fabio_whatsapp_actions.py",
        "test": "teste_whatsapp_actions.py",
        "old": 'if intent == "ambiguo":\n            action = _start(backend, context, "confirmar_intencao_audio", storage_path,',
        "new": 'if False:\n            action = _start(backend, context, "confirmar_intencao_audio", storage_path,',
    },
    {
        "name": "ambiguous text opens call pool before confirmation",
        "file": "fabio_whatsapp_actions.py",
        "test": "teste_whatsapp_actions.py",
        "old": 'if intent == "ambiguo":\n        action = _start(backend, context, "confirmar_intencao_chamada", None,',
        "new": 'if False:\n        action = _start(backend, context, "confirmar_intencao_chamada", None,',
    },
    {
        "name": "mixed text silently becomes call",
        "file": "fabio_whatsapp_intents.py",
        "test": "teste_whatsapp_intents.py",
        "old": 'def _text_heuristic(text: str) -> TextIntent:\n    hay = _norm(text)\n    if not hay:\n        return "ambiguo"\n    has_presence = _has_phrase(hay, _PRESENCE_WORDS)\n    has_content = _has_phrase(hay, _CONTENT_WORDS)\n    if has_presence and has_content:\n        return "ambiguo"',
        "new": 'def _text_heuristic(text: str) -> TextIntent:\n    hay = _norm(text)\n    if not hay:\n        return "ambiguo"\n    has_presence = _has_phrase(hay, _PRESENCE_WORDS)\n    has_content = _has_phrase(hay, _CONTENT_WORDS)\n    if has_presence and has_content:\n        return "chamada"',
    },
    {
        "name": "course contradiction no longer filters shortlist",
        "file": "fabio_whatsapp_intents.py",
        "test": "teste_whatsapp_intents.py",
        "old": '        if mentioned and _norm(candidate.get(key)) not in mentioned:\n            return False',
        "new": '        if False and mentioned and _norm(candidate.get(key)) not in mentioned:\n            return False',
    },
    {
        "name": "generic pending message confirms",
        "file": "fabio_whatsapp_intents.py",
        "test": "teste_whatsapp_intents.py",
        "old": '    return {"tipo": "conversa"}',
        "new": '    return {"tipo": "confirmar"}',
        "last": True,
    },
    {
        "name": "replay uploads/starts again",
        "file": "fabio_whatsapp_actions.py",
        "test": "teste_whatsapp_actions.py",
        "old": '    if str(action.get("wa_message_id")) == str(context.get("wa_message_id")):',
        "new": '    if False:',
    },
    {
        "name": "action reply appends devolutiva",
        "file": "fabio_chat_bridge.py",
        "test": "teste_whatsapp_bridge.py",
        "old": '    insert_fabio_response_for_row(row, reply, "whatsapp")',
        "new": '    insert_fabio_response_for_row(row, str(reply) + " devolutiva", "whatsapp")',
    },
    {
        "name": "interception moves after Hermes",
        "file": "fabio_chat_bridge.py",
        "test": "teste_whatsapp_bridge.py",
        "old": '    if try_handle_whatsapp_action(row) is True:',
        "new": '    if False and try_handle_whatsapp_action(row) is True:',
    },
    {
        "name": "invalid mode defaults to on",
        "file": "fabio_chat_bridge.py",
        "test": "teste_whatsapp_bridge.py",
        "old": '    return mode if mode in {"off", "shadow", "pilot", "on"} else "off"',
        "new": '    return mode if mode in {"off", "shadow", "pilot", "on"} else "on"',
    },
    {
        "name": "webhook transcribes before durable inbox insert",
        "file": "fabio_chat_bridge.py",
        "test": "teste_whatsapp_bridge.py",
        "old": '    identity = resolve_identity_by_phone(phone)\n    inserted = insert_identity_message(',
        "new": '    identity = resolve_identity_by_phone(phone)\n    uazapi_transcrever_audio(str(wa_id))\n    inserted = insert_identity_message(',
    },
]


def run_test(test_file: str) -> bool:
    completed = subprocess.run(
        [sys.executable, "-B", test_file],
        cwd=HERE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=os.environ.copy(),
    )
    return completed.returncode == 0


def replace_one(source: str, old: str, new: str, last: bool = False) -> tuple[str, int]:
    count = source.count(old)
    if count != 1 and not last:
        return source, count
    if last:
        index = source.rfind(old)
        if index < 0:
            return source, 0
        return source[:index] + new + source[index + len(old):], count
    return source.replace(old, new), count


def main() -> int:
    originals: dict[Path, str] = {}
    original_bytes: dict[Path, bytes] = {}
    for mutant in MUTANTS:
        path = HERE / mutant["file"]
        originals.setdefault(path, path.read_text(encoding="utf-8"))
        original_bytes.setdefault(path, path.read_bytes())

    if not all(run_test(name) for name in {m["test"] for m in MUTANTS}):
        print("ABORTADO: a suíte base já falha sem mutante.")
        return 1

    mortos = 0
    stale = 0
    try:
        for mutant in MUTANTS:
            path = HERE / mutant["file"]
            source = originals[path]
            mutated, count = replace_one(source, mutant["old"], mutant["new"], mutant.get("last", False))
            if count == 0 or (count != 1 and not mutant.get("last", False)):
                print(f"STALE  {mutant['name']} — âncora aparece {count} vez(es)")
                stale += 1
                continue
            path.write_text(mutated, encoding="utf-8")
            if run_test(mutant["test"]):
                print(f"FALHA  sobreviveu: {mutant['name']}")
            else:
                mortos += 1
                print(f"OK     morto: {mutant['name']}")
            path.write_bytes(original_bytes[path])
    finally:
        for path, source in originals.items():
            path.write_bytes(original_bytes[path])

    print(f"\n{mortos}/{len(MUTANTS)} mutantes mortos" + (f" — {stale} âncora(s) podre(s)" if stale else ""))
    return 0 if mortos == len(MUTANTS) else 1


if __name__ == "__main__":
    raise SystemExit(main())
