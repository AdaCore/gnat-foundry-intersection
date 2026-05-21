"""QEMU integration test harness for the traffic-light controller.

Launches `qemu-system-arm` against the bare-metal `bin/qemu_mps2/main`
binary with two TCP-routed UARTs and exposes a synchronous API for
sending wire-protocol commands on UART1 and reading diagnostic records
off UART0.

Wire protocol (single source of truth):
  docs/requirements/wire-protocol.md

Per-record format on UART0:
  PH=<phase> T=<ms> PED=NS:<tok>,EW:<tok> LT=NS:<bit>,EW:<bit> FAULT=<bit>
  HB T=<ms>
  (plus a one-shot "startup" banner before the first PH= record)

Each test gets its own QemuSession (one QEMU process per test). Tests
are short — a full nominal cycle is ~55 s, but most scenarios reach
their assertion well inside the first 20 s.
"""
from __future__ import annotations

import os
import re
import select
import shutil
import socket
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator

ROOT = Path(__file__).resolve().parent.parent.parent
QEMU_BIN = ROOT / "bin" / "qemu_mps2" / "main"

# Port pool — tests run sequentially so a single pair is fine, but we
# offset by os.getpid() to avoid TIME_WAIT collisions across re-runs.
_PORT_BASE = 25000 + (os.getpid() % 1000) * 2


def _next_port_pair() -> tuple[int, int]:
    global _PORT_BASE
    p = _PORT_BASE
    _PORT_BASE += 2
    return p, p + 1


PH_RE = re.compile(
    r"^PH=(?P<phase>[A-Z_0-9]+)"
    r" T=(?P<t>\d+)"
    r" PED=NS:(?P<ped_ns>req|clr),EW:(?P<ped_ew>req|clr)"
    r" LT=NS:(?P<lt_ns>[01]),EW:(?P<lt_ew>[01])"
    r" FAULT=(?P<fault>[01])$"
)
HB_RE = re.compile(r"^HB T=(?P<t>\d+)$")


@dataclass
class Transition:
    """Parsed PH= record."""
    phase: str
    t_ms: int
    ped_ns: str
    ped_ew: str
    lt_ns: int
    lt_ew: int
    fault: int
    raw: str
    wall_ms: int  # ms since session start when we received the line

    @classmethod
    def parse(cls, line: str, wall_ms: int) -> "Transition | None":
        m = PH_RE.match(line)
        if not m:
            return None
        return cls(
            phase=m["phase"],
            t_ms=int(m["t"]),
            ped_ns=m["ped_ns"],
            ped_ew=m["ped_ew"],
            lt_ns=int(m["lt_ns"]),
            lt_ew=int(m["lt_ew"]),
            fault=int(m["fault"]),
            raw=line,
            wall_ms=wall_ms,
        )


@dataclass
class Heartbeat:
    t_ms: int
    raw: str
    wall_ms: int

    @classmethod
    def parse(cls, line: str, wall_ms: int) -> "Heartbeat | None":
        m = HB_RE.match(line)
        if not m:
            return None
        return cls(t_ms=int(m["t"]), raw=line, wall_ms=wall_ms)


@dataclass
class WireLog:
    """Everything the controller has written to UART0 so far."""
    transitions: list[Transition] = field(default_factory=list)
    heartbeats: list[Heartbeat] = field(default_factory=list)
    other: list[tuple[int, str]] = field(default_factory=list)  # (wall_ms, raw)
    all_lines: list[tuple[int, str]] = field(default_factory=list)

    def append(self, wall_ms: int, line: str) -> None:
        self.all_lines.append((wall_ms, line))
        tr = Transition.parse(line, wall_ms)
        if tr is not None:
            self.transitions.append(tr)
            return
        hb = Heartbeat.parse(line, wall_ms)
        if hb is not None:
            self.heartbeats.append(hb)
            return
        self.other.append((wall_ms, line))


