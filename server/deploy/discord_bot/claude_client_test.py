#!/usr/bin/env python3
"""Tests for claude_client.py (O324) with a fake SDK client: no network, no key.

Checks the request the bot sends (model, effort, structured output schema, fallbacks beta, screenshots as vision
blocks, no thinking / temperature / forced tool_choice), the parsing of the answers, and the refusal, max_tokens and
empty answers.

usage: python3 -I server/deploy/discord_bot/claude_client_test.py
"""
import asyncio
import json
import os
import sys
from types import SimpleNamespace as NS

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bot_core as core  # noqa: E402
from claude_client import ClaudeClient, ClaudeError, FALLBACK_BETA  # noqa: E402

failures = 0


def check(cond, label):
    global failures
    if not cond:
        failures += 1
        print('FAIL', label)


class Messages:
    def __init__(self, owner, beta):
        self.owner, self.beta = owner, beta

    async def create(self, **kw):
        self.owner.calls.append((self.beta, kw))
        return self.owner.reply


class FakeSDK:
    def __init__(self, text='', stop='end_turn', blocks=None):
        self.calls = []
        content = blocks if blocks is not None else [NS(type='thinking', thinking=''), NS(type='text', text=text)]
        self.reply = NS(stop_reason=stop, content=content)
        self.messages = Messages(self, False)
        self.beta = NS(messages=Messages(self, True))


def run(coro):
    return asyncio.run(coro)


def raises_claude(coro, text):
    try:
        run(coro)
    except ClaudeError as e:
        return text in str(e)
    return False


CLS = json.dumps({'kind': 'bug', 'title': 'Crash', 'summary': 'Fecha.', 'severity': 'critico', 'repro_steps': ['a'],
                  'duplicate_of': 2})
NOTE = {'title': 'T', 'intro': '', 'new': [{'lead': '', 'text': 'x'}], 'changes': [], 'fixes': [], 'balance': []}


def main():
    open_bugs = [{'id': 2, 'title': 'Crash', 'summary': 's', 'severity': 'alto', 'report_count': 1}]
    sdk = FakeSDK(CLS)
    c = ClaudeClient(sdk, fallbacks=True)
    r = run(c.classify('trava ao abrir o mapa', [('image/png', b'abc')], open_bugs))
    beta, kw = sdk.calls[0]
    check(r['severity'] == 'critico' and r['duplicate_of'] == 2 and r['kind'] == 'bug', 'classified')
    check(beta and kw['betas'] == [FALLBACK_BETA] and kw['fallbacks'] == 'default', 'fallbacks on the beta endpoint')
    check(kw['model'] == 'claude-sonnet-5-5' and kw['output_config']['effort'] == 'low', 'model and effort')
    check(kw['output_config']['format']['type'] == 'json_schema'
          and kw['output_config']['format']['schema'] is core.CLASSIFY_SCHEMA, 'structured output')
    check('thinking' not in kw and 'temperature' not in kw and 'tool_choice' not in kw and 'top_p' not in kw,
          'no thinking, sampling or forced tool')
    content = kw['messages'][0]['content']
    check(content[1]['type'] == 'image' and content[1]['source']['media_type'] == 'image/png', 'screenshot sent as vision')
    check(kw['system'] == core.CLASSIFY_SYSTEM and kw['max_tokens'] >= 1000, 'system prompt')

    sdk = FakeSDK(CLS)
    c = ClaudeClient(sdk, model='claude-opus-5-5', fallbacks=False)
    run(c.classify('x' * 10, [], []))
    beta, kw = sdk.calls[0]
    check(not beta and 'betas' not in kw and 'fallbacks' not in kw and kw['model'] == 'claude-opus-5-5',
          'fallbacks off: the plain endpoint, the chosen model')
    # an id Claude invents is dropped
    check(run(ClaudeClient(FakeSDK(CLS)).classify('x' * 10, [], []))['duplicate_of'] is None, 'duplicate id must be open')

    check(raises_claude(ClaudeClient(FakeSDK(stop='refusal')).classify('x', [], []), 'recusou'), 'refusal')
    check(raises_claude(ClaudeClient(FakeSDK(CLS, stop='max_tokens')).classify('x', [], []), 'cortada'), 'max_tokens')
    check(raises_claude(ClaudeClient(FakeSDK(blocks=[NS(type='thinking', thinking='')])).classify('x', [], []), 'vazio'),
          'only a thinking block')
    try:
        run(ClaudeClient(FakeSDK('não é json')).classify('x', [], []))
        check(False, 'bad json refused')
    except core.BotError:
        check(True, 'bad json refused')

    sdk = FakeSDK('1. Corrigir #1 primeiro. @everyone')
    t = run(ClaudeClient(sdk).priorities([{'id': 1, 'title': 'A', 'summary': 'b', 'severity': 'alto', 'status': 'aberto',
                                          'report_count': 3}]))
    _, kw = sdk.calls[0]
    check('@everyone' not in t and 'Corrigir #1' in t, 'priorities text cleaned')
    check('format' not in kw['output_config'] and kw['output_config']['effort'] == 'medium', 'priorities: free text, medium')
    check('#1 | alto | aberto | 3 relatos' in kw['messages'][0]['content'], 'priorities prompt lists the bugs')

    sdk = FakeSDK(json.dumps({'pt': NOTE, 'en': dict(NOTE, title='T-en')}))
    p = run(ClaudeClient(sdk).write_patch([{'id': 1, 'title': 'Item some', 'summary': 'x'}], '0.9', 'extra: novo boss'))
    _, kw = sdk.calls[0]
    check(p['en']['title'] == 'T-en' and kw['output_config']['format']['schema'] is core.PATCH_SCHEMA, 'write_patch')
    check('Item some' in kw['messages'][0]['content'] and 'novo boss' in kw['messages'][0]['content']
          and '0.9' in kw['messages'][0]['content'] and 'BUG-' not in kw['messages'][0]['content'], 'patch prompt')
    check('#1' not in kw['messages'][0]['content'], 'bug numbers are not sent to the patch writer')

    sdk = FakeSDK(json.dumps({'en': dict(NOTE, title='Translated')}))
    e = run(ClaudeClient(sdk).translate_patch(core.normalize_notes_lang(NOTE)))
    check(e['title'] == 'Translated' and 'Notes (JSON' in sdk.calls[0][1]['messages'][0]['content'], 'translate_patch')
    print('claude_client_test: %s' % ('ok' if not failures else '%d failure(s)' % failures))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
