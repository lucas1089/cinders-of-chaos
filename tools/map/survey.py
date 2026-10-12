"""Survey a whole OTBM map: overall size, area types, detail metrics, hunting areas, towns and houses.

    python3 -I survey.py MAP(.otbm|.npz) ITEMS.otb ITEMS.xml OUT.json [--dat Tibia.dat] [--spawn F-spawn.xml]
                         [--house F-house.xml] [--label NAME] [--blocks OUT_blocks.npz]

Writes one JSON with:
  overall   bounds (1st-99th percentile of open tiles), floors, tiles, items per tile, unknown ids
  areas     per area type (town, building, dungeon, cave, forest, grassland, dirt, desert, ice, swamp,
            lava, water, exotic): metrics from analyze.summarize() + the most used deco items
  hunting   spawns, monsters per spawn, radius, nearest-spawn distance, monsters per 100 walkable hunt
            tiles, corridor width (min of horizontal/vertical walkable run), dead-end share, loops per
            1000 tiles, room share and sizes, floors used
  towns     per town: temple, footprint, street width, plaza sizes, houses (size, footprint, floors,
            doors, roof cover), depots, deco per street tile
  floorchanges  counts of ladders / stairs / ramps / holes / rope spots / teleports
With --blocks, every analysed 16x16 block is saved (z, x, y, type, metrics) for picking references.
Deterministic: no randomness, fixed iteration order.
"""
import sys, os, re, json, argparse, collections
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import otbm
from itemdb import ItemDB
import analyze as an

CH = 256      # chunk size (tiles)
BS = 16       # block size


def parse_spawns(path):
    s = open(path, encoding='latin1').read()
    out = []
    for b in re.finditer(r'<spawn\b([^>]*)>(.*?)</spawn>', s, re.S):
        a = dict(re.findall(r'(\w+)="(-?\d+)"', b.group(1)))
        if not {'centerx', 'centery', 'centerz'} <= set(a):
            continue
        cx, cy, cz, r = int(a['centerx']), int(a['centery']), int(a['centerz']), int(a.get('radius', 1))
        mons = []
        for mm in re.finditer(r'<monster\b([^>]*)/?>', b.group(2)):
            ma = dict(re.findall(r'(\w+)="([^"]*)"', mm.group(1)))
            try:
                mons.append((cx + int(ma.get('x', 0)), cy + int(ma.get('y', 0)), cz, ma.get('name', '')))
            except ValueError:
                pass
        out.append(dict(c=(cx, cy, cz), r=r, mons=mons))
    return out


def parse_houses(path):
    s = open(path, encoding='latin1').read()
    hs = {}
    for b in re.finditer(r'<house\b([^>]*)/?>', s):
        a = dict(re.findall(r'(\w+)="([^"]*)"', b.group(1)))
        try:
            hs[int(a['houseid'])] = dict(town=int(a.get('townid', 0)), size=int(a.get('size', 0) or 0),
                                         entry=(int(a.get('entryx', 0)), int(a.get('entryy', 0)), int(a.get('entryz', 0))))
        except (KeyError, ValueError):
            pass
    return hs


def pct(a, q):
    return float(np.percentile(a, q)) if len(a) else None


