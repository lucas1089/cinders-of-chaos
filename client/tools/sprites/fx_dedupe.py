import sys, json; sys.path.insert(0,'.')
from datspr import *; from fxlib import *
S=sys.argv[1].rstrip('/')+'/'  # dir holding things/Tibia.dat|spr and sprmatch/data/A_dat.dat|A.spr
A=Dat(S+'sprmatch/data/A_dat.dat'); As=Spr(S+'sprmatch/data/A.spr')
O=Dat(S+'things/Tibia.dat'); Os=Spr(S+'things/Tibia.spr')
res={}
for cat,la,lo,m in (('eff',A.effects,O.effects,False),('mis',A.missiles,O.missiles,True)):
    osig={}
    ohash={}
    for t in lo:
        sg=signature(t,Os,m); osig[t.id]=set(sg)
        for h in sg: ohash.setdefault(h,[]).append(t.id)
    # phash of mid frames
    oph=[(t.id,phash(frame_of(t,Os,t.phases//2,m))) for t in lo]
    for t in la:
        sg=signature(t,As,m)
        hits={}
        for h in sg:
            for i in ohash.get(h,[]): hits[i]=hits.get(i,0)+1
        best=max(hits.items(),key=lambda x:x[1]) if hits else (None,0)
        # blank?
        blank = all(not np.asarray(frame_of(t,As,p,m))[:,:,3].any() for p in range(t.phases))
        ph=phash(frame_of(t,As,t.phases//2,m))
        near=min(((hamming(ph,h),i) for i,h in oph if h and ph),default=(999,None))
        res[f'{cat}{t.id}']=dict(cat=cat,id=t.id,exact=best[0],exact_frames=best[1],nframes=t.phases,near=near[1],neardist=near[0],blank=blank)
json.dump(res,open('dedupe.json','w'),indent=0)
for cat in ('eff','mis'):
    r=[v for v in res.values() if v['cat']==cat]
    print(cat,len(r),'exact-dup(>=1 frame)',sum(1 for v in r if v['exact']),'blank',sum(v['blank'] for v in r),
      'new',sum(1 for v in r if not v['exact'] and not v['blank']),'new&notnear(<=12)',sum(1 for v in r if not v['exact'] and not v['blank'] and v['neardist']>12))
