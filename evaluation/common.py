"""Bounded-memory, prototype-only streaming analysis utilities."""
import csv,re,collections,datetime,statistics
from pathlib import Path
METRICS=('cpu_percent','memory_bytes','network_rx_bytes','network_tx_bytes','block_read_bytes','block_write_bytes')
ROLES=('fabric-bootstrap','fabric-orderer','fabric-enroll','fabric-peer','fabric-ca','vnfm','vnf')
def role(name):
 s=name.lower()
 if s.startswith('dev-fabric-peer-') and '-logging_' in s:return 'logging'
 for r in ROLES:
  if s==r or s.startswith(r+'-') or s.startswith(r+'_'):return r
 return None
def stream(path):
 with open(path,newline='') as f:
  for row in csv.DictReader(f):
   r=role(row['container'])
   if r is None:continue
   try:
    e,t,l=(int(row[k]) for k in ('experiment','towers','shared_ledgers'))
    ts=datetime.datetime.fromisoformat(row['timestamp']).timestamp()
    v=tuple(float(row[k]) for k in METRICS)
   except (ValueError,KeyError,OverflowError):continue
   yield (e,t,l),ts,row['container'],r,v

def aggregate(path):
 # One time-series per container: only running sums, previous counters and compact configuration aggregates.
 acc=collections.defaultdict(lambda:collections.defaultdict(lambda:[0.,0.,0.,0.,0.,0.,0.,0.]))
 prev={}; seen=collections.defaultdict(set); issues=collections.Counter()
 for key,ts,name,r,v in stream(path):
  # Average CPU/memory across observed samples. Byte rates from positive deltas only.
  a=acc[key][r];a[0]+=1;a[1]+=v[0];a[2]+=v[1];seen[key].add(name)
  p=(key,name)
  if p in prev:
   oldts,old=prev[p];dt=ts-oldts
   if dt>0:
    for j in range(2,6):
     d=v[j]-old[j]
     if d>=0:a[j+1]+=d/dt
     else:issues['counter_resets']+=1
    a[7]+=1
  prev[p]=(ts,v)
 out=[]
 for (e,t,l),rr in sorted(acc.items()):
  for r,a in rr.items():
   out.append(dict(experiment=e,towers=t,shared_ledgers=l,role=r,samples=int(a[0]),cpu_percent=a[1]/a[0],memory_mib=a[2]/a[0]/1048576,network_rx_mib_s=a[3]/max(a[7],1)/1048576,network_tx_mib_s=a[4]/max(a[7],1)/1048576,block_read_mib_s=a[5]/max(a[7],1)/1048576,block_write_mib_s=a[6]/max(a[7],1)/1048576,rate_intervals=int(a[7]),containers=len([x for x in seen[(e,t,l)] if role(x)==r])))
 return out,issues

def write(rows,path):
 if not rows:return
 with open(path,'w',newline='') as f:
  w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
