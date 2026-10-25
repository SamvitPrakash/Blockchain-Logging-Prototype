"""Predict prototype-only resource usage from previously fitted role models.

Example: python predict_topology.py --models results/models.csv --towers 50 --channels 10
Predictions beyond the experiment are extrapolations, not experimentally validated.
"""
import argparse, csv, math
from collections import defaultdict

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--models', default='results/models.csv')
p.add_argument('--towers', type=int, required=True)
p.add_argument('--channels', type=int, required=True)
p.add_argument('--role-counts', help='Optional comma-separated role=count overrides, e.g. logging=40,fabric-peer=50')
p.add_argument('--output', help='Optional output CSV')
a=p.parse_args()
if a.towers<2 or a.channels<1: p.error('towers must be >=2 and channels >=1')
if 2*a.channels>a.towers:p.error('Original experiment topology constraint requires 2*channels <= towers')
counts={'vnf':a.towers,'fabric-peer':a.towers,'logging':a.towers,'fabric-ca':1,'fabric-orderer':1,'vnfm':1}
if a.role_counts:
 for part in a.role_counts.split(','):
  role,count=part.split('=',1);counts[role.strip()]=int(count)
  if int(count)<0:p.error('role counts must be nonnegative')
with open(a.models,newline='') as f: models=list(csv.DictReader(f))
if not models:raise SystemExit('No fitted models found')
min_t=min(int(r['min_towers']) for r in models);max_t=max(int(r['max_towers']) for r in models)
min_l=min(int(r['min_ledgers']) for r in models);max_l=max(int(r['max_ledgers']) for r in models)
outside=a.towers<min_t or a.towers>max_t or a.channels<min_l or a.channels>max_l
print(f'Topology: T={a.towers} towers; L={a.channels} channels')
print(f'Fitted observation extent: T={min_t}..{max_t}, L={min_l}..{max_l} (not every pair was tested)')
print('STATUS:', 'EXTRAPOLATION — uncertain outside observed topologies' if outside else 'Within axis ranges — exact topology may still be untested')
print('Assumed instances:',counts)
print('NOTE: role models fit mean metric per role, NOT sum of all role instances.')
print('NOTE: negative fitted values are reported raw; nonnegative scenario estimates floor them at zero.')
result=[];totals=defaultdict(float)
for r in models:
 role=r['role'];metric=r['metric']
 b=[float(r[k]) for k in ('b0','b_towers','b_ledgers','b_interaction')]
 raw=b[0]+b[1]*a.towers+b[2]*a.channels+b[3]*a.towers*a.channels
 count=counts.get(role,0)
 scenario=max(0,raw)
 scaled=scenario*count
 totals[metric]+=scaled
 result.append({'role':role,'metric':metric,'equation':f'{b[0]:.9g} + ({b[1]:.9g})*T + ({b[2]:.9g})*L + ({b[3]:.9g})*T*L','predicted_mean_per_instance_raw':raw,'scenario_mean_per_instance_nonnegative':scenario,'assumed_instances':count,'scenario_total':scaled,'heldout_rmse':float(r['heldout_rmse']),'outside_observed_axes':outside})
print('\nEQUATIONS AND ESTIMATES:')
for d in result:
 print(f"{d['role']:16} {d['metric']:22} f(T,L)={d['equation']} | f({a.towers},{a.channels})={d['predicted_mean_per_instance_raw']:.6g} | count={d['assumed_instances']} | total={d['scenario_total']:.6g}")
print('\nESTIMATED DEPLOYMENT TOTALS (conditional on instance assumptions):')
for k,v in sorted(totals.items()):print(f'{k:25} {v:.8g}')
print('\nWARNING: extrapolation errors can grow sharply, especially for negative or superlinear projections. No confidence bounds are established by these RMSE values. Also CPU percentages are Docker per-container percentages summed, not host utilization, and MiB/s estimates are not proven steady-state.')
if a.output:
 with open(a.output,'w',newline='') as f:
  w=csv.DictWriter(f,fieldnames=list(result[0]));w.writeheader();w.writerows(result)
 print('Saved:',a.output)