class QemuSession:
    """One QEMU instance with UART0 (diag-out) + UART1 (cmd-in) routed
    over TCP. QEMU blocks at boot until both sockets are connected, so
    timestamps from session start are reproducible."""

    def __init__(self, qemu_binary: Path = QEMU_BIN,
                 boot_timeout_s: float = 5.0):
        self.qemu_binary = qemu_binary
        self.boot_timeout_s = boot_timeout_s
        self.uart0_port, self.uart1_port = _next_port_pair()
        self.proc: subprocess.Popen | None = None
        self.uart0: socket.socket | None = None
        self.uart1: socket.socket | None = None
        self.t0: float = 0.0
        self.log = WireLog()
        self._rx_buf = b""

    # ---- lifecycle ----
    def __enter__(self) -> "QemuSession":
        if not self.qemu_binary.exists():
            raise FileNotFoundError(
                f"{self.qemu_binary} not found — build with "
                f"`alr -n exec -- gprbuild -P traffic_light_qemu.gpr`"
            )
        qemu_exe = shutil.which("qemu-system-arm")
        if qemu_exe is None:
            raise FileNotFoundError("qemu-system-arm not on PATH")
        # Use server (NOT server,nowait) so QEMU blocks until both
        # connections are made — that way we never miss the boot-time
        # 'startup' banner or the first PH= record.
        cmd = [
            qemu_exe,
            "-M", "mps2-an385", "-cpu", "cortex-m3", "-nographic",
            "-serial", f"tcp:127.0.0.1:{self.uart0_port},server",
            "-serial", f"tcp:127.0.0.1:{self.uart1_port},server",
            "-kernel", str(self.qemu_binary),
        ]
        self.proc = subprocess.Popen(
            cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            self.uart0 = self._connect(self.uart0_port)
            self.uart1 = self._connect(self.uart1_port)
        except Exception:
            self.close()
            raise
        # QEMU starts executing the guest once both UARTs are connected.
        self.t0 = time.monotonic()
        return self

    def __exit__(self, *a) -> None:
        self.close()

    def close(self) -> None:
        for s in (self.uart0, self.uart1):
            try:
                if s is not None:
                    s.close()
            except OSError:
                pass
        self.uart0 = None
        self.uart1 = None
        if self.proc is not None and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=2)
        self.proc = None

    def _connect(self, port: int) -> socket.socket:
        deadline = time.monotonic() + self.boot_timeout_s
        last_err: Exception | None = None
        while time.monotonic() < deadline:
            try:
                s = socket.create_connection(("127.0.0.1", port), timeout=0.5)
                s.setblocking(False)
                return s
            except (ConnectionRefusedError, OSError) as e:
                last_err = e
                time.sleep(0.05)
        raise TimeoutError(
            f"QEMU UART port {port} never accepted: {last_err}"
        )

    # ---- elapsed time ----
    def elapsed_ms(self) -> int:
        return int((time.monotonic() - self.t0) * 1000)

    # ---- reading UART0 ----
    def _drain(self) -> None:
        """Pull all available bytes from UART0 into log; non-blocking."""
        assert self.uart0 is not None
        while True:
            try:
                chunk = self.uart0.recv(4096)
            except (BlockingIOError, InterruptedError):
                return
            except OSError:
                return
            if not chunk:
                return
            self._rx_buf += chunk
            while b"\n" in self._rx_buf:
                line, self._rx_buf = self._rx_buf.split(b"\n", 1)
                # Defensive CR strip — wire protocol is LF-only but a
                # passing client may emit CRLF.
                line = line.rstrip(b"\r")
                try:
                    decoded = line.decode("ascii", errors="replace")
                except Exception:
                    decoded = repr(line)
                self.log.append(self.elapsed_ms(), decoded)

    def read_until(self, predicate, timeout_s: float):
        """Pump UART0 until predicate(log) returns truthy or we time out.
        Returns the truthy value (often the object the predicate matched)
        or raises TimeoutError."""
        deadline = time.monotonic() + timeout_s
        while True:
            self._drain()
            result = predicate(self.log)
            if result:
                return result
            if time.monotonic() > deadline:
                raise TimeoutError(
                    f"predicate not satisfied in {timeout_s}s; "
                    f"last 8 lines: {self.log.all_lines[-8:]}"
                )
            assert self.uart0 is not None
            select.select([self.uart0], [], [], 0.05)

    def wait_for_transition_to(self, phase: str, timeout_s: float) -> Transition:
        """Wait for a PH= record with the given phase token."""
        def pred(log: WireLog):
            for tr in log.transitions:
                if tr.phase == phase:
                    return tr
            return None
        return self.read_until(pred, timeout_s)

    def wait_for_transitions(self, n: int, timeout_s: float) -> list[Transition]:
        """Wait until we've seen at least n transition records."""
        def pred(log: WireLog):
            return log.transitions if len(log.transitions) >= n else None
        return list(self.read_until(pred, timeout_s))

    def collect_for(self, seconds: float) -> None:
        """Just sit and drain for a fixed wall-clock window."""
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            self._drain()
            time.sleep(0.02)

    # ---- writing UART1 ----
    def send(self, cmd: str) -> None:
        """Send a command line on UART1 (cmd-in). LF appended if absent."""
        assert self.uart1 is not None
        if not cmd.endswith("\n"):
            cmd += "\n"
        self.uart1.sendall(cmd.encode("ascii"))


