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
    """Notes waiting for Publicar / Editar / Cancelar."""

    def __init__(self, version, date, pt, en, bug_ids):
        self.version, self.date, self.pt, self.en, self.bug_ids = version, date, pt, en, bug_ids


def embeds_of(session):
    return [discord.Embed.from_dict(e) for e in core.render_embeds(session.pt, session.version, session.date)]


def preview_text(session, channel_id):
    n = len(core.render_embeds(session.pt, session.version, session.date))
    s = 'Prévia do patch. Vai para <#%d>. Bugs corrigidos incluídos: %d.' % (channel_id, len(session.bug_ids))
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
        await interaction.response.edit_message(content=preview_text(self.session, self.bot.cfg.patch_channel_id),
                                                embeds=embeds_of(self.session)[:1], view=self.view_)


class PatchView(discord.ui.View):
    def __init__(self, bot, session):
        super().__init__(timeout=900)
        self.bot, self.session = bot, session

    async def interaction_check(self, interaction):
        return await self.bot.guard(interaction)

    @discord.ui.button(label='Publicar', style=discord.ButtonStyle.success)
    async def publish(self, interaction, button):
        await interaction.response.defer()
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
        await interaction.response.edit_message(content='Cancelado. Nada foi publicado.', embeds=[], view=None)


class WriteModal(EditModal):
    """/patch escrever: the same fields, empty."""

    def __init__(self, bot, version):
        session = PatchSession(version, core.note_date(bot.now_local()), None, None, [])
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
        self.tz = ZoneInfo(core.TZ_NAME)

    def now_local(self):
        return datetime.datetime.now(self.tz)

    # ---- start
    async def setup_hook(self):
        register_commands(self)
        if self.cfg.guild_id:
            g = discord.Object(id=self.cfg.guild_id)
            self.tree.copy_global_to(guild=g)
            await self.tree.sync(guild=g)
        else:
            await self.tree.sync()
        self.loop.create_task(self.daily_loop())

    async def on_ready(self):
        log.info('ready as bot id %s', self.user.id if self.user else '?')

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

    # ---- the bugs channel
    async def on_message(self, m):
        if m.author.bot or m.channel.id != self.cfg.bugs_channel_id:
            return
        text = m.content or ''
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
            note = ' Arquivos do site: %s.md e %s.pt-br.md (use "chaos-ctl discord-bot patchnotes" para levar ao jogo).' \
                % (nid, nid)
        except Exception as e:
            log.error('site files not written: %s', type(e).__name__)
            note = ' Os arquivos do site NÃO foram gravados (%s).' % type(e).__name__
        self.store.mark_patched(s.bug_ids, s.version or nid or s.date)
        self.store.record_patch(s.version or '', nid, s.bug_ids)
        return 'Publicado em <#%d>.%s' % (self.cfg.patch_channel_id, note)


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
            if not fixed and not extras.strip():
                await interaction.followup.send('Não há bugs corrigidos sem patch nem extras. Marque bugs como '
                                                '"corrigido" ou passe o texto em extras.', ephemeral=True)
                return
            notes = await claude.write_patch(fixed, versao, extras)
            s = PatchSession(core.clean_line(versao, 40), core.note_date(bot.now_local()), notes['pt'], notes['en'],
                             [b['id'] for b in fixed])
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
