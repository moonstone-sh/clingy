#!/usr/bin/env python3
"""Exercise Clingy's actual Bash supervisor with real processes and a PTY.

Run from any directory: python3 tests/process_supervision.py
The Lua fixture uses `moon exec --dev lua` and loads the working-tree module.
CLINGY_TEST_BASH can select another Bash (the default tests macOS Bash 3.2).
"""

import errno
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


REPO = Path(__file__).resolve().parents[1]
THIS_FILE = Path(__file__).resolve()
BASH = os.environ.get("CLINGY_TEST_BASH", "/bin/bash")
LITERAL = "literal $(echo unsafe) `echo unsafe` ' \" $HOME"


def eventually(predicate, timeout=7):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.04)
    return bool(predicate())


def is_live(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    result = subprocess.run(
        ["ps", "-p", str(pid), "-o", "stat="], capture_output=True, text=True
    )
    state = result.stdout.strip()
    return bool(state) and not state.startswith("Z")


def worker(mode, root, args):
    """The test's workload; every live PID is recorded for failure cleanup."""
    if mode == "parent":
        manager = subprocess.Popen([BASH, str(root / "supervisor.sh")])
        (root / "manager.pid").write_text(str(manager.pid))
        return manager.wait()
    if mode == "leaf":
        if args and args[0] == "ignore":
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
        (root / "leaf.pid").write_text(str(os.getpid()))
        while True:
            time.sleep(1)
    if mode == "quote":
        (root / "result.json").write_text(json.dumps({
            "argv": args,
            "env": os.environ.get("CLINGY_TEST_LITERAL"),
            "cwd": os.getcwd(),
            "supervised": os.environ.get("CLINGY_SUPERVISED"),
        }))
        return 0

    if mode == "ignore":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
    (root / "worker.pid").write_text(str(os.getpid()))
    child = subprocess.Popen([
        sys.executable, str(THIS_FILE), "--worker", "leaf", str(root),
        "ignore" if mode == "ignore" else "normal",
    ])
    (root / "child.pid").write_text(str(child.pid))
    if not eventually(lambda: (root / "leaf.pid").exists()):
        return 24
    (root / "ready").write_text("ready")
    if mode in {"normal", "failure"}:
        time.sleep(0.2)
        return 23 if mode == "failure" else 0
    while True:
        time.sleep(1)


class Session:
    def __init__(self, case, mode="running", tty=False, args=(), parent=False, lock=None):
        self.case = case
        self.temp = tempfile.TemporaryDirectory(prefix="clingy process '")
        self.root = Path(self.temp.name)
        self.proc = None
        self.master = None
        self.log = None
        self.tty_output = bytearray()
        case.addCleanup(self.close)
        (self.root / "cleanup.marker").write_text("owned by this invocation")
        fixture_env = os.environ.copy()
        if lock is not None:
            fixture_env["CLINGY_TEST_LOCK_DIR"] = str(lock)
        generated = subprocess.run([
            os.environ.get("MOONSTONE_BIN", shutil.which("moon") or "moon"),
            "exec", "--dev", "lua", "tests/process_supervision_fixture.lua",
            str(self.root), "tty" if tty else "redirected", sys.executable,
            str(THIS_FILE), "--worker", mode, str(self.root), *args,
        ], cwd=REPO, env=fixture_env, capture_output=True, text=True, timeout=30)
        case.assertEqual(generated.returncode, 0, generated.stderr)
        case.assertIn("#!/", generated.stdout, "fixture must emit a Bash script")
        self.script = self.root / "supervisor.sh"
        self.script.write_text(generated.stdout)
        if tty:
            pid, self.master = pty.fork()
            if pid == 0:
                if parent:
                    os.execv(sys.executable, [sys.executable, str(THIS_FILE),
                        "--worker", "parent", str(self.root)])
                os.execv(BASH, [BASH, str(self.script)])
            self.pid = pid
            self.pty_status = None
        else:
            self.log = (self.root / "supervisor.log").open("w+")
            argv = [BASH, str(self.script)]
            if parent:
                argv = [sys.executable, str(THIS_FILE), "--worker", "parent", str(self.root)]
            self.proc = subprocess.Popen(
                argv, stdin=subprocess.DEVNULL, stdout=self.log, stderr=self.log,
                start_new_session=True,
            )
            self.pid = self.proc.pid

    def pids(self):
        result = []
        for path in self.root.glob("*.pid"):
            try:
                result.append(int(path.read_text().strip()))
            except (ValueError, FileNotFoundError):
                pass
        return result

    def output(self):
        if self.master is not None:
            while select.select([self.master], [], [], 0)[0]:
                try:
                    chunk = os.read(self.master, 65536)
                except OSError as exc:
                    if exc.errno == errno.EIO:
                        break
                    raise
                if not chunk:
                    break
                self.tty_output.extend(chunk)
            return self.tty_output.decode(errors="replace")
        if self.log:
            self.log.flush()
            return (self.root / "supervisor.log").read_text()
        return ""

    def poll(self):
        if self.proc:
            return self.proc.poll()
        # macOS can leave a PTY session leader in exit-in-progress until the
        # master drains its final job-control/cleanup output.
        self.output()
        if self.pty_status is None:
            pid, status = os.waitpid(self.pid, os.WNOHANG)
            if pid:
                self.pty_status = os.waitstatus_to_exitcode(status)
        return self.pty_status

    def ready(self):
        self.case.assertTrue(eventually(lambda: (self.root / "ready").exists()), self.output())
        self.case.assertIsNone(self.poll(), self.output())
        return self

    def stopped(self, expected=None):
        exited = eventually(lambda: self.poll() is not None)
        if not exited:
            details = subprocess.run([
                "ps", "-p", str(self.pid), "-o", "pid=,ppid=,pgid=,stat=,wchan=,command=",
            ], capture_output=True, text=True).stdout
            self.case.fail(self.output() + "\n" + details)
        if expected is not None:
            self.case.assertEqual(self.poll(), expected, self.output())
        self.case.assertTrue(
            eventually(lambda: all(not is_live(pid) for pid in self.pids())),
            "owned processes survived: " + str(self.pids()) + "\n" + self.output(),
        )
        self.case.assertFalse((self.root / "cleanup.marker").exists(), self.output())

    def close(self):
        # Only PIDs born in this test are eligible for emergency test cleanup.
        if self.proc is not None or self.master is not None:
            for pid in self.pids() + [self.pid]:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            if self.proc is not None:
                self.proc.wait(timeout=5)
            elif self.pty_status is None:
                os.waitpid(self.pid, 0)
        if self.master is not None:
            os.close(self.master)
        if self.log:
            self.log.close()
        self.temp.cleanup()


@unittest.skipUnless(os.name == "posix", "Bash process supervision is POSIX-only")
class ProcessSupervision(unittest.TestCase):
    def test_targeted_signals_stop_the_owned_tree(self):
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            with self.subTest(signal=sig.name):
                session = Session(self).ready()
                os.kill(session.pid, sig)
                session.stopped(128 + sig)

    def test_second_signal_escalates_without_abandoning_children(self):
        session = Session(self, mode="ignore").ready()
        os.kill(session.pid, signal.SIGINT)
        time.sleep(0.05)
        os.kill(session.pid, signal.SIGINT)
        session.stopped(130)

    def test_term_ignoring_children_are_killed_after_grace(self):
        session = Session(self, mode="ignore").ready()
        os.kill(session.pid, signal.SIGTERM)
        session.stopped(143)

    def test_normal_and_failed_worker_exit_remove_surviving_children(self):
        for mode, code in (("normal", 0), ("failure", 23)):
            with self.subTest(mode=mode):
                Session(self, mode=mode).stopped(code)

    def test_terminal_ctrl_c(self):
        session = Session(self, tty=True).ready()
        os.write(session.master, b"\x03")
        session.stopped(130)

    def test_terminal_ctrl_d(self):
        session = Session(self, tty=True).ready()
        os.write(session.master, b"\x04")
        session.stopped(0)

    def test_idle_terminal_survives_read_timeouts(self):
        session = Session(self, tty=True).ready()
        time.sleep(2.2)
        self.assertIsNone(session.poll(), session.output())
        os.write(session.master, b"\x04")
        session.stopped(0)

    def test_child_status_change_does_not_masquerade_as_terminal_eof(self):
        session = Session(self, tty=True).ready()
        worker = int((session.root / "worker.pid").read_text())
        os.kill(worker, signal.SIGSTOP)
        time.sleep(0.05)
        os.kill(worker, signal.SIGCONT)
        time.sleep(1.2)
        self.assertIsNone(session.poll(), session.output())
        self.assertNotIn("Bad file descriptor", session.output())
        os.write(session.master, b"\x04")
        session.stopped(0)

    def test_redirected_stdin_eof_does_not_stop_service(self):
        session = Session(self).ready()
        time.sleep(1.2)
        self.assertIsNone(session.poll(), session.output())
        self.assertTrue(all(is_live(pid) for pid in session.pids()))
        os.kill(session.pid, signal.SIGTERM)
        session.stopped(143)

    def test_parent_death_stops_supervisor_and_owned_tree(self):
        session = Session(self, parent=True).ready()
        os.kill(session.pid, signal.SIGTERM)
        session.stopped(-signal.SIGTERM)

    def test_terminal_parent_death_wakes_blocking_eof_reader(self):
        session = Session(self, parent=True, tty=True).ready()
        os.kill(session.pid, signal.SIGTERM)
        session.stopped(-signal.SIGTERM)

    def test_parallel_session_survives_peer_shutdown(self):
        first = Session(self).ready()
        second = Session(self).ready()
        os.kill(first.pid, signal.SIGTERM)
        first.stopped(143)
        self.assertIsNone(second.poll(), second.output())
        self.assertTrue(all(is_live(pid) for pid in second.pids()))
        os.kill(second.pid, signal.SIGTERM)
        second.stopped(143)

    def test_lock_collision_preserves_the_active_session(self):
        lock_root = tempfile.TemporaryDirectory(prefix="clingy-lock-")
        self.addCleanup(lock_root.cleanup)
        lock = Path(lock_root.name) / "session.lock"
        first = Session(self, lock=lock).ready()
        owner = (lock / "owner.pid").read_text()
        second = Session(self, lock=lock)
        self.assertTrue(eventually(lambda: second.poll() is not None), second.output())
        self.assertEqual(second.poll(), 1, second.output())
        self.assertIsNone(first.poll(), first.output())
        self.assertEqual((lock / "owner.pid").read_text(), owner)
        self.assertTrue((first.root / "cleanup.marker").exists())
        self.assertTrue((second.root / "cleanup.marker").exists())
        self.assertFalse((second.root / "worker.pid").exists())
        os.kill(first.pid, signal.SIGTERM)
        first.stopped(143)
        self.assertFalse(lock.exists())

    def test_signal_during_startup(self):
        for delay in (0, 0.002, 0.005, 0.01, 0.02, 0.04):
            with self.subTest(delay=delay):
                session = Session(self)
                time.sleep(delay)
                try:
                    os.kill(session.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                self.assertTrue(eventually(lambda: session.poll() is not None), session.output())
                self.assertTrue(eventually(lambda: all(not is_live(pid) for pid in session.pids())), session.output())

    def test_argv_env_and_cwd_are_literal(self):
        arguments = ["", "space value", "'\"$HOME", "$(echo unsafe)", "`echo unsafe`", "line\nbreak", "; exit 99"]
        session = Session(self, mode="quote", args=arguments)
        session.stopped(0)
        result = json.loads((session.root / "result.json").read_text())
        self.assertEqual(result["argv"], arguments)
        self.assertEqual(result["env"], LITERAL)
        self.assertEqual(Path(result["cwd"]).resolve(), session.root.resolve())
        self.assertEqual(result["supervised"], "1")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--worker":
        sys.exit(worker(sys.argv[2], Path(sys.argv[3]), sys.argv[4:]))
    unittest.main(verbosity=2)
