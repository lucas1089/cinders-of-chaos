#!/usr/bin/env python3
"""Cinders of Chaos Discord bot (O324): bug reports and patch notes. The thin Discord layer.

The rules are in bot_core.py (pure, unit tested) and the Claude calls in claude_client.py. This file only connects
them to discord.py: the bugs channel, the daily DM, the /bugs and /patch commands. Settings come from the
environment (the systemd unit reads /etc/chaos/discord-bot.env, mode 600); see .env.example and README.md.

Logging: ids and counters only. A message's text, a token or a key is never logged.

usage: python3 -I bot.py        (the unit does this)
"""
import asyncio
import datetime
import io
import logging
import os
import sys
import time
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import discord  # noqa: E402
from discord import app_commands  # noqa: E402

import bot_core as core  # noqa: E402
from claude_client import ClaudeClient  # noqa: E402

log = logging.getLogger('chaosbot')
NO_PINGS = discord.AllowedMentions.none()
STATUS_CHOICES = [app_commands.Choice(name=core.STATUS_LABEL[s], value=s) for s in core.STATUSES]
LIST_CHOICES = [app_commands.Choice(name='Abertos', value='abertos'),
                app_commands.Choice(name='Todos', value='todos')] + STATUS_CHOICES


class PatchSession:
    """Notes waiting for Publicar / Editar / Cancelar. seen_shas: the commits of the changes file the notes were made
    from (marked as covered at Publicar; None: no file). auto: the automatic preview DM'd to the owner (its buttons
    survive a restart: meta 'auto_pending', message_id)."""

    def __init__(self, version, date, pt, en, bug_ids, seen_shas=None, newest_sha='', summary='', auto=False):
        self.version, self.date, self.pt, self.en, self.bug_ids = version, date, pt, en, bug_ids
        self.seen_shas, self.newest_sha, self.summary, self.auto = seen_shas, newest_sha, summary, auto
        self.message_id = None

    def to_dict(self):
        return {'version': self.version, 'date': self.date, 'pt': self.pt, 'en': self.en, 'bug_ids': self.bug_ids,
                'seen_shas': self.seen_shas, 'newest_sha': self.newest_sha, 'summary': self.summary}

    @classmethod
    def from_dict(cls, d):
        return cls(d['version'], d['date'], d['pt'], d['en'], d['bug_ids'], d['seen_shas'], d['newest_sha'],
                   d['summary'], auto=True)


def embeds_of(session):
    return [discord.Embed.from_dict(e) for e in core.render_embeds(session.pt, session.version, session.date)]


def preview_text(session, channel_id):
    n = len(core.render_embeds(session.pt, session.version, session.date))
    s = 'Prévia do patch. Vai para <#%d>. Bugs corrigidos incluídos: %d.' % (channel_id, len(session.bug_ids))
    if session.summary:
        s += ' ' + session.summary
    if n > 1:
        s += ' A prévia mostra a primeira de %d mensagens.' % n
    return s


class EditModal(discord.ui.Modal):
    """Edit or write the notes by hand: one bullet per line, 'Lead :: text' gives a bullet a lead."""

    def __init__(self, bot, session, view, title='Editar patch notes'):
        super().__init__(title=title, timeout=900)
        self.bot, self.session, self.view_ = bot, session, view
        cur = core.notes_to_fields(session.pt) if session.pt else {s: '' for s in core.SECTIONS}
        self.ftitle = discord.ui.TextInput(label='Título', default=(session.pt or {}).get('title', ''),
                                           max_length=100, required=True)
        self.add_item(self.ftitle)
        self.fields = {}
        for s, label in (('new', 'Novidades (uma por linha)'), ('changes', 'Mudanças (uma por linha)'),
                         ('fixes', 'Correções (uma por linha)'), ('balance', 'Balanceamento (uma por linha)')):
            ti = discord.ui.TextInput(label=label, style=discord.TextStyle.paragraph, required=False,
                                      max_length=4000, default=cur[s] or None,
                                      placeholder='Destaque :: texto   (ou só o texto)')
            self.fields[s] = ti
            self.add_item(ti)

    async def on_submit(self, interaction):
        try:
            notes = core.parse_hand_written(self.ftitle.value, {s: t.value for s, t in self.fields.items()})
        except core.BotError as e:
            await interaction.response.send_message('Não deu: %s.' % e, ephemeral=True)
            return
        notes['intro'] = (self.session.pt or {}).get('intro', '')
        self.session.pt = notes
        self.session.en = None  # the English twin is made again at Publicar
        if self.session.auto:
            self.bot.save_auto_pending(self.session)
        await interaction.response.edit_message(content=preview_text(self.session, self.bot.cfg.patch_channel_id),
                                                embeds=embeds_of(self.session)[:1], view=self.view_)


