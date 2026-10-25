import argparse
from pathlib import Path
from common import aggregate,write
p=argparse.ArgumentParser();p.add_argument('--csv',default='../metrics.csv');p.add_argument('--out',default='results');a=p.parse_args();d=Path(a.out);d.mkdir(exist_ok=True,parents=True)
rows,issues=aggregate(a.csv);write(rows,d/'aggregated.csv');print('Saved',len(rows),'configuration/role summaries;',dict(issues))
