#!/usr/bin/env python3
"""Runs a command as the owner of every process it starts (Linux only).

Usage: gate_owner.py <command> [argument...]

The owner is a child subreaper, so a process orphaned anywhere below it, for
example when a gate worker is SIGKILLed, is reparented here instead of to init.
Once the command exits, every descendant still running is killed and reaped
before the owner returns, so none can later write results or scratch files.
TERM, INT and HUP, including the TERM sent when the owner's parent dies, stop
the command and all its descendants the same way.

Exits with the command's status (128+N if signal N killed it). If descendants
outlived the command, says so and exits with LEFTOVER_STATUS instead.
"""
import ctypes
import os
import signal
import subprocess
import sys

PR_SET_PDEATHSIG = 1
PR_SET_CHILD_SUBREAPER = 36
LEFTOVER_STATUS = 125
STOP_SIGNALS = (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)


class Stopped(Exception):
    def __init__(self, signum):
        super().__init__(signum)
        self.signum = signum


def prctl(option, value):
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(option, value, 0, 0, 0) != 0:
        error = ctypes.get_errno()
        raise OSError(error, f"prctl({option}) failed: {os.strerror(error)}")


def live_children():
    """Children of this process that have not exited yet (zombies excluded)."""
    own_pid = os.getpid()
    children = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/stat") as handle:
                fields = handle.read().rsplit(")", 1)[1].split()
        except OSError:
            continue  # exited while scanning
        if int(fields[1]) == own_pid and fields[0] != "Z":
            children.append(int(entry))
    return children


def stop_descendants():
    """Kills and reaps every descendant; returns how many were still running.

    Killing a child reparents its children here before the child becomes
    waitable, so each pass finds the next generation. No child at all means no
    descendant is left.
    """
    killed = set()
    while True:
        for pid in live_children():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                continue
            killed.add(pid)
        try:
            os.waitpid(-1, 0)
        except ChildProcessError:
            return len(killed)


def exit_status(wait_status):
    if os.WIFSIGNALED(wait_status):
        return 128 + os.WTERMSIG(wait_status)
    return os.WEXITSTATUS(wait_status)


def main(command):
    if not command:
        print(__doc__.split("\n\n", 2)[1], file=sys.stderr)
        return 2

    def stop(signum, _frame):
        for stop_signal in STOP_SIGNALS:
            signal.signal(stop_signal, signal.SIG_IGN)
        raise Stopped(signum)

    parent = os.getppid()
    try:
        for stop_signal in STOP_SIGNALS:
            signal.signal(stop_signal, stop)
        prctl(PR_SET_CHILD_SUBREAPER, 1)
        prctl(PR_SET_PDEATHSIG, signal.SIGTERM)
        if os.getppid() != parent:
            raise Stopped(signal.SIGTERM)  # the parent died before PDEATHSIG was set
        child = subprocess.Popen(command)
        _, wait_status = os.waitpid(child.pid, 0)
    except Stopped as stopped:
        stop_descendants()
        return 128 + stopped.signum
    except OSError as error:
        print(f"gate_owner: cannot run {command[0]}: {error}", file=sys.stderr)
        stop_descendants()
        return LEFTOVER_STATUS
    # The command is done; nothing it started may outlive it.
    for stop_signal in STOP_SIGNALS:
        signal.signal(stop_signal, signal.SIG_IGN)
    leftovers = stop_descendants()
    if leftovers:
        print(f"gate_owner: killed {leftovers} process(es) left running by: {' '.join(command)}", file=sys.stderr)
        return LEFTOVER_STATUS
    return exit_status(wait_status)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