class PatchView(discord.ui.View):
    """persistent: the automatic preview; no timeout and fixed custom ids, so bot.add_view() after a restart binds
    the buttons of the stored message again."""

    def __init__(self, bot, session, persistent=False):
        super().__init__(timeout=None if persistent else 900)
        self.bot, self.session = bot, session
        if persistent:
            for item in self.children:
                item.custom_id = 'chaospatch:auto:' + {'Publicar': 'publish', 'Editar': 'edit'}.get(item.label, 'cancel')

    async def interaction_check(self, interaction):
        return await self.bot.guard(interaction)

    @discord.ui.button(label='Publicar', style=discord.ButtonStyle.success)
    async def publish(self, interaction, button):
        await interaction.response.defer()
        if self.session.auto and not self.bot.auto_pending_is(self.session.message_id):
            self.stop()
            await interaction.edit_original_response(content='Esta prévia não vale mais: outro patch saiu depois '
                                                     'dela. Use /patch gerar.', embeds=[], view=None)
            return
        try:
            msg = await self.bot.publish(self.session)
        except Exception as e:
            log.error('publish failed: %s', type(e).__name__)
            await interaction.followup.send('Não consegui publicar (%s). Nada foi marcado como publicado.'
                                            % type(e).__name__, ephemeral=True)
            return
        self.stop()
        await interaction.edit_original_response(content=msg, embeds=[], view=None)

    @discord.ui.button(label='Editar', style=discord.ButtonStyle.secondary)
    async def edit(self, interaction, button):
        await interaction.response.send_modal(EditModal(self.bot, self.session, self))

    @discord.ui.button(label='Cancelar', style=discord.ButtonStyle.danger)
    async def cancel(self, interaction, button):
        self.stop()
        if self.session.auto:
            self.bot.clear_auto_pending()
        await interaction.response.edit_message(content='Cancelado. Nada foi publicado.', embeds=[], view=None)


class WriteModal(EditModal):
    """/patch escrever: the same fields, empty."""

    def __init__(self, bot, version):
        export = core.load_changes(bot.cfg.changes_path)
        # a hand-written patch also covers the game's changes up to now (the next /patch gerar starts after them)
        session = PatchSession(version, core.note_date(bot.now_local()), None, None, [],
                               [c['sha'] for c in export['commits']] if export else None,
                               export['head'] if export else '')
        super().__init__(bot, session, None, title='Escrever patch notes')

    async def on_submit(self, interaction):
        try:
            self.session.pt = core.parse_hand_written(self.ftitle.value, {s: t.value for s, t in self.fields.items()})
        except core.BotError as e:
            await interaction.response.send_message('Não deu: %s.' % e, ephemeral=True)
            return
        view = PatchView(self.bot, self.session)
        await interaction.response.send_message(preview_text(self.session, self.bot.cfg.patch_channel_id),
                                                embeds=embeds_of(self.session)[:1], view=view, ephemeral=True)


