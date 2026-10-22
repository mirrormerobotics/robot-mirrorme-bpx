"""Offline odometry estimates; never claims externally measured physical accuracy."""
import argparse
import json
import math
from pathlib import Path


def summarize(events):
    request = next((x for x in events if x.get('event')=='request'), None)
    result = next((x for x in events if x.get('event')=='result'), None)
    odom = [x for x in events if x.get('event')=='odom']
    report = {'odom_samples':len(odom),'request':request,'result':result,
              'physical_accuracy_verified':False, 'completed_capture':any(x.get('event')=='capture_end' for x in events)}
    statuses=[x for x in events if x.get('event')=='motion_status']
    report['diagnostic_samples']=len(statuses)
    faults=[x['status'].get('last_fault') for x in statuses if x['status'].get('last_fault')]
    report['last_fault']=faults[-1] if faults else None
    report['server_last_move']=statuses[-1]['status'].get('last_move') if statuses else None
    report['final_health']=statuses[-1]['status'].get('health') if statuses else None
    if not odom: return report
    if request:
        before=[x for x in odom if x['monotonic']<=request['monotonic']]
        if not before:
            report['error']='missing pre-request odom'; return report
        start=before[-1]
        finish=result['monotonic'] if result else odom[-1]['monotonic']
        selected=[start]+[x for x in odom if start['monotonic']<x['monotonic']<=finish]
    else: selected=odom
    def yaw(row):
        x,y,z,w=row['quaternion']
        return math.atan2(2*(w*z+x*y),1-2*(y*y+z*z))
    first,last=selected[0],selected[-1]
    heading=yaw(first)
    dx=last['position'][0]-first['position'][0]
    dy=last['position'][1]-first['position'][1]
    distance=dx*math.cos(heading)+dy*math.sin(heading)
    angle=math.degrees(sum(math.atan2(math.sin(yaw(b)-yaw(a)),math.cos(yaw(b)-yaw(a)))
                           for a,b in zip(selected,selected[1:])))
    report.update(projected_distance_m=distance, lateral_displacement_m=-dx*math.sin(heading)+dy*math.cos(heading),
                  rotation_deg=angle, max_observed_sample_gap_s=max((b['monotonic']-a['monotonic']
                        for a,b in zip(selected,selected[1:])), default=0),
                  initial_sample_age_s=(request['monotonic']-first['monotonic']) if request else 0,
                  estimate_only=True)
    if request:
        cmd=request['command']
        if cmd.get('forward_m'):
            report['distance_remaining_m']=cmd['forward_m']-distance
        elif cmd.get('rotate_deg'):
            report['angle_remaining_deg']=cmd['rotate_deg']-angle
    return report


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('capture',type=Path)
    p.add_argument('--output',type=Path)
    p.add_argument('--measured-distance-m',type=float,help='Externally measured signed displacement along initial heading')
    p.add_argument('--measured-angle-deg',type=float,help='Externally measured signed rotation')
    args=p.parse_args()
    events=[]
    for line in args.capture.read_text().splitlines():
        try: value=json.loads(line)
        except ValueError: continue
        if isinstance(value,dict): events.append(value)
    report=summarize(events)
    for key,value in [('distance_m',args.measured_distance_m),('angle_deg',args.measured_angle_deg)]:
        if value is not None:
            if not math.isfinite(value): p.error('external measurements must be finite')
            report['operator_measured_'+key]=value
    text=json.dumps(report,indent=2,ensure_ascii=False,allow_nan=False)
    if args.output:
        with args.output.open('x') as stream: stream.write(text+'\n')
    print(text)


if __name__=='__main__': main()
