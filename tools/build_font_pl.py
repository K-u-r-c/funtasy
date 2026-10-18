"""Adds the Polish letters to the pixel font (#32): a ą ć ę ł ń ó ś ź ż (and capitals) are built
from the font's own base letters plus pixel accents (acute, ogonek, dot, stroke), 64 font units
per pixel. Writes assets/fonts/funtasy_pixel_pl.ttf next to the original. Needs fontTools.
"""
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.recordingPen import DecomposingRecordingPen
import sys
import os
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC=os.path.join(ROOT,'assets/fonts/funtasy_pixel.ttf')
DST=os.path.join(ROOT,'assets/fonts/funtasy_pixel_pl.ttf')
f=TTFont(SRC)
glyf=f['glyf']; cmap=f.getBestCmap(); gs=f.getGlyphSet()
P=64
def cells(gname):
    g=glyf[gname]
    coords=g.getCoordinates(glyf)[0]; ends=g.endPtsOfContours
    out=set(); start=0
    for e in ends:
        pts=coords[start:e+1]; start=e+1
        xs=[p[0] for p in pts]; ys=[p[1] for p in pts]
        for x in range(min(xs),max(xs),P):
            for y in range(min(ys),max(ys),P):
                out.add((x//P,y//P))
    return out
def make(base_ch, extra):
    base=cmap[ord(base_ch)]
    c=cells(base)
    top=max(y for x,y in c); xs=[x for x,y in c]
    left,right=min(xs),max(xs)
    row0=[x for x,y in c if y==0]
    add=set()
    mid=(left+right)//2
    if extra=='acute':
        add={(mid+1, top+2), (mid+2, top+3)}
    elif extra=='dot':
        add={(mid, top+2), (mid+1, top+2)}
    elif extra=='ogonek':
        r=max(row0)
        add={(r-1,-1),(r-1,-2),(r,-2)}
    elif extra=='stroke':
        h=max(y for x,y in c if x in (1,2))
        m=h//2
        add={(0,m),(3,m+1)}
    pen=TTGlyphPen(gs)
    for (x,y) in sorted(c|add):
        pen.moveTo((x*P,y*P)); pen.lineTo((x*P,(y+1)*P)); pen.lineTo(((x+1)*P,(y+1)*P)); pen.lineTo(((x+1)*P,y*P)); pen.closePath()
    return pen.glyph(), f['hmtx'][base]
spec={'ą':('a','ogonek'),'ć':('c','acute'),'ę':('e','ogonek'),'ł':('l','stroke'),'ń':('n','acute'),'ó':('o','acute'),
      'ś':('s','acute'),'ź':('z','acute'),'ż':('z','dot'),
      'Ą':('A','ogonek'),'Ć':('C','acute'),'Ę':('E','ogonek'),'Ł':('L','stroke'),'Ń':('N','acute'),'Ó':('O','acute'),
      'Ś':('S','acute'),'Ź':('Z','acute'),'Ż':('Z','dot')}
order=f.getGlyphOrder()
for ch,(b,kind) in spec.items():
    name='uni%04X'%ord(ch)
    g,mtx=make(b,kind)
    glyf[name]=g
    f['hmtx'][name]=mtx
    for t in f['cmap'].tables:
        if t.isUnicode(): t.cmap[ord(ch)]=name
f.setGlyphOrder(list(glyf.glyphOrder))
order=glyf.glyphOrder
for rec in f['name'].names:
    try:
        s=rec.toUnicode()
        if 'funtasy' in s.lower() or rec.nameID in (1,3,4,6):
            pass
    except Exception: pass
f.save(DST)
print('saved', len(order))