class BugBot(discord.Client):
    def __init__(self, cfg, store, claude):
        intents = discord.Intents.default()
        intents.message_content = True  # needs "Message Content Intent" on in the Developer Portal (README)
        super().__init__(intents=intents, allowed_mentions=NO_PINGS)
        self.cfg, self.store, self.claude = cfg, store, claude
        self.tree = app_commands.CommandTree(self)
        self.lock = asyncio.Lock()
        self.limiter = core.RateLimiter(cfg.per_user_hour)
        self.last_fail_dm = 0.0
        self.channels_checked = False
        self.ignored_seen = {}
        self.tz = ZoneInfo(core.TZ_NAME)

    def now_local(self):
        return datetime.datetime.now(self.tz)

    # ---- start
    async def setup_hook(self):
        register_commands(self)
        if self.cfg.guild_id:
            g = discord.Object(id=self.cfg.guild_id)
            self.tree.copy_global_to(guild=g)
            try:
                await self.tree.sync(guild=g)
            except discord.Forbidden:
                # 50001 Missing Access (live 2026-10-31): the bot is not in that server, was invited without the
                # applications.commands scope, or DISCORD_GUILD_ID is not a server id. The bot keeps running (the bug
                # channel works without the slash commands) and says how to fix it.
                log.error('slash commands not registered in server %s: Missing Access. Invite the bot with the link '
                          'of README.md (scope bot applications.commands) and check DISCORD_GUILD_ID '
                          '(right click on the server name > Copy Server ID), then discord-bot restart',
                          self.cfg.guild_id)
        else:
            await self.tree.sync()
        self.restore_auto_pending()
        self.loop.create_task(self.daily_loop())
        self.loop.create_task(self.auto_loop())
        self.loop.create_task(self.outbox_loop())

    async def on_ready(self):
        log.info('ready as bot id %s', self.user.id if self.user else '?')
        if not self.channels_checked:
            self.channels_checked = True
            try:
                await self.check_channels()
            except Exception as e:
                log.error('channel check failed: %s', type(e).__name__)
            try:
                await self.catch_up()
            except Exception as e:
                log.error('catch-up failed: %s', type(e).__name__)

    async def check_channels(self):
        """At start: can the bot see the bugs and patch channels, with the permissions it needs? Logs one line per
        channel and DMs the owner when something is wrong (owner 2026-11-03: the bot read nothing, no hint why)."""
        results = []
        for label, role, cid in (('Canal de bugs', 'bugs', self.cfg.bugs_channel_id),
                                 ('Canal de patch notes', 'patch', self.cfg.patch_channel_id)):
            if not cid:
                results.append((label, cid, 'not-set'))
                log.error('%s channel: not set', role)
                continue
            try:
                ch = self.get_channel(cid) or await self.fetch_channel(cid)
            except discord.HTTPException as e:
                results.append((label, cid, 'missing'))
                log.error('%s channel ...%s: not reachable (%s)', role, str(cid)[-4:], type(e).__name__)
                continue
            guild = getattr(ch, 'guild', None)
            me = guild.me if guild else None
            if me is None:
                results.append((label, cid, 'missing'))
                log.error('%s channel ...%s: not a server channel', role, str(cid)[-4:])
                continue
            perms = ch.permissions_for(me)
            granted = {n for n, v in perms if v}
            forum = isinstance(ch, discord.ForumChannel)
            missing = core.missing_permissions(granted, role, forum)
            results.append((label, cid, missing or None))
            log.info('%s channel ...%s: %s%s', role, str(cid)[-4:], 'forum' if forum else 'text',
                     ', missing: ' + ', '.join(missing) if missing else ', ok')
        text = core.channel_check_text(results)
        if text:
            await self.dm_owner(text)

    # ---- who may use the commands
    async def guard(self, interaction):
        roles = [r.id for r in getattr(interaction.user, 'roles', [])]
        if core.is_authorized(interaction.user.id, roles, self.cfg.owner_id, self.cfg.admin_role_id):
            return True
        text = 'Só o dono ou a administração pode usar isso.'
        if interaction.response.is_done():
            await interaction.followup.send(text, ephemeral=True)
        else:
            await interaction.response.send_message(text, ephemeral=True)
        return False

    # ---- the owner
    async def dm_owner(self, text):
        try:
            user = await self.fetch_user(self.cfg.owner_id)
            await user.send(text, allowed_mentions=NO_PINGS)
            return True
        except discord.HTTPException as e:
            log.error('could not DM the owner: %s', type(e).__name__)
            return False

    async def daily_loop(self):
        await self.wait_until_ready()
        while not self.is_closed():
            try:
                now = self.now_local()
                if core.daily_due(now, self.store.meta_get('daily_last'), self.cfg.daily_hour):
                    if await self.dm_owner(core.build_daily_summary(self.store, now.timestamp())):
                        self.store.meta_set('daily_last', now.strftime('%Y-%m-%d'))
                        log.info('daily summary sent')
            except Exception as e:
                log.error('daily loop: %s', type(e).__name__)
            await asyncio.sleep(60)

    async def outbox_loop(self):
        """O398: files chaos-ctl.sh drops into DATA/outbox (the season balance report) go to the owner as DMs, then
        are deleted. A file that cannot be sent stays and is tried again a minute later."""
        await self.wait_until_ready()
        while not self.is_closed():
            try:
                for path in core.outbox_files(self.cfg.outbox_dir):
                    text = core.read_outbox(path)
                    ok = True
                    for part in core.split_message(text):
                        if not await self.dm_owner(part):
                            ok = False
                            break
                    if not ok:
                        break
                    os.unlink(path)
                    log.info('outbox: %s sent to the owner', os.path.basename(path))
            except Exception as e:
                log.error('outbox: %s', type(e).__name__)
            await asyncio.sleep(60)

    # ---- the bugs channel
    async def catch_up(self):
        """At start: read what was posted in the bugs channel while the bot was off (at most CATCHUP_HOURS back,
        CATCHUP_LIMIT messages per channel or forum post). Messages answered before are skipped."""
        cid = self.cfg.bugs_channel_id
        if not cid:
            return
        ch = self.get_channel(cid) or await self.fetch_channel(cid)
        after = core.catchup_after(self.store.meta_get(core.LAST_SEEN_KEY, 0), time.time())
        sources = []
        if isinstance(ch, discord.ForumChannel):
            threads = list(ch.threads)
            try:
                threads += [th async for th in ch.archived_threads(limit=50)]
            except discord.HTTPException as e:
                log.info('catch-up: archived posts not readable (%s)', type(e).__name__)
            seen = set()
            for th in threads:
                if th.id not in seen and (th.last_message_id or th.id) > after:
                    seen.add(th.id)
                    sources.append(th)
        else:
            sources.append(ch)
        done = 0
        for src in sources:
            async for m in src.history(after=discord.Object(id=after), oldest_first=True, limit=core.CATCHUP_LIMIT):
                if m.author.bot or core.already_handled(self.store, m.id):
                    continue
                await self.handle_report(m)
                done += 1
        log.info('catch-up: %d message(s) read from the bugs channel since id %s', done, after)

    async def on_message(self, m):
        if m.author.bot:
            return
        thread = m.channel if isinstance(m.channel, discord.Thread) else None
        parent = thread.parent_id if thread else None
        if not core.in_bugs_channel(m.channel.id, parent, self.cfg.bugs_channel_id):
            # one line per channel an hour, ids only: shows a wrong DISCORD_BUGS_CHANNEL_ID (owner 2026-11-03)
            key = parent or m.channel.id
            if time.time() - self.ignored_seen.get(key, 0) > 3600:
                self.ignored_seen[key] = time.time()
                log.info('message in channel %s%s ignored: the bugs channel is %s', m.channel.id,
                         ' (thread of %s)' % parent if parent else '', self.cfg.bugs_channel_id or 'not set')
            return
        await self.handle_report(m)

    async def handle_report(self, m):
        """One message of the bugs channel (live or read back at start)."""
        thread = m.channel if isinstance(m.channel, discord.Thread) else None
        core.note_seen(self.store, m.id)
        # a forum post: the starter message has the thread's id; its title goes in front of the text
        text = core.report_text(m.content, thread.name if thread else None, bool(thread) and m.id == thread.id)
        idx = core.pick_images([(a.filename, a.content_type, a.size) for a in m.attachments])
        if len(text.strip()) < 6 and not idx:
            return
        if not self.limiter.allow(m.author.id, time.time()):
            log.info('message %s: author over the hourly limit, skipped', m.id)
            return
        async with self.lock:  # one at a time, so two reports of one bug in a row are seen as duplicates
            images = []
            try:
                for i in idx:
                    a = m.attachments[i]
                    images.append((core.image_media_type(a.filename, a.content_type), await a.read()))
                cls = await self.claude.classify(text, images, self.store.list('abertos'))
            except Exception as e:
                log.error('message %s: classify failed: %s', m.id, type(e).__name__)
                await self.warn_failure(type(e).__name__)
                return
            result = core.handle_classification(self.store, cls, m.id, m.author.id, m.jump_url)
        log.info('message %s: kind=%s action=%s bug=%s', m.id, cls['kind'], result['action'], result.get('bug_id', '-'))
        emoji = {'new': '\U0001F41E', 'duplicate': '\U0001F501'}.get(result['action'])
        if not emoji:
            return
        try:
            await m.add_reaction(emoji)
            await m.reply(core.reply_text(result, m.author.mention), mention_author=False,
                          allowed_mentions=discord.AllowedMentions(users=[m.author]))
        except discord.HTTPException as e:
            log.error('message %s: could not react or reply: %s', m.id, type(e).__name__)
        if result['notify_owner']:
            await self.dm_owner(core.owner_alert(result['bug'], m.jump_url))

    async def warn_failure(self, kind):
        if time.time() - self.last_fail_dm > 3600:
            self.last_fail_dm = time.time()
            await self.dm_owner('Falha ao classificar uma mensagem do canal de bugs (%s). Veja os logs: '
                                'chaos-ctl discord-bot logs. Vou avisar de novo só daqui a uma hora.' % kind)

    # ---- patch notes
    async def publish(self, s):
        ch = self.get_channel(self.cfg.patch_channel_id) or await self.fetch_channel(self.cfg.patch_channel_id)
        for e in core.render_embeds(s.pt, s.version, s.date):
            await ch.send(embed=discord.Embed.from_dict(e), allowed_mentions=NO_PINGS)
        note = ''
        nid = ''
        try:
            if s.en is None:
                s.en = await self.claude.translate_patch(s.pt)
            nid = core.write_site_files(self.cfg.patchnotes_dir, s.date, s.pt, s.en)
            note = (' Arquivos do site: %s.md e %s.pt-br.md (o jogo recebe em até 5 minutos; na hora: Levar patch '
                    'notes ao jogo).' % (nid, nid))
        except Exception as e:
            log.error('site files not written: %s', type(e).__name__)
            note = ' Os arquivos do site NÃO foram gravados (%s).' % type(e).__name__
        self.store.mark_patched(s.bug_ids, s.version or nid or s.date)
        self.store.record_patch(s.version or '', nid, s.bug_ids)
        if s.seen_shas is not None:
            self.store.mark_changes_seen(s.seen_shas, s.newest_sha)
        if s.auto or s.seen_shas is not None:
            self.clear_auto_pending()  # a pending automatic preview is out of date now: its Publicar refuses
        return 'Publicado em <#%d>.%s' % (self.cfg.patch_channel_id, note)

    # ---- the game's changes and the automatic patch (O385)
    def changes_for_patch(self):
        """(export, changes, since, block, used, left_out) for the next patch."""
        export = core.load_changes(self.cfg.changes_path)
        changes, since = core.select_changes(export, self.store.changes_seen(), self.store.patch_last_at(), time.time())
        block, used, left = core.changes_block(changes)
        return export, changes, since, block, used, left

    def session_from(self, version, notes, fixed, export, since, used, left, auto=False):
        return PatchSession(version, core.note_date(self.now_local()), notes['pt'], notes['en'],
                            [b['id'] for b in fixed], [c['sha'] for c in export['commits']] if export else None,
                            export['head'] if export else '', core.changes_summary(used, left, since, export, self.tz),
                            auto=auto)

    def save_auto_pending(self, session):
        self.store.meta_set('auto_pending', core.pending_to_json(session.to_dict(), session.message_id))

    def clear_auto_pending(self):
        self.store.meta_set('auto_pending', '')

    def auto_pending_is(self, message_id):
        return core.pending_message_id(self.store.meta_get('auto_pending')) == message_id

    def restore_auto_pending(self):
        """At start: the buttons of a stored automatic preview work again."""
        raw = self.store.meta_get('auto_pending')
        if not raw:
            return
        data, mid = core.pending_from_json(raw)
        if not data:
            self.clear_auto_pending()
            return
        s = PatchSession.from_dict(data)
        s.message_id = mid
        self.add_view(PatchView(self, s, persistent=True), message_id=mid)
        log.info('automatic preview %s: buttons restored', mid)

    async def auto_loop(self):
        await self.wait_until_ready()
        while not self.is_closed():
            try:
                await self.auto_patch_tick()
            except Exception as e:
                log.error('auto patch: %s', type(e).__name__)
            await asyncio.sleep(300)

    async def auto_patch_tick(self):
        export = core.load_changes(self.cfg.changes_path)
        seen, last_at = self.store.changes_seen(), self.store.patch_last_at()
        plan = core.auto_patch_plan(self.cfg.patch_auto, export, self.store.meta_get('auto_head'), seen, last_at,
                                    time.time())
        if plan['action'] == 'none':
            return
        self.store.meta_set('auto_head', plan['head'])  # one attempt per head: never twice for the same changes
        if plan['action'] == 'skip':
            log.info('auto patch: head %s has no new player-facing change', plan['head'][:12])
            return
        block, used, left = core.changes_block(plan['changes'])
        fixed = self.store.fixed_unpatched()
        version = core.auto_version(self.now_local())
        try:
            notes = await self.claude.write_patch(fixed, version, '', block)
        except Exception as e:
            log.error('auto patch: notes not written: %s', type(e).__name__)
            await self.dm_owner('Não consegui escrever o patch automático (%s). Use /patch gerar.' % type(e).__name__)
            return
        if notes is None:
            log.info('auto patch: head %s, %d changes, nothing players notice', plan['head'][:12], used)
            self.store.mark_changes_seen([c['sha'] for c in export['commits']], export['head'])
            return
        s = self.session_from(version, notes, fixed, export, plan['since'], used, left, auto=True)
        if plan['publish']:
            try:
                msg = await self.publish(s)
            except Exception as e:
                log.error('auto patch: publish failed: %s', type(e).__name__)
                await self.dm_owner('O patch automático não foi publicado (%s). Use /patch gerar.' % type(e).__name__)
                return
            log.info('auto patch: published %s (%d changes)', version, used)
            await self.dm_owner('Patch automático %s depois da atualização do servidor. %s' % (version, msg))
            return
        await self.retire_auto_preview()
        user = await self.fetch_user(self.cfg.owner_id)
        view = PatchView(self, s, persistent=True)
        text = 'Patch automático depois da atualização do servidor. ' + preview_text(s, self.cfg.patch_channel_id)
        m = await user.send(text, embeds=embeds_of(s)[:1], view=view, allowed_mentions=NO_PINGS)
        s.message_id = m.id
        self.save_auto_pending(s)
        log.info('auto patch: preview %s sent to the owner (%d changes)', version, used)

    async def retire_auto_preview(self):
        """A newer automatic preview replaces the old one: its message loses the buttons."""
        raw = self.store.meta_get('auto_pending')
        if not raw:
            return
        self.clear_auto_pending()
        mid = core.pending_message_id(raw)
        if mid is None:
            return
        try:
            user = await self.fetch_user(self.cfg.owner_id)
            ch = user.dm_channel or await user.create_dm()
            old = await ch.fetch_message(mid)
            await old.edit(content='Substituída por uma prévia mais nova (abaixo).', embeds=[], view=None)
        except Exception as e:
            log.info('old automatic preview not edited: %s', type(e).__name__)


