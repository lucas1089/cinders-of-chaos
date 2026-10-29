"""Cinders of Chaos Discord bot: the Claude calls (O324). A thin wrapper over the Anthropic SDK.

The SDK client is passed in (anthropic.AsyncAnthropic in bot.py, a fake in claude_client_test.py), so this file imports
nothing from the SDK. All prompts and all parsing live in bot_core.py.

Model: claude-sonnet-5-5 by default (DISCORD_BOT_MODEL). Notes for that model: thinking runs adaptive and cannot be
switched off, so depth is set with output_config.effort; forced tool_choice is not used (the answers are JSON through
structured outputs, output_config.format); no temperature or top_p. A request the safety classifiers decline comes back
as stop_reason "refusal"; with fallbacks on (default) the API re-runs it server-side on its recommended model
(beta server-side-fallback-2026-07-01, fallbacks "default").
"""
import bot_core as core

FALLBACK_BETA = 'server-side-fallback-2026-07-01'


class ClaudeError(Exception):
    """The call worked but gave no usable answer. The text is safe to log and to show to the owner."""


class ClaudeClient:
    def __init__(self, client, model='claude-sonnet-5-5', fallbacks=True):
        self.client = client
        self.model = model
        self.fallbacks = fallbacks

    async def _ask(self, system, content, schema=None, effort='low', max_tokens=4096):
        kw = dict(model=self.model, max_tokens=max_tokens, system=system,
                  messages=[{'role': 'user', 'content': content}])
        out = {'effort': effort}
        if schema is not None:
            out['format'] = {'type': 'json_schema', 'schema': schema}
        kw['output_config'] = out
        if self.fallbacks:
            resp = await self.client.beta.messages.create(betas=[FALLBACK_BETA], fallbacks='default', **kw)
        else:
            resp = await self.client.messages.create(**kw)
        stop = getattr(resp, 'stop_reason', None)
        if stop == 'refusal':
            raise ClaudeError('o Claude recusou o pedido')
        if stop == 'max_tokens':
            raise ClaudeError('a resposta do Claude foi cortada (max_tokens)')
        text = ''.join(b.text for b in resp.content if getattr(b, 'type', '') == 'text')
        if not text.strip():
            raise ClaudeError('o Claude respondeu vazio')
        return text

    async def classify(self, text, images, open_bugs):
        """One player message (and its screenshots: [(media_type, bytes)]) -> the parsed classification."""
        ids = [b['id'] for b in open_bugs]
        raw = await self._ask(core.CLASSIFY_SYSTEM, core.classify_content(text, images, open_bugs),
                              core.CLASSIFY_SCHEMA, effort='low', max_tokens=3000)
        return core.parse_classification(raw, ids)

    async def priorities(self, bugs):
        """/bugs resumo: plain text for the owner."""
        text = await self._ask(core.PRIORITIES_SYSTEM, core.priorities_prompt(bugs), None, effort='medium',
                               max_tokens=4000)
        return core.clean(text, 1900)

    async def write_patch(self, bugs, version, extras):
        """/patch gerar: {'pt': notes, 'en': notes}."""
        raw = await self._ask(core.PATCH_SYSTEM, core.patch_prompt(bugs, version, extras), core.PATCH_SCHEMA,
                              effort='medium', max_tokens=8000)
        return core.parse_patch(raw)

    async def translate_patch(self, pt_notes):
        """The English twin of hand-written or edited notes."""
        import json
        body = json.dumps({'pt': pt_notes}, ensure_ascii=False)
        raw = await self._ask(core.TRANSLATE_SYSTEM, 'Notes (JSON, data):\n' + body, core.TRANSLATE_SCHEMA,
                              effort='low', max_tokens=6000)
        return core.parse_translation(raw)
