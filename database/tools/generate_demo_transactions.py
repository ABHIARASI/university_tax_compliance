# Generates the INSERT for revenue_transaction in database/06_demo_data.sql.
# Fixed random seed -> the same data every run. Usage: python generate_demo_transactions.py
# (prints a count and writes tx.sql; paste its content into section 4 of 06_demo_data.sql)
import random, datetime as dt
random.seed(42)
out=[]
w=out.append
CLIENTS={'Nimbus Analytics Pvt Ltd':('29AAECN4410K1ZE','Karnataka'),
         'Orbit Motors Ltd':('27AAGCO7731P1ZR','Maharashtra'),
         'Coromandel Systems Ltd':('33AAJCS2290M1Z1','Tamil Nadu'),
         'Dhruva Pharma Ltd':('24AAHCD6614R1Z7','Gujarat')}
# source ids from seed
S=dict(tuition=1,admission=2,exam=3,suppl=4,hostel=5,ugc=6,dst=7,subsidy=8,donation=9,
       consult=10,research=11,mdp=12,online=13,audi=14,lab=15,affil=16)
UNIS=[('g','Greenfield University','Karnataka'),('r','Riverside University','Maharashtra'),('h','Hillcrest University','Tamil Nadu')]
def months():
    d=dt.date(2025,4,1)
    while d<=dt.date(2026,11,1):
        yield d
        d=(d.replace(day=28)+dt.timedelta(days=4)).replace(day=1)
def r(a,b,step=1000): return random.randrange(a,b+1,step)
rows=[]
def add(u,date,amt,mode,dept,src,payer=None,place=None,ref=None,ben=None,days=None,tds=None,desc=None):
    if date>dt.date(2026,11,18): return
    rows.append((u,date,amt,mode,dept,src,payer,place,ref,ben,days,tds,desc))
scale={'g':1.0,'r':0.8,'h':1.3}
for u,name,state in UNIS:
    k=scale[u]
    for m in months():
        mo=m.month
        day=lambda a,b: m.replace(day=random.randint(a,b))
        if mo in (7,1):   # semester tuition
            add(u,day(3,12),int(r(9000000,11000000,10000)*k),'Bank Transfer','acc',S['tuition'],'Semester fees - all students')
        if mo in (6,7):
            add(u,day(10,25),int(r(1500000,2000000,10000)*k),'UPI','acc',S['admission'],'Admission fees - new batch')
        if mo in (11,5):
            add(u,day(5,15),int(r(800000,1000000,10000)*k),'UPI','acc',S['exam'],'Exam fees - all students')
        if mo in (7,1):   # hostel semester: exempt
            ben=int(400*k); days_=150; per_day=random.randint(280,330)
            add(u,day(5,15),ben*days_*per_day,'Bank Transfer','hostel',S['hostel'],'Hostel fees - semester',ben=ben,days=days_)
        if mo==6 and m.year==2025 or mo==6 and m.year==2026:   # summer school: 5%
            add(u,day(1,8),60*30*random.choice([850,900,950]),'Bank Transfer','hostel',S['hostel'],'Summer school stay',ben=60,days=30)
        if mo in (4,10):
            add(u,day(10,25),int(r(2500000,3500000,50000)*k),'Bank Transfer','res',S['ugc'],'UGC - research grant')
        if mo==8:
            add(u,day(5,20),int(r(1000000,1500000,50000)*k),'Bank Transfer','res',S['dst'],'DST - project grant')
        if mo==9:
            add(u,day(5,20),int(r(500000,800000,50000)*k),'Bank Transfer','admin',S['subsidy'],'State government subsidy')
        if mo in (3,12):
            add(u,day(5,20),r(100000,300000,10000),'Cheque','admin',S['donation'],'Alumni association')
        # consultancy: 1-2 clients per month
        for _ in range(random.choice([1,1,2])):
            cl=random.choice(list(CLIENTS)); g,cst=CLIENTS[cl]
            add(u,day(2,26),r(40000,90000,5000),'Bank Transfer','eng',S['consult'],cl,None if cst==state else cst)
        if mo in (5,8,11,2):
            cl=random.choice(list(CLIENTS)); g,cst=CLIENTS[cl]
            add(u,day(2,26),r(200000,350000,10000),'Bank Transfer','res',S['research'],cl,None if cst==state else cst)
        if mo%2==0:
            add(u,day(2,26),r(150000,220000,5000),'UPI','mgmt',S['mdp'],'MDP participants (corporate)')
        add(u,day(2,26),r(30000,60000,1000),'UPI','mgmt',S['online'],'Online course learners')
        if mo%3==0:
            add(u,day(2,26),r(60000,120000,5000),'Bank Transfer','admin',S['audi'],random.choice(['Kala Events','Spark Productions','City Music Society']))
        if mo%4==1:
            add(u,day(2,26),r(40000,80000,5000),'Bank Transfer','eng',S['lab'],random.choice(['Nimbus Analytics Pvt Ltd','Coromandel Systems Ltd']))
        if u=='r' and mo in (8,9):
            add(u,day(2,26),r(900000,1200000,10000),'Bank Transfer','admin',S['affil'],'Affiliated colleges')
# deliberate anomalies
add('g',dt.date(2025,12,12),250000,'Cash','admin',S['audi'],'Starlight Wedding Planners',ref='EVT-1201',desc='Convocation hall rental - cash')
add('r',dt.date(2026,3,9),150000,'Cash','admin',S['audi'],'Vedika Events',ref='EVT-0309')
add('r',dt.date(2026,3,9),70000,'Cash','admin',S['audi'],'Vedika Events',ref='EVT-0309',desc='Second cash part, same day')
add('h',dt.date(2026,4,14),980000,'Bank Transfer','mgmt',S['mdp'],'Large corporate MDP batch')
add('r',dt.date(2026,5,6),75000,'Bank Transfer','eng',S['consult'],'Orbit Motors Ltd',None)
add('r',dt.date(2026,5,6),75000,'Bank Transfer','eng',S['consult'],'Orbit Motors Ltd',None,desc='Entered twice by mistake?')
add('g',dt.date(2026,6,16),300000,'Bank Transfer','res',S['research'],'Dhruva Pharma Ltd','Gujarat',tds=1500,desc='Client deducted less TDS')
rows.sort(key=lambda x:(x[1],x[0]))

def q(v): return 'NULL' if v is None else ("'"+str(v).replace("'","''")+"'")
DEPT={'acc':'Accounts','admin':'Administration','eng':'Engineering','mgmt':'Management','res':'Research Centre','hostel':'Hostel Office'}
w("INSERT INTO revenue_transaction\n    (Trans_Date, Amount, Mode, Dept_ID, Source_ID, Payer_Name, Payer_GSTIN, Place_Of_Supply,\n     Reference_No, Beneficiaries, Stay_Days, TDS_Deducted, Description, Created_By)\nVALUES")
vals=[]
for (u,date,amt,mode,dept,src,payer,place,ref,ben,days,tds,desc) in rows:
    gst=CLIENTS.get(payer,(None,))[0]
    vals.append(f"('{date}', {amt}, '{mode}', @{u}_{dept}, {src}, {q(payer)}, {q(gst)}, {q(place)}, {q(ref)}, {q(ben)}, {q(days)}, {q(tds)}, {q(desc)}, @{u}_user)")
w(",\n".join(vals)+";")
open('tx.sql','w').write("\n".join(out))
print(len(rows))