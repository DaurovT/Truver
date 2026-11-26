import sys,re
from html.parser import HTMLParser
KEEP=['border-top','border-bottom','border-left','border-right','transform-origin','padding-top','margin-bottom','flex-wrap','filter','text-decoration','z-index','animation','position','left','top','right','bottom','inset','width','height','min-width','max-width','min-height','display','flex-direction','flex','align-items','justify-content','gap','padding','margin','margin-top','margin-left','border-radius','background','border','box-shadow','font-size','font-weight','letter-spacing','line-height','color','opacity','transform','text-align','overflow','backdrop-filter','grid-template-columns','white-space','font-variant-numeric']
ABBR={'position':'pos','background':'bg','border-radius':'r','font-size':'fs','font-weight':'fw','letter-spacing':'ls','line-height':'lh','box-shadow':'sh','flex-direction':'dir','align-items':'ai','justify-content':'jc','padding':'pad','margin':'m','opacity':'op','transform':'tf'}
SKIP_STYLE={('font-variant-numeric','tabular-nums')}
class P(HTMLParser):
    def __init__(s): super().__init__(); s.d=0; s.out=[]; s.on=False; s.svgd=0; s.skip=0
    def handle_starttag(s,t,a):
        a=dict(a)
        if t=='x-dc': s.on=True; return
        if not s.on: return
        if t=='link': return
        if t in('helmet','style','script'): s.skip+=1; return
        if s.skip: return
        if t in ('br','img','input','path','circle','rect','line','polygon','polyline','ellipse','stop','feturbulence','fecolormatrix'):
            selfclose=True
        else: selfclose=False
        st=a.get('style','')
        parts=[]
        for kv in st.split(';'):
            if ':' not in kv: continue
            k,v=kv.split(':',1); k=k.strip(); v=v.strip()
            if k in KEEP and (k,v) not in SKIP_STYLE and not (k=='display' and v=='flex' and False):
                parts.append(f"{ABBR.get(k,k)}:{v}")
        extra=[]
        for k in ('d','cx','cy','r','x','y','x1','y1','x2','y2','width','height','rx','fill','stroke','stroke-width','stroke-opacity','stroke-dasharray','pathlength','opacity','transform','viewBox','points','pathLength','stroke-linecap','aria-label','placeholder','value'):
            if k in a and a[k] is not None:
                v=a[k]
                if k=='d' and len(v)>70: v=v[:70]+'…'
                extra.append(f"{k}={v}")
        line='  '*s.d+t+(' {'+'; '.join(parts)+'}' if parts else '')+(' ['+' '.join(extra)+']' if extra else '')
        if t=='svg' and s.svgd==0 and 'filter' in st: pass
        s.out.append(line)
        if not selfclose: s.d+=1
    def handle_endtag(s,t):
        if t=='x-dc': s.on=False; return
        if not s.on: return
        if t in('helmet','style','script'): s.skip-=1; return
        if s.skip: return
        if t in ('br','img','input','path','circle','rect','line','polygon','polyline','ellipse','stop','feturbulence','fecolormatrix'): return
        s.d-=1
    def handle_data(s,data):
        if s.on and not s.skip and data.strip(): s.out.append('  '*s.d+'"'+data.strip()+'"')
for f in sys.argv[1:]:
    p=P(); p.feed(open(f).read())
    lines=p.out
    # collapse runs of identical-shape lines (e.g. tick marks)
    res=[]; i=0
    while i<len(lines):
        j=i
        key=re.sub(r'[-\d.]+','#',lines[i])
        while j+1<len(lines) and re.sub(r'[-\d.]+','#',lines[j+1])==key: j+=1
        if j-i>=3: res.append(lines[i]); res.append(lines[i][:len(lines[i])-len(lines[i].lstrip())]+f"… ×{j-i} more like above (last: {lines[j].strip()[:120]})")
        else: res.extend(lines[i:j+1])
        i=j+1
    print('=====',f.split('/')[-1]); print('\n'.join(res))
