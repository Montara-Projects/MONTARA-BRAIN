"""Tests of exact staged shell bundle; never execute administrative bootstrap."""
import ast
import hashlib
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

D=Path(__file__).resolve().parent

class Bundle(unittest.TestCase):
    def test_shell_syntax(self):
        for n in ("activate.sh","worker-start.sh","montara-v2-ops.sh"):
            subprocess.run(["bash","-n",str(D/n)],check=True)
        code=(D/"activate.sh").read_text()
        blocks=re.findall(r"<<'PY'\n(.*?)\nPY\n",code,re.S)
        self.assertEqual(len(blocks),3)
        for b in blocks: ast.parse(b)
    def test_exact_pins(self):
        s=(D/"activate.sh").read_text()
        for n in ("ops.py","worker-start.sh","montara-v2-ops.sh","sudoers"):
            raw=(D/n).read_bytes()
            h=hashlib.sha1(b"blob "+str(len(raw)).encode()+b"\0"+raw).hexdigest()
            self.assertIn('hashgit "$D/'+n+'" '+h,s)
    def test_fixed_policy(self):
        p=(D/"sudoers").read_text()
        lines=[l for l in p.splitlines() if l and not l.startswith("#")]
        self.assertEqual(lines,["sentinelx ALL=(root) NOPASSWD: NOSETENV: "+
            ", ".join("/usr/local/sbin/montara-v2-ops-root "+a for a in ("status","start","stop","restart","backup"))])
        self.assertNotIn("*",lines[0])
        s=(D/"montara-v2-ops.sh").read_text()
        self.assertIn('test "$#" = 1',s)
        self.assertIn('status|start|stop|restart|backup',s)
    def test_exact_launcher_classifier(self):
        code=(D/"worker-start.sh").read_text()
        fn=code[code.index("classify() {"):code.index('\nclassify "$rc"')]
        base="MainPID=0\nResult=success\nExecMainCode=1\nExecMainStatus=0\nActiveState=inactive\nSubState=dead"
        cases=[(0,base,"WORKER_CYCLE_EXIT_ZERO"),
               (0,base.replace("Code=1","Code=0"),"WORKER_CYCLE_EXIT_METADATA_UNAVAILABLE"),
               (1,base,None),(124,base,None),
               (0,base.replace("Code=1","Code=2"),None),
               (0,base.replace("Status=0","Status=4"),None),
               (0,base.replace("inactive","active"),None),
               (0,base.replace("dead","running"),None),
               (0,base.replace("MainPID=0","MainPID=8"),None),
               (0,base.replace("Result=success","Result=exit-code"),None),
               (0,base+"\nExecMainCode=0",None),
               (0,base.replace("SubState=dead",""),None)]
        for rc,txt,expected in cases:
            with self.subTest(rc=rc,txt=txt):
                r=subprocess.run(["bash","-c",fn+'\nclassify "$1" "$2"',"test",str(rc),txt],capture_output=True,text=True)
                self.assertEqual(r.returncode==0,expected is not None)
                if expected: self.assertEqual(r.stdout.strip(),expected)
    def test_config_delta_mock_owner(self):
        # The actual program requires uid0. Adapt only that assertion for this
        # nonroot fixture; parse/semantic checks and atomic replacement are exact.
        s=(D/"activate.sh").read_text()
        block=re.findall(r"<<'PY'\n(.*?)\nPY\n",s,re.S)[0]
        self.assertEqual(block.count("st.st_uid==0"),1)
        block=block.replace("st.st_uid==0","st.st_uid==os.getuid()")
        import yaml
        orig='exec_mode: strict\nallowed_commands:\n  - uptime\n  - free -h\n  - df -h\n  - id\n  - /usr/local/bin/montara-test\n  - /usr/local/bin/montara-pilot-worker-start\n  - /usr/local/bin/montara-pilot-worker-status\n# private comment\nother: true\n'
        new="/usr/local/bin/montara-v2-ops"
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/"config.yaml"; p.write_text(orig); p.chmod(0o600)
            for mode in ("add","remove"):
                subprocess.run(["python3","-I","-c",block,str(p),mode,new],check=True)
                if mode=="add":
                    expected=yaml.safe_load(orig); expected["allowed_commands"].append(new)
                    self.assertEqual(yaml.safe_load(p.read_text()),expected)
            self.assertEqual(p.read_text(),orig)
            self.assertEqual(p.stat().st_mode&0o777,0o600)

if __name__=="__main__": unittest.main(verbosity=2)
