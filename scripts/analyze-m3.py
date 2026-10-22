"""Offline M3 timestamp and reconnect evidence; no physical calibration claims."""
import argparse
import hashlib
import json
import math
import statistics
from pathlib import Path


def analyze(path):
    rows = [json.loads(line) for line in path.read_text().splitlines()]
    odom = [r for r in rows if r['topic']=='odom']
    health = [r for r in rows if r['topic']=='health']
    vendor = []
    for row in health:
        for status in row['data']['status']:
            values = {v['key']:json.loads(v['value']) for v in status['values']}
            if values.get('vendor_timestamps'):
                vendor.append((row['monotonic'],values['vendor_timestamps']))
    rates = {}
    for key in ('odometry_ms','imu_ms','joint_ms'):
        ts = [(t,v[key]) for t,v in vendor if v.get(key) is not None]
        diffs = [b[1]-a[1] for a,b in zip(ts,ts[1:])]
        rates[key] = {'regressions':sum(d<0 for d in diffs),
                     'median_positive_increment':statistics.median([d for d in diffs if d>0]) if any(d>0 for d in diffs) else None,
                     'ticks_per_host_second':(ts[-1][1]-ts[0][1])/(ts[-1][0]-ts[0][0]) if len(ts)>1 else None}
    def pose(row):
        return row['data']['pose']['pose']
    return {'file':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'vendor_clock_observation':rates, 'first_pose':pose(odom[0]) if odom else None,
            'last_pose':pose(odom[-1]) if odom else None,
            'joint_lengths':sorted(set(len(r['data']['position']) for r in rows if r['topic']=='joints')),
            'first_vendor':vendor[0][1] if vendor else None,'last_vendor':vendor[-1][1] if vendor else None}


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('before',type=Path)
parser.add_argument('after',type=Path)
parser.add_argument('--output',required=True,type=Path)
args = parser.parse_args()
before,after = analyze(args.before),analyze(args.after)
distance = None
if before['last_pose'] and after['first_pose']:
    distance = math.sqrt(sum((before['last_pose']['position'][axis]-after['first_pose']['position'][axis])**2 for axis in 'xyz'))
report = {'before':before,'after':after,'position_difference_between_windows_m':distance,
          'physical_stationarity_confirmed':False,'coordinate_reset_verdict':'not established',
          'limitations':'Observed clock slope supports millisecond-scale ticks, not epoch/wrap proof. Windows are separated in time; no external pose reference, robot reboot or initial-heading change was performed.'}
with args.output.open('x') as stream:
    json.dump(report,stream,indent=2)
print(json.dumps(report,indent=2))
