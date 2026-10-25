"""Shared plotting implementation; each figure_NN.py is independently executable."""
import csv,argparse,collections
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from common import aggregate,write
FIELDS={'cpu':'cpu_percent','memory':'memory_mib','network_rx':'network_rx_mib_s','network_tx':'network_tx_mib_s','disk_read':'block_read_mib_s','disk_write':'block_write_mib_s'}
UNITS={'cpu':'Docker CPU %','memory':'MiB','network_rx':'MiB/s','network_tx':'MiB/s','disk_read':'MiB/s','disk_write':'MiB/s'}
def run(kind):
    p=argparse.ArgumentParser();p.add_argument('--csv',default='../metrics.csv');p.add_argument('--aggregated',default=None);p.add_argument('--out',default='results');a=p.parse_args()
    if a.aggregated:
    with open(a.aggregated,newline='') as f:rows=list(csv.DictReader(f))
    else:rows,_=aggregate(a.csv)
    groups=collections.defaultdict(list)
    for r in rows:
    if int(r['samples'])<2:continue
    groups[r['role']].append((int(r['towers']),int(r['shared_ledgers']),float(r[FIELDS[kind]])))
    fig,ax=plt.subplots(figsize=(9,5.5))
    for role,values in sorted(groups.items()):
    ax.scatter([v[0] for v in values],[v[2] for v in values],s=13,alpha=.55,label=role)
    ax.set(xlabel='Number of towers',ylabel=UNITS[kind],title=f'BCL/BCLm component resource usage — {kind.replace("_"," ")}')
    ax.legend(fontsize=8,ncol=2);ax.grid(alpha=.2);fig.tight_layout();out=Path(a.out);out.mkdir(exist_ok=True,parents=True);fig.savefig(out/f'{kind}.png',dpi=200);fig.savefig(out/f'{kind}.pdf');print(out/f'{kind}.png')
