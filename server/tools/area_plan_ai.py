#!/usr/bin/env python3
"""Optional AI adapter of the area planner: `area_planner.py plan --from-prompt "..."` (docs/MAP_GUIDE.md "Area planner").

It runs only when the user has set an endpoint (and a key where one is needed) in environment variables on their own
machine. It never stores, prints or searches for a key: it reads exactly the variable named below and sends it only in
the request header to the endpoint the user set.

  AREAPLAN_LLM            anthropic (default) or openai (any OpenAI-compatible chat endpoint, such as a local Ollama)
  ANTHROPIC_API_KEY       the key for anthropic
  AREAPLAN_LLM_ENDPOINT   anthropic: default https://api.anthropic.com/v1/messages
                          openai: required, the chat completions URL, e.g. http://localhost:11434/v1/chat/completions
  AREAPLAN_LLM_KEY        openai: the bearer key (not needed for an endpoint on localhost)
  AREAPLAN_LLM_MODEL      required: the model name your provider gives (no default is kept in the repo)

The prompt holds the schema, the biomes and their materials, the monsters of the band, the NPCs, the rules, and in
each fix round the validator's errors. At most MAX_FIX_ROUNDS fix rounds follow the first answer.
"""
import json, os, re, urllib.error, urllib.request
from urllib.parse import urlparse

import area_plan_core as C

MAX_FIX_ROUNDS = 3
ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages'

HOWTO = """No AI endpoint is set up, so `plan --from-prompt` cannot run. Plans can always be written by hand
(server/tools/areaplan/examples/, docs/MAP_GUIDE.md "Area planner").

To use Anthropic's API, set on your own machine (the key is read from the environment only, never stored):
    export ANTHROPIC_API_KEY=...            # your key
    export AREAPLAN_LLM=anthropic           # optional, the default
    export AREAPLAN_LLM_MODEL=<model name>  # required: a current model of your provider

To use a local OpenAI-compatible server (for example Ollama):
    export AREAPLAN_LLM=openai
    export AREAPLAN_LLM_ENDPOINT=http://localhost:11434/v1/chat/completions
    export AREAPLAN_LLM_MODEL=<the model name>
    export AREAPLAN_LLM_KEY=...             # only for an endpoint that is not on localhost
"""


class NotConfigured(Exception):
    pass


def settings(env=None):
    """(provider, endpoint, model, key) from the environment; NotConfigured when something is missing"""
    env = os.environ if env is None else env
    prov = (env.get('AREAPLAN_LLM') or 'anthropic').strip().lower()
    if prov == 'anthropic':
        key = env.get('ANTHROPIC_API_KEY')
        if not key:
            raise NotConfigured('ANTHROPIC_API_KEY is not set')
        model = env.get('AREAPLAN_LLM_MODEL')
        if not model:
            raise NotConfigured('AREAPLAN_LLM_MODEL is not set (the model name your provider gives)')
        return prov, env.get('AREAPLAN_LLM_ENDPOINT') or ANTHROPIC_URL, model, key
    if prov == 'openai':
        url = env.get('AREAPLAN_LLM_ENDPOINT')
        model = env.get('AREAPLAN_LLM_MODEL')
        if not url or not model:
            raise NotConfigured('AREAPLAN_LLM_ENDPOINT and AREAPLAN_LLM_MODEL must be set for an OpenAI-compatible endpoint')
        key = env.get('AREAPLAN_LLM_KEY')
        host = (urlparse(url).hostname or '').lower()
        if not key and host not in ('localhost', '127.0.0.1', '::1'):
            raise NotConfigured('AREAPLAN_LLM_KEY is not set (needed for an endpoint that is not on localhost)')
        return prov, url, model, key
    raise NotConfigured('AREAPLAN_LLM must be anthropic or openai, not "%s"' % prov)


def _post(url, headers, body, timeout=600):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=headers, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        # the body of an error names the problem; the request headers (and the key) are never echoed
        detail = e.read().decode(errors='replace')[:500]
        raise RuntimeError('the endpoint answered HTTP %d: %s' % (e.code, detail))
    except urllib.error.URLError as e:
        raise RuntimeError('the endpoint could not be reached: %s' % e.reason)


