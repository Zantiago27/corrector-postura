import math, random, statistics as st
from one_euro_sim import OneEuro, EMA, pose_sentadilla, pose_jumping, rodilla, brazos

def ruido(pose, rnd, sd):
    return {k:(x+rnd.gauss(0,sd), y+rnd.gauss(0,sd)) for k,(x,y) in pose.items()}

def quieto(F, sd=3, fps=20, n=200):
    rnd=random.Random(1); vals=[]
    for i in range(n):
        vals.append(rodilla(F(ruido(pose_sentadilla(170),rnd,sd), i/fps)))
    return st.pstdev(vals[20:])

def retraso_rodilla(F, fps=20, periodo=2.0, sd=0):
    """Sentadilla sinusoidal 175<->90; retraso medio en grados durante la bajada."""
    rnd=random.Random(2); errs=[]; minv=999
    for i in range(int(fps*periodo*3)):
        t=i/fps; real=132.5+42.5*math.cos(2*math.pi*t/periodo)
        v=rodilla(F(ruido(pose_sentadilla(real),rnd,sd),t)); minv=min(minv,v)
        if i>fps*periodo: errs.append(abs(v-real))
    return st.mean(errs), minv

def retraso_jj(F, fps=20, periodo=1.0, sd=0):
    rnd=random.Random(3); errs=[]; maxv=0
    for i in range(int(fps*periodo*4)):
        t=i/fps; k=(1-math.cos(2*math.pi*t/periodo))/2; real=20+150*k
        v=brazos(F(ruido(pose_jumping(real,0.6+1.2*k),rnd,sd),t)); maxv=max(maxv,v)
        if i>fps*periodo: errs.append(abs(v-real))
    return st.mean(errs), maxv

for fps in (20, 12):
    print(f"\n######## {fps} FPS ########")
    for nom,mk in [("sin filtro",lambda: EMA(1.0)),("EMA 0.6",lambda: EMA(0.6)),("EMA 0.8",lambda: EMA(0.8)),
                   ("1€ (1.0, 6)",lambda: OneEuro(1.0,6)),("1€ (1.5,10)",lambda: OneEuro(1.5,10)),
                   ("1€ (0.8, 8)",lambda: OneEuro(0.8,8))]:
        q=quieto(mk(),fps=fps)
        rs,mn=retraso_rodilla(mk(),fps=fps,sd=3)
        rj,mx=retraso_jj(mk(),fps=fps,sd=3)
        print(f"{nom:12s} temblor quieto ±{q:4.2f}°  | sentadilla 2s: error {rs:4.1f}°, mín {mn:5.1f} (real 90)"
              f" | JJ 1s: error {rj:5.1f}°, máx {mx:5.1f} (real 170)")