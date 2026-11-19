"""Simulación del filtro One Euro sobre las poses sintéticas de los tests de Dart
(sentadilla, flexiones, jumping jacks) + máquina de estados del motor."""
import math, random

def alfa(fc, dt):
    tau = 1/(2*math.pi*fc); return 1/(1+tau/dt)

class OneEuro:
    def __init__(s, min_corte=1.0, beta=6.0, corte_d=1.0, reiniciar=0.4):
        s.p=dict(min_corte=min_corte,beta=beta,corte_d=corte_d); s.reiniciar=reiniciar
        s.prev={}; s.vel={}; s.t=None
    def __call__(s, pose, t):
        if s.t is not None and t-s.t > s.reiniciar: s.prev.clear(); s.vel.clear()
        dt = None if s.t is None else max(t-s.t, 1e-3); s.t=t
        xs=[p[0] for p in pose.values()]; ys=[p[1] for p in pose.values()]
        escala=max(max(xs)-min(xs), max(ys)-min(ys), 1)
        out={}
        for k,(x,y) in pose.items():
            if k not in s.prev or dt is None:
                out[k]=(x,y); s.vel[k]=(0,0); continue
            px,py=s.prev[k]; vx0,vy0=s.vel[k]
            ad=alfa(s.p['corte_d'],dt)
            vx=vx0+ad*((x-px)/dt-vx0); vy=vy0+ad*((y-py)/dt-vy0)
            s.vel[k]=(vx,vy)
            fc=s.p['min_corte']+s.p['beta']*math.hypot(vx,vy)/escala
            a=alfa(fc,dt); out[k]=(px+a*(x-px), py+a*(y-py))
        s.prev=dict(out); return out

class EMA:
    def __init__(s,a): s.a=a; s.prev={}; s.t=None
    def __call__(s,pose,t):
        out={}
        for k,(x,y) in pose.items():
            if k in s.prev:
                px,py=s.prev[k]; out[k]=(px+s.a*(x-px),py+s.a*(y-py))
            else: out[k]=(x,y)
        s.prev=dict(out); return out

def ang(a,b,c):
    v1=(a[0]-b[0],a[1]-b[1]); v2=(c[0]-b[0],c[1]-b[1])
    d=(v1[0]*v2[0]+v1[1]*v2[1])/(math.hypot(*v1)*math.hypot(*v2))
    return math.degrees(math.acos(max(-1,min(1,d))))

class Motor:
    """Conteo con histéresis + confirmación 2 frames; guarda min/max de medidas."""
    def __init__(s, metrica, extremo, reposo, menor=True, medidas={}, dur_min=0.5):
        s.m=metrica; s.ex=extremo; s.re=reposo; s.menor=menor; s.medidas=medidas; s.dur_min=dur_min
        s.fase='reposo'; s.c=dict(er=0,fr=0,ee=0,fe=0); s.reps=[]; s.ini=None; s.agg={}
    def frame(s,pose,t):
        v=s.m(pose)
        enRe = v>s.re if s.menor else v<s.re
        enEx = v<s.ex if s.menor else v>s.ex
        c=s.c; c['er']=c['er']+1 if enRe else 0; c['fr']=0 if enRe else c['fr']+1
        c['ee']=c['ee']+1 if enEx else 0; c['fe']=0 if enEx else c['fe']+1
        f=s.fase
        if f=='reposo' and c['fr']>=2: s.fase='ida'; s.ini=t; s.agg={}
        elif f=='ida':
            if c['ee']>=2: s.fase='extremo'
            elif c['er']>=2: s.fase='reposo'
        elif f=='extremo' and c['fe']>=2: s.fase='vuelta'
        elif f=='vuelta':
            if c['er']>=2:
                s.fase='reposo'; d=t-s.ini
                if d>=s.dur_min: s.reps.append(dict(dur=round(d,2),**{k:round(x,2) for k,x in s.agg.items()}))
            elif c['ee']>=2: s.fase='extremo'
        if s.fase!='reposo':
            for k,(fn,agg) in s.medidas.items():
                x=fn(pose); s.agg[k]=x if k not in s.agg else (min if agg=='min' else max)(s.agg[k],x)

# ---------- poses (copiadas de los tests) ----------
def pose_sentadilla(a,torso=10):
    t=math.radians(a); f=math.radians(torso); kx,ky=300,400
    hx,hy=kx+100*math.sin(t),ky+100*math.cos(t); sx,sy=hx+100*math.sin(f),hy-100*math.cos(f)
    return {'S':(sx,sy),'H':(hx,hy),'K':(kx,ky),'A':(kx,ky+100)}
def pose_flexion(codo):
    h=200*math.sin(math.radians(codo)/2); atras=math.sqrt(max(0,100*100-(h/2)**2))
    return {'S':(500,400-h),'E':(500-atras,400-h/2),'W':(500,400),'H':(300,400-h/2),'A':(100,400)}
def pose_jumping(bd,piernas,bi=None):
    bi=bd if bi is None else bi; r=math.radians
    return {'RS':(250,200),'LS':(350,200),'RH':(250,350),'LH':(350,350),
            'RW':(250-150*math.sin(r(bd)),200+150*math.cos(r(bd))),
            'LW':(350+150*math.sin(r(bi)),200+150*math.cos(r(bi))),
            'RA':(300-piernas*50,550),'LA':(300+piernas*50,550)}

