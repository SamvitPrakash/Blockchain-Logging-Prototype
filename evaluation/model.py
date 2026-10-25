"""Per-role/per-resource descriptive topology models; grouped configuration holdout."""
import argparse,csv,collections,math
from pathlib import Path
import numpy as np
from common import aggregate,write
FIELDS=['cpu_percent','memory_mib','network_rx_mib_s','network_tx_mib_s','block_read_mib_s','block_write_mib_s']
p=argparse.ArgumentParser();p.add_argument('--csv',default='../metrics.csv');p.add_argument('--aggregated');p.add_argument('--out',default='results');a=p.parse_args()
if a.aggregated:
 with open(a.aggregated,newline='') as f:rows=list(csv.DictReader(f))
else:rows,_=aggregate(a.csv)
by=collections.defaultdict(list)
for r in rows:
 if int(r['samples'])>=3:by[r['role']].append(r)
models=[]
for role,rr in sorted(by.items()):
 for metric in FIELDS:
  # Fit interaction when supported, with ridge stabilization; evaluate on held-out experiments.
  usable=[r for r in rr if metric in r and math.isfinite(float(r[metric]))]
  if len(usable)<12:continue
  ids=sorted(set(int(r['experiment']) for r in usable));hold=set(ids[::5]);train=[r for r in usable if int(r['experiment']) not in hold];test=[r for r in usable if int(r['experiment']) in hold]
  def X(items):return np.array([[1,float(r['towers']),float(r['shared_ledgers']),float(r['towers'])*float(r['shared_ledgers'])] for r in items])
  if len(train)<5 or not test or np.linalg.matrix_rank(X(train))<4:continue
  x=X(train);y=np.array([float(r[metric]) for r in train]);beta=np.linalg.lstsq(x,y,rcond=None)[0];pred=X(test)@beta;truth=np.array([float(r[metric]) for r in test]);rmse=float(np.sqrt(np.mean((truth-pred)**2)))
  models.append(dict(role=role,metric=metric,b0=beta[0],b_towers=beta[1],b_ledgers=beta[2],b_interaction=beta[3],heldout_rmse=rmse,n_train=len(train),n_test=len(test),min_towers=min(int(r['towers']) for r in usable),max_towers=max(int(r['towers']) for r in usable),min_ledgers=min(int(r['shared_ledgers']) for r in usable),max_ledgers=max(int(r['shared_ledgers']) for r in usable)))
out=Path(a.out);out.mkdir(parents=True,exist_ok=True);write(models,out/'models.csv');print('Models:',len(models),'(descriptive; no extrapolation guarantee)')