def survey(m, db, spawns=None, houses=None, blocks_out=None):
    it = an.ItemTables(db)
    f = an.tile_features(m, it)
    n = len(f['x'])
    res = {}
    op = f['open']
    xs, ys = f['x'][op], f['y'][op]
    zc = np.bincount(f['z'], minlength=16)
    res['overall'] = dict(
        tiles=int(n), open_tiles=int(op.sum()), walkable_tiles=int(f['walk'].sum()), items=int(len(m.items)),
        items_per_tile=round(len(m.items) / max(n, 1), 3),
        bounds_p1_p99=[pct(xs, 1), pct(ys, 1), pct(xs, 99), pct(ys, 99)] if len(xs) else None,
        floors={int(z): int(c) for z, c in enumerate(zc) if c},
        floors_used=int((zc > 0).sum()), house_tiles=int(f['house'].sum()), pz_tiles=int(f['pz'].sum()),
        unknown_item_uses=int(f['nunk'].sum()), towns=len(m.towns),
        items_version=f"{m.header.get('items_major')}.{m.header.get('items_minor')}", otbm_version=m.header.get('version'))
    # ---- monsters (for hunting) indexed by chunk
    mon_by_chunk = collections.defaultdict(list)
    if spawns:
        for s in spawns:
            for (x, y, z, nm) in s['mons']:
                mon_by_chunk[(z, y // CH, x // CH)].append((x, y))
    # ---- chunks
    ck = (f['z'].astype(np.int64) << 40) | ((f['y'] // CH).astype(np.int64) << 20) | (f['x'] // CH).astype(np.int64)
    order = np.argsort(ck, kind='stable')
    cks = ck[order]
    bounds = np.flatnonzero(np.diff(cks)) + 1
    starts = np.concatenate([[0], bounds]); ends = np.concatenate([bounds, [len(cks)]])
    btype_rows = collections.defaultdict(list)
    blocks = []
    hunt = collections.Counter(); widths = []; room_sizes = []
    tile_type = np.full(n, 255, np.uint8)
    from scipy import ndimage
    for s0, e0 in zip(starts, ends):
        sel = order[s0:e0]
        k = int(cks[s0]); z = k >> 40; cy = (k >> 20) & 0xFFFFF; cx = k & 0xFFFFF
        x0, y0 = cx * CH, cy * CH
        D = an.to_dense(f, sel, x0, y0, CH, CH)
        if D['open'].sum() < 40:
            continue
        bt_grid = np.full((CH // BS, CH // BS), 255, np.uint8)
        for by in range(CH // BS):
            for bx in range(CH // BS):
                sl = (slice(by * BS, by * BS + BS), slice(bx * BS, bx * BS + BS))
                t = an.block_type(D, z, sl)
                if t is None:
                    continue
                r = an.block_metrics(D, sl)
                btype_rows[t].append(r)
                bt_grid[by, bx] = an.A[t]
                blocks.append((z, x0 + bx * BS, y0 + by * BS, an.A[t], r['open'], r['deco'], r['nature'], r['trans'],
                               r['bordered'], r['walled'], r['variants'], round(r['topshare'], 3), r['light'], r['heavy'], r['unknown']))
        # area type per tile (for top item lists)
        yi = f['y'][sel] - y0; xi = f['x'][sel] - x0
        tile_type[sel] = bt_grid[yi // BS, xi // BS]
        # hunting metrics
        mons = mon_by_chunk.get((z, cy, cx))
        if mons:
            mm = np.zeros((CH, CH), bool)
            for (x, y) in mons:
                mm[y - y0, x - x0] = True
            area = ndimage.maximum_filter(mm, size=13) & D['walk']
            if area.sum() == 0:
                continue
            wk = D['walk']
            wmin = np.minimum(an.run_lengths(wk, 0), an.run_lengths(wk, 1))
            widths.append(wmin[area])
            nbh = np.zeros((CH, CH), np.int32)
            nbh[:, 1:] += wk[:, :-1]; nbh[:, :-1] += wk[:, 1:]; nbh[1:, :] += wk[:-1, :]; nbh[:-1, :] += wk[1:, :]
            V = int(area.sum())
            E = int((area[:, 1:] & area[:, :-1]).sum() + (area[1:, :] & area[:-1, :]).sum())
            Q = int((area[1:, 1:] & area[:-1, 1:] & area[1:, :-1] & area[:-1, :-1]).sum())
            lab, C = ndimage.label(area)
            room = area & (wmin >= 5)
            rl, rn = ndimage.label(room)
            if rn:
                room_sizes.extend(np.bincount(rl.ravel())[1:].tolist())
            hunt['tiles'] += V; hunt['monsters'] += len(mons); hunt['dead_ends'] += int((area & (nbh == 1)).sum())
            hunt['loops'] += max(E - V + C - Q, 0); hunt['components'] += C
            hunt['room_tiles'] += int(room.sum()); hunt['corridor_tiles'] += int((area & (wmin <= 2)).sum())
            hunt['deco'] += int(D['nd'][area].sum()); hunt['lights'] += int(D['nl'][area].sum())
    res['areas'] = {t: an.summarize(rows) for t, rows in sorted(btype_rows.items(), key=lambda kv: -sum(r['open'] for r in kv[1]))}
    tot_open = sum(v['open_tiles'] for v in res['areas'].values()) or 1
    for t, v in res['areas'].items():
        v['share_of_open'] = round(v['open_tiles'] / tot_open, 3)
    res['overall_detail'] = an.summarize([r for rows in btype_rows.values() for r in rows])
    # ---- top deco items per area type
    owner = np.repeat(np.arange(n), m.tiles['cnt'].astype(np.int64))
    ids = m.items.astype(np.int64)
    tt = tile_type[owner]
    isd = it.is_deco[ids] | it.is_wall[ids] | it.is_border[ids] | it.is_ground[ids]
    for t, v in res['areas'].items():
        a = an.A[t]
        sel = (tt == a)
        c = np.bincount(ids[sel & it.is_deco[ids]], minlength=65536)
        top = np.argsort(-c)[:12]
        v['top_deco'] = [[int(i), db.name[i], int(c[i])] for i in top if c[i] > 0]
        cg = np.bincount(ids[sel & it.is_ground[ids]], minlength=65536)
        top = np.argsort(-cg)[:8]
        v['top_ground'] = [[int(i), db.name[i], int(cg[i])] for i in top if cg[i] > 0]
        cb = np.bincount(ids[sel & it.is_border[ids]], minlength=65536)
        v['distinct_border_ids'] = int((cb > 0).sum())
        cw = np.bincount(ids[sel & it.is_wall[ids]], minlength=65536)
        top = np.argsort(-cw)[:6]
        v['top_wall'] = [[int(i), db.name[i], int(cw[i])] for i in top if cw[i] > 0]
        v['distinct_deco_ids'] = int((c > 0).sum())
    # ---- floor changes
    fck = it.fckind[ids]
    names = {1: 'ladder', 2: 'stairs', 3: 'ramp', 4: 'hole', 5: 'rope spot', 6: 'teleport', 7: 'other'}
    res['floorchanges'] = {names[k]: int(v) for k, v in sorted(collections.Counter(fck[fck > 0].tolist()).items())}
    # ---- hunting
    if spawns:
        sp = spawns
        nm = np.array([len(s['mons']) for s in sp]); rr = np.array([s['r'] for s in sp])
        cz = collections.Counter(s['c'][2] for s in sp)
        mz = collections.Counter(mo[2] for s in sp for mo in s['mons'])
        # nearest other spawn centre on the same floor
        grid = collections.defaultdict(list)
        for i, s in enumerate(sp):
            grid[(s['c'][2], s['c'][0] // 32, s['c'][1] // 32)].append(i)
        nn = []
        for i, s in enumerate(sp):
            x, y, z = s['c']; best = 99
            for gx in (x // 32 - 1, x // 32, x // 32 + 1):
                for gy in (y // 32 - 1, y // 32, y // 32 + 1):
                    for j in grid.get((z, gx, gy), ()):
                        if j != i:
                            d = max(abs(sp[j]['c'][0] - x), abs(sp[j]['c'][1] - y))
                            best = min(best, d)
            if best < 99:
                nn.append(best)
        W = np.concatenate(widths) if widths else np.zeros(0)
        res['hunting'] = dict(
            spawns=len(sp), monsters=int(nm.sum()), monsters_per_spawn_mean=round(float(nm.mean()), 2),
            monsters_per_spawn_hist={int(k): int(v) for k, v in sorted(collections.Counter(nm.tolist()).items()) if k <= 12},
            radius_median=float(np.median(rr)), radius_hist={int(k): int(v) for k, v in sorted(collections.Counter(rr.tolist()).items()) if v >= len(sp) * 0.01},
            nearest_spawn_median=float(np.median(nn)) if nn else None, nearest_spawn_p25_p75=[pct(nn, 25), pct(nn, 75)],
            hunt_tiles=hunt['tiles'], monsters_per_100_hunt_tiles=round(100 * hunt['monsters'] / max(hunt['tiles'], 1), 2),
            corridor_width_median=pct(W, 50), corridor_width_p25_p75=[pct(W, 25), pct(W, 75)],
            width_hist={str(k): round(float((np.minimum(W, 9) == k).mean()), 3) for k in range(1, 10)} if len(W) else {},
            dead_end_per_1000=round(1000 * hunt['dead_ends'] / max(hunt['tiles'], 1), 2),
            loops_per_1000=round(1000 * hunt['loops'] / max(hunt['tiles'], 1), 2),
            room_share=round(hunt['room_tiles'] / max(hunt['tiles'], 1), 3),
            corridor_share=round(hunt['corridor_tiles'] / max(hunt['tiles'], 1), 3),
            room_size_median=pct([r for r in room_sizes if r >= 9], 50), room_size_p75=pct([r for r in room_sizes if r >= 9], 75),
            deco_per_hunt_tile=round(hunt['deco'] / max(hunt['tiles'], 1), 3),
            lights_per_100_hunt_tiles=round(100 * hunt['lights'] / max(hunt['tiles'], 1), 2),
            spawns_by_floor={int(k): int(v) for k, v in sorted(cz.items())},
            monsters_by_floor={int(k): int(v) for k, v in sorted(mz.items())})
    # ---- houses and towns
    res['houses'], res['towns'] = houses_and_towns(m, f, it, db, houses)
    if blocks_out:
        np.savez_compressed(blocks_out, blocks=np.array(blocks, dtype=np.float32),
                            cols=np.array('z x y type open deco nature trans bordered walled variants topshare light heavy unknown'.split()),
                            types=np.array(an.AREA_TYPES))
    return res


def houses_and_towns(m, f, it, db, hx):
    from scipy import ndimage
    hid = m.tiles['house']
    sel = np.flatnonzero(hid > 0)
    H = {}
    if len(sel):
        order = np.argsort(hid[sel], kind='stable'); s2 = sel[order]
        hs = hid[s2]
        b = np.flatnonzero(np.diff(hs)) + 1
        for a, e in zip(np.concatenate([[0], b]), np.concatenate([b, [len(hs)]])):
            idx = s2[a:e]
            z = f['z'][idx]; zs = np.unique(z)
            zmain = np.bincount(z).argmax()
            mm = idx[z == zmain]
            w = int(f['x'][mm].max() - f['x'][mm].min() + 1); h = int(f['y'][mm].max() - f['y'][mm].min() + 1)
            H[int(hs[a])] = dict(tiles=int(len(idx)), floors=int(len(zs)), z=int(zmain), w=w, h=h,
                                 cx=int(np.median(f['x'][mm])), cy=int(np.median(f['y'][mm])),
                                 fill=round(len(mm) / (w * h), 2), doors=int(f['ndoor'][idx].sum()),
                                 beds=0)
    hres = {}
    if H:
        sizes = np.array([h['tiles'] for h in H.values()]); fl = np.array([h['floors'] for h in H.values()])
        wh = np.array([(min(h['w'], h['h']), max(h['w'], h['h'])) for h in H.values()])
        hres = dict(count=len(H), tiles_median=float(np.median(sizes)), tiles_p25_p75=[pct(sizes, 25), pct(sizes, 75)],
                    tiles_max=int(sizes.max()), floors_hist={int(k): int(v) for k, v in sorted(collections.Counter(fl.tolist()).items())},
                    footprint_short_median=float(np.median(wh[:, 0])), footprint_long_median=float(np.median(wh[:, 1])),
                    footprint_p25=[pct(wh[:, 0], 25), pct(wh[:, 1], 25)], footprint_p75=[pct(wh[:, 0], 75), pct(wh[:, 1], 75)],
                    fill_median=float(np.median([h['fill'] for h in H.values()])),
                    door_tiles_median=float(np.median([h['doors'] for h in H.values()])))
    towns = []
    for tid, name, (tx, ty, tz) in m.towns:
        # town footprint: house tiles of this town (house xml) or within 120 tiles of the temple
        if hx:
            hh = [h for k, h in H.items() if k in hx and hx[k]['town'] == tid]
        else:
            hh = [h for h in H.values() if max(abs(h['cx'] - tx), abs(h['cy'] - ty)) <= 120]
        rec = dict(id=tid, temple=[tx, ty, tz], houses=len(hh))
        if len(hh) >= 3:
            cx = np.array([h['cx'] for h in hh]); cy = np.array([h['cy'] for h in hh])
            x0, x1 = int(np.percentile(cx, 3)) - 12, int(np.percentile(cx, 97)) + 12
            y0, y1 = int(np.percentile(cy, 3)) - 12, int(np.percentile(cy, 97)) + 12
            x0, x1 = min(x0, tx - 15), max(x1, tx + 15); y0, y1 = min(y0, ty - 15), max(y1, ty + 15)
        else:
            x0, x1, y0, y1 = tx - 40, tx + 40, ty - 40, ty + 40
        z = 7 if tz <= 7 else tz
        x0, y0 = max(x0, 0), max(y0, 0); x1, y1 = min(x1, 65535), min(y1, 65535)
        w, h = x1 - x0 + 1, y1 - y0 + 1
        idx = m.rect(x0, y0, x1, y1, z)
        if len(idx) < 100:
            towns.append(rec); continue
        D = an.to_dense(f, idx, x0, y0, w, h)
        openw = D['walk'] & ~D['house'] & ~D['fill']
        street = openw & (D['gcat'] == an.G['street'])
        paving = 'street'
        if street.sum() < 300:
            street = openw & np.isin(D['gcat'], [an.G['street'], an.G['floor']]); paving = 'street+floor'
        if street.sum() < 300:                    # unpaved town: measure every open tile
            street = openw; paving = 'any open'
        wmin = np.minimum(an.run_lengths(street, 0), an.run_lengths(street, 1))
        st = wmin[street]
        plaza = street & (wmin >= 7)
        lab, pn = ndimage.label(plaza)
        ps = np.sort(np.bincount(lab.ravel())[1:])[::-1] if pn else np.zeros(0)
        # depots: lockers / depot boxes
        dep = 0
        for i in idx:
            for sid in m.stack(i):
                nmn = db.name[int(sid)].lower()
                if 'locker' in nmn or nmn == 'depot chest':
                    dep += 1
        built = D['present'] & (D['house'] | (D['nw'] > 0))
        hsz = [x['tiles'] for x in hh]
        rec.update(footprint=[x0, y0, x1, y1, z], footprint_w=w, footprint_h=h, street_ground=paving,
                   street_tiles=int(street.sum()), street_width_median=pct(st, 50), street_width_p25_p75=[pct(st, 25), pct(st, 75)],
                   street_width_hist={str(k): round(float((np.minimum(st, 9) == k).mean()), 3) for k in range(1, 10)} if len(st) else {},
                   plazas=int((ps >= 40).sum()), plaza_largest=int(ps[0]) if len(ps) else 0,
                   plaza_sizes=[int(v) for v in ps[:5]],
                   deco_per_street_tile=round(float(D['nd'][street].sum() / max(street.sum(), 1)), 3),
                   empty_street_share=round(float((D['nd'][street] == 0).mean()) if street.sum() else 0, 3),
                   built_share=round(float(built.sum() / max(D['present'].sum(), 1)), 3),
                   lockers=dep, house_tiles_median=float(np.median(hsz)) if hsz else None,
                   house_floors=dict(collections.Counter(x['floors'] for x in hh)))
        # roofs: share of house tiles on z (<=7) that have a tile directly above
        if z <= 7 and z > 0:
            hsel = idx[f['house'][idx]]
            if len(hsel):
                above = sum(1 for i in hsel[:: max(1, len(hsel) // 400)] if m.find(f['x'][i], f['y'][i], z - 1) >= 0)
                rec['roof_cover'] = round(above / len(hsel[:: max(1, len(hsel) // 400)]), 2)
        towns.append(rec)
    return hres, towns


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('map'); ap.add_argument('otb'); ap.add_argument('xml'); ap.add_argument('out')
    ap.add_argument('--dat'); ap.add_argument('--spawn'); ap.add_argument('--house'); ap.add_argument('--label', default='')
    ap.add_argument('--blocks')
    a = ap.parse_args()
    m = otbm.load_map(a.map)
    db = ItemDB(a.otb, a.xml, a.dat)
    sp = parse_spawns(a.spawn) if a.spawn else None
    hx = parse_houses(a.house) if a.house else None
    res = survey(m, db, sp, hx, a.blocks)
    res = dict(label=a.label, header={k: v for k, v in m.header.items() if k in ('version', 'width', 'height', 'items_major', 'items_minor')}, **res)
    json.dump(res, open(a.out, 'w'), indent=1)
    print('wrote', a.out)


if __name__ == '__main__':
    main()