# ---------------- test discovery / runner ---------------- #

@dataclass
class TestResult:
    name: str
    req_ids: list[str]
    status: str           # "PASS" | "FAIL" | "SKIP"
    detail: str = ""
    duration_s: float = 0.0


_REQ_ID_RE = re.compile(r"\b(?:FR|NFR)-[A-Z]{2}-\d{2,}\b")


def extract_req_ids(func) -> list[str]:
    """Pull FR/NFR IDs from the function's @req attribute (set by the
    `requires` decorator) or, failing that, from its docstring."""
    ids = list(getattr(func, "_req_ids", ()))
    if not ids and func.__doc__:
        ids = _REQ_ID_RE.findall(func.__doc__)
    return ids


def requires(*req_ids: str):
    """Decorator: mark a test as covering one or more FR/NFR IDs.
    Also emits a `# @req ...` comment-equivalent at runtime, but the
    trace-check.py scanner reads the comment in the source file
    directly — the decorator is for the runner's report."""
    def wrap(fn):
        fn._req_ids = req_ids
        return fn
    return wrap


def _collect_tests(modules):
    tests = []
    for mod in modules:
        for name in sorted(dir(mod)):
            if not name.startswith("test_"):
                continue
            fn = getattr(mod, name)
            if not callable(fn):
                continue
            tests.append((mod.__name__, name, fn))
    return tests


def run(modules, *, verbose: bool = True) -> int:
    """Run every `test_*` function in `modules`. Returns process exit
    code: 0 on all-pass, 1 on any failure."""
    results: list[TestResult] = []
    tests = _collect_tests(modules)
    for mod_name, name, fn in tests:
        req_ids = extract_req_ids(fn)
        label = f"{mod_name}.{name}"
        if verbose:
            print(f"  [..] {label} @req={','.join(req_ids) or '-'}",
                  flush=True)
        start = time.monotonic()
        try:
            fn()
        except AssertionError as e:
            results.append(TestResult(
                name=label, req_ids=req_ids, status="FAIL",
                detail=str(e), duration_s=time.monotonic() - start,
            ))
            if verbose:
                print(f"  [FAIL] {label}: {e}", flush=True)
            continue
        except Exception as e:  # noqa: BLE001 — runner intentionally generic
            results.append(TestResult(
                name=label, req_ids=req_ids, status="FAIL",
                detail=f"{type(e).__name__}: {e}",
                duration_s=time.monotonic() - start,
            ))
            if verbose:
                print(f"  [FAIL] {label}: {type(e).__name__}: {e}",
                      flush=True)
            continue
        results.append(TestResult(
            name=label, req_ids=req_ids, status="PASS",
            duration_s=time.monotonic() - start,
        ))
        if verbose:
            print(f"  [PASS] {label} ({time.monotonic() - start:.1f}s)",
                  flush=True)

    n_pass = sum(1 for r in results if r.status == "PASS")
    n_fail = sum(1 for r in results if r.status == "FAIL")
    print()
    print(f"Summary: {n_pass} passed, {n_fail} failed, {len(results)} total")
    covered: set[str] = set()
    for r in results:
        if r.status == "PASS":
            covered.update(r.req_ids)
    if covered:
        print(f"Requirements exercised by passing tests "
              f"({len(covered)}): {', '.join(sorted(covered))}")
    if n_fail:
        print()
        print("Failures:")
        for r in results:
            if r.status == "FAIL":
                print(f"  {r.name} — {r.detail}")
    return 0 if n_fail == 0 else 1
