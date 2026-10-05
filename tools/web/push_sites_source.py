"""Push a Sites checkout using an ephemeral credential read from stdin."""
import json
import getpass
import os
import subprocess
import sys
from pathlib import Path

site = Path(sys.argv[1]).resolve()
git = "C:/Program Files/Git/cmd/git.exe"
print("Awaiting ephemeral Sites credential without echo", flush=True)
credential = json.loads(getpass.getpass("Sites credential: ") if sys.stdin.isatty() else sys.stdin.readline())
token = credential["token"]
environment = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_CONFIG_COUNT="1",
                   GIT_CONFIG_KEY_0="http.extraHeader", GIT_CONFIG_VALUE_0="Authorization: Bearer " + token)


def run(*args):
    result = subprocess.run([git, "-C", str(site), *args], env=environment, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if result.returncode:
        raise RuntimeError((result.stdout + result.stderr).replace(token, "[REDACTED]"))
    return result.stdout.strip()


try:
    if run("remote", "get-url", "origin") != credential["remote_url"]:
        raise ValueError("Credential and checkout remote differ")
    if run("status", "--porcelain"):
        raise ValueError("Commit the exact Sites checkout before pushing")
    commit = run("rev-parse", "HEAD")
    before = run("ls-remote", "origin", "refs/heads/" + credential["branch"]).split()[0]
    print(json.dumps({"remote_before": before, "local_commit": commit}), flush=True)
    if before != commit:
        run("push", "origin", "HEAD:" + credential["branch"])
    remote = run("ls-remote", "origin", "refs/heads/" + credential["branch"]).split()[0]
    if remote != commit:
        raise ValueError("Remote source SHA differs from the prepared commit")
    print(json.dumps({"pushed": True, "commit": commit, "remote_sha_verified": remote}), flush=True)
finally:
    environment.pop("GIT_CONFIG_VALUE_0", None)
    token = ""
    credential.clear()