def register_commands(bot):
    bugs = app_commands.Group(name='bugs', description='Bugs relatados pelos jogadores', guild_only=True)
    patch = app_commands.Group(name='patch', description='Patch notes', guild_only=True)
    store, claude = bot.store, bot.claude

    async def fail(interaction, e):
        text = str(e) if isinstance(e, core.BotError) else 'Erro (%s). Veja os logs.' % type(e).__name__
        if not isinstance(e, core.BotError):
            log.error('command failed: %s', type(e).__name__)
        if interaction.response.is_done():
            await interaction.followup.send(text, ephemeral=True)
        else:
            await interaction.response.send_message(text, ephemeral=True)

    @bugs.command(name='lista', description='Lista de bugs por gravidade e número de relatos')
    @app_commands.describe(status='Qual lista (padrão: abertos)')
    @app_commands.choices(status=LIST_CHOICES)
    async def lista(interaction: discord.Interaction, status: app_commands.Choice[str] = None):
        if not await bot.guard(interaction):
            return
        try:
            rows = store.list(status.value if status else 'abertos')
            await interaction.response.send_message(core.format_bug_list(rows), ephemeral=True)
        except Exception as e:
            await fail(interaction, e)

    @bugs.command(name='ver', description='Detalhes de um bug')
    @app_commands.describe(id='Número do bug')
    async def ver(interaction: discord.Interaction, id: int):
        if not await bot.guard(interaction):
            return
        try:
            emb = discord.Embed(description=core.format_bug_detail(store, id), color=core.EMBED_COLOR)
            await interaction.response.send_message(embed=emb, ephemeral=True)
        except Exception as e:
            await fail(interaction, e)

    @bugs.command(name='status', description='Muda o status de um bug')
    @app_commands.describe(id='Número do bug', novo_status='Novo status', duplicado_de='Número do bug original (para duplicado)',
                           nota='Nota curta (aparece em /bugs ver)')
    @app_commands.choices(novo_status=STATUS_CHOICES)
    async def status(interaction: discord.Interaction, id: int, novo_status: app_commands.Choice[str],
                     duplicado_de: int = None, nota: str = None):
        if not await bot.guard(interaction):
            return
        try:
            b = store.set_status(id, novo_status.value, duplicado_de, nota)
            await interaction.response.send_message('Bug #%d agora está **%s**.' % (b['id'], core.STATUS_LABEL[b['status']]),
                                                    ephemeral=True)
        except Exception as e:
            await fail(interaction, e)

    @bugs.command(name='exportar', description='Baixa os bugs em Markdown')
    @app_commands.describe(incluir_fechados='Inclui corrigidos, duplicados e não-bugs')
    async def exportar(interaction: discord.Interaction, incluir_fechados: bool = False):
        if not await bot.guard(interaction):
            return
        try:
            data = core.export_markdown(store, incluir_fechados).encode('utf-8')
            await interaction.response.send_message('Exportado.', ephemeral=True,
                                                    file=discord.File(io.BytesIO(data), filename='bugs.md'))
        except Exception as e:
            await fail(interaction, e)

    @bugs.command(name='resumo', description='O Claude sugere prioridades e bugs com causa provável em comum')
    async def resumo(interaction: discord.Interaction):
        if not await bot.guard(interaction):
            return
        try:
            await interaction.response.defer(ephemeral=True)
            rows = store.list('abertos')
            if not rows:
                await interaction.followup.send('Nenhum bug aberto.', ephemeral=True)
                return
            await interaction.followup.send(await claude.priorities(rows), ephemeral=True)
        except Exception as e:
            await fail(interaction, e)

    @patch.command(name='gerar', description='Escreve patch notes a partir dos bugs corrigidos')
    @app_commands.describe(versao='Versão ou nome do patch (ex.: 0.9.3)', extras='Outras mudanças para incluir (texto livre)')
    async def gerar(interaction: discord.Interaction, versao: str, extras: str = ''):
        if not await bot.guard(interaction):
            return
        try:
            await interaction.response.defer(ephemeral=True)
            fixed = store.fixed_unpatched()
            export, changes, since, block, used, left = bot.changes_for_patch()
            if not fixed and not extras.strip() and not changes:
                await interaction.followup.send(core.nothing_new_text(since or store.patch_last_at(), bot.tz),
                                                ephemeral=True)
                return
            notes = await claude.write_patch(fixed, versao, extras, block)
            if notes is None:
                await interaction.followup.send('O Claude não achou nada que os jogadores notem nas %d mudanças do '
                                                'jogo. Passe o texto em extras se quiser um patch mesmo assim.' % used,
                                                ephemeral=True)
                return
            s = bot.session_from(core.clean_line(versao, 40), notes, fixed, export, since, used, left)
            await interaction.followup.send(preview_text(s, bot.cfg.patch_channel_id), embeds=embeds_of(s)[:1],
                                            view=PatchView(bot, s), ephemeral=True)
        except Exception as e:
            await fail(interaction, e)

    @patch.command(name='escrever', description='Escreve patch notes à mão, com prévia')
    @app_commands.describe(versao='Versão ou nome do patch (opcional)')
    async def escrever(interaction: discord.Interaction, versao: str = ''):
        if not await bot.guard(interaction):
            return
        await interaction.response.send_modal(WriteModal(bot, core.clean_line(versao, 40)))

    bot.tree.add_command(bugs)
    bot.tree.add_command(patch)


def main():
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(name)s: %(message)s')
    try:
        cfg = core.load_config(os.environ)
    except core.BotError as e:
        print('chaosbot: configuração incompleta: %s' % e, file=sys.stderr)
        return 2
    import anthropic
    store = core.Store(cfg.db_path)
    claude = ClaudeClient(anthropic.AsyncAnthropic(api_key=cfg.api_key), cfg.model, cfg.fallbacks)
    bot = BugBot(cfg, store, claude)
    log.info('starting; model %s, fallbacks %s', cfg.model, 'on' if cfg.fallbacks else 'off')
    bot.run(cfg.token, log_handler=None)
    return 0


if __name__ == '__main__':
    sys.exit(main())
