"""Focalized non-root tests. No real systemctl, nft, sudo, DB or media."""
import copy
import os
from pathlib import Path
import tempfile
import sqlite3
import unittest
from unittest.mock import patch
import ops

def unit(active="inactive", result="success", pid="0", job="0"):
    return {"ActiveState":active,"SubState":"dead" if active=="inactive" else active,
            "Result":result,"MainPID":pid,"Job":job,"ControlGroup":""}

class Fake(ops.Ops):
    def __init__(self):
        self.s={u:unit() for u in ops.PINS}
        self.events=[]
        self.fail_health=False
        self.fail_stop=False
        self.worker_busy=False
    def get(self,u): return self.s[u].copy()
    def preflight(self):
        self.events.append("preflight")
        self.check_quiet(ops.WORKER)
    def check_quiet(self,u,previous=""):
        ops.require(ops.quiet(self.get(u)),"UNIT_NOT_QUIESCENT")
    def stop_one(self,u):
        self.events.append(("stop",u))
        if self.fail_stop: raise ops.Refused("STOP_FAILED")
        self.s[u]=unit()
    def start_one(self,u):
        self.events.append(("start",u))
        self.s[u]=unit("active",pid="10")
    def listeners(self,running):
        self.events.append(("listeners",running))
    def no_processes(self): self.events.append("no_processes")
    def health(self):
        self.events.append("health")
        if self.fail_health: raise ops.Refused("HEALTH_FAILED")

def acl(uid):
    return [{"table":{"family":"inet","name":"montara_pilot_v2"}},
            {"chain":{"family":"inet","table":"montara_pilot_v2","name":"local_output","type":"filter","hook":"output","prio":-5,"policy":"accept"}},
            *[{"rule":{"family":"inet","table":"montara_pilot_v2","chain":"local_output","expr":[
                {"match":{"op":"==","left":{"meta":{"key":"oifname"}},"right":"lo"}},
                {"match":{"op":"==","left":{"payload":{"protocol":"tcp","field":"dport"}},"right":port}},
                {"match":{"op":"!=","left":{"meta":{"key":"skuid"}},"right":right}},{"reject":None}]}}
                for port,right in ((8080,{"set":[0,uid]}),(20246,0))]]

