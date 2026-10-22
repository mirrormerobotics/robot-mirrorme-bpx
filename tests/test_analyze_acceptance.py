import importlib.util
import math
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('analysis',Path(__file__).parents[1]/'scripts/analyze_acceptance.py')
analysis=importlib.util.module_from_spec(spec)
spec.loader.exec_module(analysis)

def row(t,x,y,angle):
    return dict(event='odom',monotonic=t,position=[x,y,0],
                quaternion=[0,0,math.sin(angle/2),math.cos(angle/2)])

class AcceptanceTest(unittest.TestCase):
    def test_projected_distance_uses_initial_heading_and_rpc_window(self):
        events=[row(0,0,0,math.pi/2),dict(event='request',monotonic=.1,command={'forward_m':.2}),
                row(1,0,.15,math.pi/2),dict(event='result',monotonic=1.1,success=False),row(2,0,9,0)]
        r=analysis.summarize(events)
        self.assertAlmostEqual(r['projected_distance_m'],.15)
        self.assertAlmostEqual(r['distance_remaining_m'],.05)
        self.assertFalse(r['physical_accuracy_verified'])
    def test_rotation_crosses_wrap_without_losing_direction(self):
        r=analysis.summarize([row(0,0,0,math.radians(170)),row(1,0,0,math.radians(-170))])
        self.assertAlmostEqual(r['rotation_deg'],20)
    def test_missing_feedback_is_not_success(self):
        r=analysis.summarize([dict(event='request',monotonic=0,command={})])
        self.assertEqual(r['odom_samples'],0)
        self.assertFalse(r['completed_capture'])
    def test_health_fault_survives_missing_odometry(self):
        r=analysis.summarize([dict(event='motion_status',status=dict(health='fault',last_fault={'reason':'feedback disconnected'}))])
        self.assertEqual(r['final_health'],'fault')
        self.assertEqual(r['last_fault']['reason'],'feedback disconnected')

if __name__=='__main__': unittest.main()