def make_transport(env=None):
    """a function (system, messages) -> (reply text, the assistant message to append to the history)"""
    prov, url, model, key = settings(env)
    if prov == 'anthropic':
        def send(system, messages):
            headers = {'content-type': 'application/json', 'x-api-key': key, 'anthropic-version': '2023-06-01'}
            body = dict(model=model, max_tokens=16000, system=system, messages=messages,
                        output_config={'effort': 'medium'})
            if url == ANTHROPIC_URL:
                # route a declined request to another model instead of failing (server-side fallback)
                headers['anthropic-beta'] = 'server-side-fallback-2026-07-01'
                body['fallbacks'] = 'default'
            res = _post(url, headers, body)
            if res.get('stop_reason') == 'refusal':
                raise RuntimeError('the model declined the request')
            content = res.get('content', [])
            # the whole answer goes back into the history unchanged (thinking blocks included)
            return ''.join(b.get('text', '') for b in content if b.get('type') == 'text'), \
                {'role': 'assistant', 'content': content}
        return send

    def send(system, messages):
        headers = {'content-type': 'application/json'}
        if key:
            headers['authorization'] = 'Bearer ' + key
        body = dict(model=model, messages=[{'role': 'system', 'content': system}] + messages, temperature=0.4)
        res = _post(url, headers, body)
        text = res['choices'][0]['message']['content']
        return text, {'role': 'assistant', 'content': text}
    return send


def system_prompt(cat, band=None):
    schema = json.dumps(C.load_schema(), indent=1)
    biomes = '\n'.join('- %s (%s, %s): %s' % (k, b['kind'], ', '.join(b['families']), b['desc'])
                       for k, b in sorted(cat['biomes'].items()))
    mons = sorted(C.monsters().values(), key=lambda m: (m['level'] or 0, m['name']))
    if band:
        _t, lo, hi = C.tier_window(*band)
        if lo is not None:
            mons = [m for m in mons if m['level'] and lo <= m['level'] <= int(hi * 1.5)]
    mlist = '; '.join('%s %s%s' % (m['name'], m['level'] or '?', ' boss' if m['boss'] else '') for m in mons)
    tiers = ', '.join('%d-%s takes monsters %d-%d' % (t[0], t[1] if t[1] < 99999 else '+', t[2], t[3]) for t in C.tiers())
    npcs = ', '.join(sorted(C.npcs().values()))
    return """You design hunting areas for Cinders of Chaos, a dark fantasy game server. You write one area plan as JSON
that follows the schema below exactly. The plan is semantic: it never holds an item id, a tile list or coordinates
beyond the optional zone "at" and "origin". The planner turns it into tiles with our own materials.

Rules the validator enforces:
- every zone is reachable from the entry (paths join zones of one floor; stairs, ladder and hole join floors next to
  each other, a hole only goes down; teleports join any two zones);
- the entry zone is on floor 1; the boss room (role "boss") has exactly one way in; the boss stands in it;
- no spawn in a zone with "pz": true; NPCs belong in a pz zone;
- monster names come from the list below, with a level inside the window of the area's level band;
- the level band stays inside one tier or two neighbouring tiers: %s;
- zones fit in the area with 4 tiles of rim and 3 tiles between zones; 1.5-5 monsters per 100 walkable tiles;
- a good hunt has a loop of zones and a dead-end pocket or two.

Biomes (kind, materials):
%s

Monsters (name level):
%s

NPCs: %s

Schema:
%s

Answer with the JSON plan only, no other text.""" % (tiers, biomes, mlist, npcs, schema)


def extract_json(text):
    m = re.search(r'```(?:json)?\s*(\{.*\})\s*```', text, re.S)
    s = m.group(1) if m else text[text.find('{'):text.rfind('}') + 1]
    return json.loads(s)


def plan_from_prompt(prompt, transport, cat, band=None, log=print):
    """(plan, issues, rounds): the first answer and up to MAX_FIX_ROUNDS rounds with the validator's errors"""
    system = system_prompt(cat, band)
    messages = [{'role': 'user', 'content': prompt}]
    plan, issues = None, []
    for rnd in range(MAX_FIX_ROUNDS + 1):
        reply, said = transport(system, messages)
        messages.append(said)
        try:
            plan = extract_json(reply)
            issues = C.validate(plan, cat)
            errs = C.errors(issues)
        except (ValueError, TypeError) as e:
            plan, errs = None, ['the answer is not one JSON object: %s' % e]
        if not errs:
            log('round %d: the plan validates' % rnd)
            return plan, issues, rnd
        log('round %d: %d error(s)' % (rnd, len(errs)))
        if rnd == MAX_FIX_ROUNDS:
            break
        messages.append({'role': 'user', 'content': 'The validator found these errors. Return the whole corrected plan '
                         'as JSON only.\n' + '\n'.join(str(e) for e in errs)})
    return plan, issues, MAX_FIX_ROUNDS