def secuencia_sentadilla(hasta=90,torso=10):
    seq=[]; a=175.0
    while a>hasta: seq.append(pose_sentadilla(a,torso)); a-=5
    seq+= [pose_sentadilla(hasta,torso)]*4; a=hasta
    while a<175: seq.append(pose_sentadilla(a,torso)); a+=5
    return seq+[pose_sentadilla(175,torso)]*6
def secuencia_flexion(hasta=80,paso=5,pausa=4):
    seq=[]; a=170.0
    while a>hasta: seq.append(pose_flexion(a)); a-=paso
    seq+=[pose_flexion(hasta)]*pausa; a=hasta
    while a<170: seq.append(pose_flexion(a)); a+=paso
    return seq+[pose_flexion(170)]*6
def secuencia_jumping(brazos=170,piernas=1.8,brazoI=None):
    seq=[]
    def f(a):
        k=(a-20)/(brazos-20); bi=None if brazoI is None else 20+(brazoI-20)*k
        seq.append(pose_jumping(a,0.6+(piernas-0.6)*k,bi))
    a=20.0
    while a<brazos: f(a); a+=15
    for _ in range(4): f(brazos)
    a=brazos
    while a>20: f(a); a-=15
    for _ in range(4): f(20)
    return seq

rodilla=lambda p: ang(p['H'],p['K'],p['A'])
codo=lambda p: ang(p['S'],p['E'],p['W'])
brazos=lambda p:(ang(p['LH'],p['LS'],p['LW'])+ang(p['RH'],p['RS'],p['RW']))/2
piernas=lambda p: math.dist(p['LA'],p['RA'])/math.dist(p['LS'],p['RS'])
asim=lambda p: abs(ang(p['LH'],p['LS'],p['LW'])-ang(p['RH'],p['RS'],p['RW']))

def correr(filtro, seqs, motor, paso=0.05):
    t=0.0
    for seq in seqs:
        for p in seq: motor.frame(filtro(p,t),t); t+=paso
    return motor.reps

def caso(nombre, mk_filtro, mk_motor, seqs, paso=0.05):
    print(f"  {nombre:38s}", correr(mk_filtro(), seqs, mk_motor(), paso))

import sys
for etiqueta, F_sent, F_rap in [
    ("EMA actual (0.6 / 0.8 en JJ)", lambda: EMA(0.6), lambda: EMA(0.8)),
    ("One Euro (1.0, 6) / JJ (1.5, 10)", lambda: OneEuro(1.0,6), lambda: OneEuro(1.5,10)),
]:
    print("\n==", etiqueta)
    ms=lambda: Motor(rodilla,120,160,medidas={'min_rodilla':(rodilla,'min')})
    caso("sentadilla 90 (min<100 = correcta)", F_sent, ms, [secuencia_sentadilla(90)])
    caso("sentadilla 110 (100<min<120)", F_sent, ms, [secuencia_sentadilla(110)])
    caso("3 sentadillas", F_sent, ms, [secuencia_sentadilla()]*3)
    caso("amago 130 (0 reps)", F_sent, ms, [secuencia_sentadilla(130)])
    caso("sentadilla rápida paso 10ms (0 reps)", F_sent, ms, [secuencia_sentadilla()], paso=0.01)
    mf=lambda: Motor(codo,110,150,medidas={'min_codo':(codo,'min')},dur_min=0.3)
    caso("flexión 80 (min codo<95)", F_sent, mf, [secuencia_flexion()])
    caso("3 flexiones", F_sent, mf, [secuencia_flexion()]*3)
    caso("flexión 100 (95<min<110)", F_sent, mf, [secuencia_flexion(100)])
    caso("flexión rápida (dur<0.8)", F_sent, mf, [secuencia_flexion(paso=15,pausa=1)])
    mj=lambda: Motor(brazos,120,50,menor=False,dur_min=0.3,medidas={'max_brazos':(brazos,'max'),'max_piernas':(piernas,'max'),'max_asim':(asim,'max')})
    caso("JJ completo (brazos>=150, piernas>=1.3)", F_rap, mj, [secuencia_jumping()])
    caso("5 JJ (5 reps)", F_rap, mj, [secuencia_jumping()]*5)
    caso("JJ brazos 135 (120<max<150)", F_rap, mj, [secuencia_jumping(135)])
    caso("JJ piernas 1.0 (max<1.3)", F_rap, mj, [secuencia_jumping(piernas=1.0)])
    caso("JJ brazoI 110 (asim>30)", F_rap, mj, [secuencia_jumping(brazoI=110)])

# ruido del test "157/170" con One Euro
print("\n== ruido 157/170 alternado (sentadilla) ==")
for nom,F in [("EMA 0.6",EMA(0.6)),("One Euro",OneEuro(1.0,6))]:
    vals=[rodilla(F(pose_sentadilla(157 if i%2==0 else 170),i*0.05)) for i in range(40)]
    m=Motor(rodilla,120,160); [m.frame(pose_sentadilla(0),0)] if False else None
    print(f"  {nom}: últimos valores", [round(v,1) for v in vals[-4:]])