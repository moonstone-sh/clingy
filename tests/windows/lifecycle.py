"""Native Windows tests. Real processes, no simulated OS detection."""
import ctypes
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

assert sys.platform == 'win32'
moon = str(Path(sys.argv[1]).resolve())
root = Path(__file__).resolve().parents[2]
fixture = str(Path(sys.argv[2]).resolve()) if len(sys.argv)>2 else str(root)
os.chdir(root)
kernel = ctypes.WinDLL('kernel32', use_last_error=True)
kernel.OpenProcess.restype = ctypes.c_void_p
kernel.OpenProcess.argtypes = [ctypes.c_uint32, ctypes.c_bool, ctypes.c_uint32]
kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
kernel.CloseHandle.argtypes = [ctypes.c_void_p]

def alive(pid):
    handle = kernel.OpenProcess(0x100000, False, pid)
    if not handle:
        return False
    try:
        return kernel.WaitForSingleObject(handle, 0) == 258
    finally:
        kernel.CloseHandle(handle)

def eventually(check, description):
    until = time.monotonic() + 25
    while time.monotonic() < until:
        if check():
            return
        time.sleep(.05)
    raise AssertionError(description)

with tempfile.TemporaryDirectory(prefix='clingy space ü ') as directory:
    work = Path(directory)
    child = work / 'child.py'
    child.write_text('''import json, os, subprocess, sys, time
from pathlib import Path
mode=sys.argv[1]
if mode == 'args':
 print(json.dumps([sys.argv[2:],os.environ['CLINGY_TEST_VALUE'],os.getcwd()]))
 sys.exit(17)
if mode == 'tree':
 p=subprocess.Popen([sys.executable,'-c','import time; time.sleep(120)'])
 Path(sys.argv[2]).write_text(str(p.pid))
 time.sleep(float(sys.argv[3]))
''', encoding='utf-8')
    processes, descendants = [], []
    def lua_string(value):
        return '"' + ''.join('\\%03d' % byte for byte in value.encode('utf-8')) + '"'
    def launch(name, mode, args, **extra):
        scripts = root / '.ci' / 'windows-contract'
        scripts.mkdir(parents=True, exist_ok=True)
        script = scripts / (name + '.ps1')
        config = scripts / (name + '.lua')
        config.write_text('return {argv={' + ','.join(map(lua_string,[sys.executable,str(child),*args])) +
            '},cwd=' + lua_string(str(work)) +
            ',env={CLINGY_TEST_VALUE=' + lua_string("literal & % ! ' ü") + ',CLINGY_OWNER_PID=' + lua_string(extra.get('CLINGY_TEST_OWNER','')) + '},grace_ms=200,stdin_eof=' +
            ('true' if mode=='eof' else 'false') + ',lock_dir=' + lua_string(extra.get('CLINGY_TEST_LOCK','')) +
            ',cleanup_files={' + lua_string(extra.get('CLINGY_TEST_CLEANUP',str(work/'missing'))) + '}}',encoding='ascii')
        subprocess.run([moon,'-C',fixture,'exec','--','lua',str(root/'tests/windows/supervisor.lua'),
                        str(script),str(config)],env=dict(os.environ,CLINGY_TEST_ROOT=str(root)),check=True,timeout=60)
        process = subprocess.Popen(['powershell.exe','-NoLogo','-NoProfile','-ExecutionPolicy','Bypass',
                         '-File',str(script)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE,creationflags=subprocess.CREATE_NEW_PROCESS_GROUP)
        processes.append(process)
        return process
    try:
        values = ['', 'space value', 'a"b', 'trailing\\', '%PATH%', '!x!', '&', 'ü']
        process = launch('args','normal',['args',*values])
        stdout, stderr = process.communicate(timeout=30)
        assert process.returncode == 17, stderr.decode(errors='replace')
        received = json.loads(stdout.decode('utf-8-sig'))
        assert received == [values,"literal & % ! ' ü",str(work)], received
        for name, action in [('exit',None),('break','break'),('eof','eof'),('killed','kill')]:
            pidfile=work/(name+'.pid')
            process=launch(name,'eof' if action=='eof' else 'normal',
                           ['tree',str(pidfile),'1' if action is None else '120'])
            print('Testing',name,flush=True)
            def started():
                if pidfile.exists(): return True
                if process.poll() is not None:
                    out,err=process.communicate()
                    raise AssertionError((name,process.returncode,out,err))
                return False
            eventually(started,'child did not start: '+name)
            pid=int(pidfile.read_text()); descendants.append(pid)
            assert alive(pid)
            if action=='break': process.send_signal(signal.CTRL_BREAK_EVENT)
            if action=='eof': process.stdin.close(); process.stdin=None
            if action=='kill': process.kill()
            stdout,stderr=process.communicate(timeout=15)
            if action in ('break','eof'):
                assert process.returncode==130,(process.returncode,stderr)
            elif action is None:
                assert process.returncode==0,stderr
            eventually(lambda:not alive(pid),'owned grandchild survived '+name)
        owner_process=subprocess.Popen([sys.executable,'-c','import time; time.sleep(120)'])
        processes.append(owner_process)
        owner_pidfile=work/'parent-loss.pid'
        supervised=launch('parent-loss','normal',['tree',str(owner_pidfile),'120'],CLINGY_TEST_OWNER=str(owner_process.pid))
        eventually(owner_pidfile.exists,'owned child did not start')
        descendant=int(owner_pidfile.read_text()); descendants.append(descendant)
        owner_process.kill(); owner_process.wait(timeout=10)
        supervised.communicate(timeout=15)
        assert supervised.returncode==130
        eventually(lambda:not alive(descendant),'grandchild survived owner death')
        # Contention must never remove the running owner's cleanup files.
        marker=work/'owner.pid'; marker.write_text('owned')
        lock=str(work/'session.lock')
        pidfile=work/'locked.pid'
        owner=launch('owner','normal',['tree',str(pidfile),'120'],
                     CLINGY_TEST_LOCK=lock,CLINGY_TEST_CLEANUP=str(marker))
        eventually(pidfile.exists,'owner did not start')
        descendants.append(int(pidfile.read_text()))
        contender=launch('contender','normal',['args'],
                         CLINGY_TEST_LOCK=lock,CLINGY_TEST_CLEANUP=str(marker))
        contender.communicate(timeout=30)
        assert contender.returncode!=0
        assert marker.read_text()=='owned'
        owner.send_signal(signal.CTRL_BREAK_EVENT)
        owner.communicate(timeout=15)
        eventually(lambda:not marker.exists(),'owner cleanup not applied')
        print('PASS: Windows flavor, argv, Unicode, exit, EOF, Ctrl+Break, job ownership and lock isolation')
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill(); process.wait(timeout=10)
        for pid in descendants:
            if alive(pid):
                subprocess.run(['taskkill','/F','/T','/PID',str(pid)],capture_output=True)