class Tests(unittest.TestCase):
    def test_start_order(self):
        f=Fake(); self.assertEqual(f.perform("start")["admission"],"LOCAL_READY_EXTERNAL_GATE_REQUIRED")
        self.assertLess(f.events.index(("start",ops.HTTP)),f.events.index("health"))
        self.assertLess(f.events.index("health"),f.events.index(("start",ops.INGRESS)))
    def test_stop_order(self):
        f=Fake(); f.perform("start"); f.events=[]
        f.perform("stop")
        self.assertLess(f.events.index(("stop",ops.INGRESS)),f.events.index(("stop",ops.HTTP)))
    def test_restart_order(self):
        f=Fake(); f.perform("start"); f.events=[]
        f.perform("restart")
        self.assertLess(f.events.index(("stop",ops.HTTP)),f.events.index(("start",ops.HTTP)))
    def test_worker_busy_no_mutation(self):
        f=Fake(); f.s[ops.WORKER]=unit("active",pid="7")
        for act in ("start","stop","restart","backup"):
            with self.assertRaises(ops.Refused): f.perform(act)
        self.assertFalse(any(isinstance(e,tuple) for e in f.events))
    def test_pending_job_no_mutation(self):
        f=Fake(); f.s[ops.WORKER]=unit(job="12")
        with self.assertRaises(ops.Refused): f.perform("restart")
        self.assertEqual(f.events,["preflight"])
    def test_worker_failed_no_start(self):
        f=Fake(); f.s[ops.WORKER]=unit("failed","exit-code")
        with self.assertRaises(ops.Refused): f.perform("start")
        self.assertFalse(any(isinstance(e,tuple) for e in f.events))
    def test_health_failure_closes(self):
        f=Fake(); f.fail_health=True
        with self.assertRaisesRegex(ops.Refused,"START_FAILED_CLOSED_LOCAL"): f.perform("start")
        self.assertNotIn(("start",ops.INGRESS),f.events)
        self.assertIn(("stop",ops.HTTP),f.events)
    def test_closure_failure_explicit(self):
        f=Fake(); f.fail_health=True; f.fail_stop=True
        with self.assertRaisesRegex(ops.Refused,"CLOSURE_UNVERIFIED"): f.perform("start")
    def test_no_other_actions(self):
        f=Fake()
        for act in ("shell","restore","promote","stop-worker","/tmp/x","start http"):
            with self.assertRaises(ops.Refused): f.perform(act)
        self.assertEqual(f.events,[])
    def test_props_rejects_missing(self):
        with self.assertRaises(ops.Refused): ops.props(b"ActiveState=inactive\n")
    def test_acl_valid(self):
        a=acl(1001); ops.validate_acl(a,1001)
        a[2]["rule"]["expr"].insert(1,{"match":{"op":"==","left":{"meta":{"key":"l4proto"}},"right":6}})
        ops.validate_acl(a,1001)
    def test_acl_drift(self):
        for alter in (lambda a:a.pop(),lambda a:a.reverse(),
                      lambda a:a[2]["rule"]["expr"][2]["match"].update(right={"set":[0,1002]})):
            a=acl(1001); alter(a)
            with self.assertRaises(ops.Refused): ops.validate_acl(a,1001)
    def test_launcher_final_matrix(self):
        base={"ActiveState":"inactive","SubState":"dead","MainPID":"0","Result":"success","ExecMainCode":"1","ExecMainStatus":"0"}
        self.assertEqual(ops.final_cycle(0,base),"EXIT_ZERO_RETAINED")
        self.assertEqual(ops.final_cycle(0,dict(base,ExecMainCode="0")),"EXIT_METADATA_UNAVAILABLE")
        for d in (dict(base,ExecMainCode="2"),dict(base,ExecMainStatus="4"),dict(base,Result="exit-code"),dict(base,ActiveState="active"),dict(base,SubState="running"),dict(base,MainPID="8")):
            self.assertEqual(ops.final_cycle(0,d),"REVIEW_REQUIRED")
        self.assertEqual(ops.final_cycle(124,base),"REVIEW_REQUIRED")
    def test_backup_and_retention(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t); state=p/"state"; dest=p/"backups"; state.mkdir(); dest.mkdir(mode=0o700)
            for n in ("db","originals","attempts","artifacts"): (state/n).mkdir(mode=0o700)
            f=state/"db/core.sqlite"
            with sqlite3.connect(f) as db:
                db.execute("PRAGMA user_version=5")
                db.execute("CREATE TABLE sample(id INTEGER PRIMARY KEY)")
                db.execute("INSERT INTO sample VALUES(1)")
            db.close(); f.chmod(0o600)
            with patch.object(ops,"root_dir"),patch.object(ops.shutil,"disk_usage",return_value=type("D",(),{"free":10*ops.GIB})()):
                for _ in range(2): self.assertEqual(ops.create_backup(state,dest,os.getuid(),ops.SLOT)["backup"],"VERIFIED_LOCAL")
                with self.assertRaisesRegex(ops.Refused,"RETENTION"): ops.create_backup(state,dest,os.getuid(),ops.SLOT)
            self.assertEqual(len(list(dest.iterdir())),2)
    def test_backup_invalid_db_not_published(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t); state=p/"state"; dest=p/"backups"; state.mkdir(); dest.mkdir(mode=0o700)
            for n in ("db","originals","attempts","artifacts"): (state/n).mkdir(mode=0o700)
            f=state/"db/core.sqlite"; f.write_bytes(b"invalid db"); f.chmod(0o600)
            with patch.object(ops,"root_dir"),patch.object(ops.shutil,"disk_usage",return_value=type("D",(),{"free":10*ops.GIB})()):
                with self.assertRaises((ops.Refused,sqlite3.DatabaseError)): ops.create_backup(state,dest,os.getuid(),ops.SLOT)
            self.assertEqual(list(dest.iterdir()),[])
    def test_backup_symlink_external_hardlink_and_size(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)
            for n in ("db","originals","attempts","artifacts"): (p/n).mkdir(mode=0o700)
            f=p/"db/core.sqlite"; f.write_bytes(b"test"); f.chmod(0o600)
            outside=p/"outside"; outside.write_bytes(b"x"); outside.chmod(0o600)
            x=p/"originals/x"; x.symlink_to(outside)
            with self.assertRaises(ops.Refused): ops.inventory(p,os.getuid())
            x.unlink(); os.link(outside,x)
            with self.assertRaisesRegex(ops.Refused,"EXTERNAL_HARDLINK"): ops.inventory(p,os.getuid())
            x.unlink()
            with patch.object(ops,"MAX_BYTES",1):
                with self.assertRaisesRegex(ops.Refused,"SIZE_LIMIT"): ops.inventory(p,os.getuid())

if __name__=="__main__": unittest.main(verbosity=2)
