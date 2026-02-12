#!/usr/bin/env python3
"""Helper to run SSH commands on the router with password auth."""
import os
import sys
import paramiko

def run(cmd, host=None, user="root", password="root", timeout=10):
    if host is None:
        host = os.environ.get("ROUTER_IP", "192.168.1.1")
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(host, username=user, password=password, timeout=timeout)
        stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout)
        out = stdout.read().decode("utf-8", errors="replace")
        err = stderr.read().decode("utf-8", errors="replace")
        rc = stdout.channel.recv_exit_status()
        if out:
            print(out, end="")
        if err:
            print(err, end="", file=sys.stderr)
        sys.exit(rc)
    except Exception as e:
        print(f"SSH Error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        client.close()

if __name__ == "__main__":
    args = sys.argv[1:]
    host = None
    if args and args[0].startswith("--host="):
        host = args.pop(0).split("=", 1)[1]
    if not args:
        print("Usage: ssh_cmd.py [--host=IP] <command>", file=sys.stderr)
        sys.exit(1)
    run(" ".join(args), host=host)
