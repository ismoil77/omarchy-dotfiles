#!/usr/bin/env python3
"""Reads the state of a chezmoi setup for the Dotfiles widget.

Prints one JSON object and no human words (the widget owns the texts):

  ok, error      error is "" or nochezmoi / nosource / busy / internal
  host           this machine's name
  remote         "owner/repo" of origin, without any credentials in the URL
  upstream       whether the source branch tracks a remote branch
  local          files changed on this machine and not in the repo yet:
                 [{path, kind}] with kind modified / deleted / added / new
  pending        files the repo has and this machine has not applied: [{path, kind}]
  scripts        scripts `chezmoi apply` would run
  uncommitted    changed files in the source repo not committed yet
  ahead, behind  commits not pushed / not pulled
  incoming       the commits not pulled, newest first: [{subject, time, files}]
  history        the last commits of the source repo: [{subject, time, files}]
  fetch          {time, error}: when origin was last fetched (0 = never) and
                 why the last try failed ("" / offline / auth / failed)

  state.py [--fetch] [--chezmoi PATH]

--fetch asks origin first (git fetch, no prompts, 25 s at most).
"""
import json
import os
import re
import shutil
import socket
import subprocess
import sys

HISTORY = 5
INCOMING = 10
TIMEOUT = 20
FETCH_TIMEOUT = 25

# One environment for every child: no pager, no prompt for a password, plain
# English messages so fetch errors can be classified.
ENV = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_PAGER="cat", PAGER="cat", LC_ALL="C",
           GIT_SSH_COMMAND=os.environ.get("GIT_SSH_COMMAND", "ssh -o BatchMode=yes"))


class Busy(Exception):
    pass


def run(cmd, timeout=TIMEOUT, check=True):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=ENV, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        raise Busy()
    if check and p.returncode != 0:
        raise subprocess.CalledProcessError(p.returncode, cmd, p.stdout, p.stderr)
    return p


def find_chezmoi(given):
    for c in [given, shutil.which("chezmoi"), os.path.expanduser("~/.local/bin/chezmoi"), "/usr/bin/chezmoi"]:
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    return None


# ---------- parsers (pure, unit-tested) ----------

STATUS_KIND = {"M": "modified", "A": "added", "D": "deleted"}


def parse_status(text):
    """`chezmoi status` lines -> (local, pending, scripts).

    Column 1 is what changed on disk since chezmoi last wrote the file (an edit
    made here), column 2 what `apply` would change. A file edited here is
    local even when the repo changed it too: apply will ask about it.
    """
    local, pending, scripts = [], [], 0
    for line in text.splitlines():
        if len(line) < 4:
            continue
        first, second, path = line[0], line[1], line[3:]
        if second == "R" or first == "R":
            scripts += 1
        elif first != " ":
            local.append({"path": "~/" + path, "kind": STATUS_KIND.get(first, "modified")})
        elif second != " ":
            pending.append({"path": "~/" + path, "kind": STATUS_KIND.get(second, "modified")})
    return local, pending, scripts


def parse_log(text):
    """`git log --format=%x1e%ct%x1f%s --shortstat` -> [{subject, time, files}]."""
    out = []
    for chunk in text.split("\x1e"):
        chunk = chunk.strip("\n")
        if not chunk:
            continue
        head, _, rest = chunk.partition("\n")
        when, _, subject = head.partition("\x1f")
        m = re.search(r"(\d+) files? changed", rest)
        try:
            when = int(when)
        except ValueError:
            continue
        out.append({"subject": subject, "time": when, "files": int(m.group(1)) if m else 0})
    return out


def classify_fetch(stderr):
    s = stderr.lower()
    if any(k in s for k in ("could not resolve", "unable to access", "network is unreachable",
                             "connection timed out", "connection refused", "temporary failure")):
        return "offline"
    if any(k in s for k in ("authentication failed", "could not read username", "permission denied",
                             "repository not found", "403")):
        return "auth"
    return "failed"


def short_remote(url):
    """Any remote URL -> "owner/repo", never with a user or token in it."""
    url = url.strip()
    url = re.sub(r"^[a-z+]+://[^@/]*@", lambda m: m.group(0).split("://")[0] + "://", url)
    url = re.sub(r"\.git$", "", url)
    m = re.search(r"[:/]([^/:]+/[^/:]+)$", url)
    return m.group(1) if m else ""


def count_ahead_behind(text):
    parts = text.split()
    return (int(parts[0]), int(parts[1])) if len(parts) == 2 else (0, 0)


# ---------- reading ----------

def watch_folders(cz):
    """Folders listed under `dotfiles.watch` in chezmoi's data: new files in them count as local."""
    try:
        data = json.loads(run([cz, "data", "--format=json"]).stdout or "{}")
    except (subprocess.CalledProcessError, ValueError):
        return []
    watch = (data.get("dotfiles") or {}).get("watch") or []
    return [p for p in (os.path.expanduser(str(w)) for w in watch) if os.path.isdir(p)]


def new_files(cz, folders):
    if not folders:
        return []
    home = os.path.expanduser("~")
    p = run([cz, "unmanaged", "--path-style=absolute", *folders], check=False)
    out = []
    for line in p.stdout.splitlines():
        if line.startswith(home + "/"):
            line = "~" + line[len(home):]
        out.append({"path": line, "kind": "new"})
    return out


def fetch_head_time(src):
    try:
        return int(os.path.getmtime(os.path.join(src, ".git", "FETCH_HEAD")))
    except OSError:
        return 0


def read(cz, do_fetch):
    state = {"ok": False, "error": "", "host": socket.gethostname(), "remote": "", "upstream": False,
             "local": [], "pending": [], "scripts": 0, "uncommitted": 0, "ahead": 0, "behind": 0,
             "incoming": [], "history": [], "fetch": {"time": 0, "error": ""}}
    try:
        src = run([cz, "source-path"]).stdout.strip()
    except subprocess.CalledProcessError:
        src = ""
    if not src or not os.path.isdir(os.path.join(src, ".git")):
        state["error"] = "nosource"
        return state
    git = ["git", "-C", src]

    state["remote"] = short_remote(run(git + ["remote", "get-url", "origin"], check=False).stdout)
    state["upstream"] = run(git + ["rev-parse", "--abbrev-ref", "@{u}"], check=False).returncode == 0

    fetch_error = ""
    if do_fetch and state["remote"]:
        try:
            p = run(git + ["fetch", "--quiet", "origin"], timeout=FETCH_TIMEOUT, check=False)
            if p.returncode != 0:
                fetch_error = classify_fetch(p.stderr)
        except Busy:
            fetch_error = "offline"
    state["fetch"] = {"time": fetch_head_time(src), "error": fetch_error}

    # status stops chezmoi from running externals or scripts; it only compares.
    status = run([cz, "status", "--exclude=externals"])
    state["local"], state["pending"], state["scripts"] = parse_status(status.stdout)
    state["local"] += new_files(cz, watch_folders(cz))

    state["uncommitted"] = len([l for l in run(git + ["status", "--porcelain"]).stdout.splitlines() if l.strip()])
    fmt = "--format=%x1e%ct%x1f%s"
    if state["upstream"]:
        state["ahead"], state["behind"] = count_ahead_behind(
            run(git + ["rev-list", "--left-right", "--count", "HEAD...@{u}"]).stdout)
        if state["behind"]:
            state["incoming"] = parse_log(run(git + ["log", "-%d" % INCOMING, fmt, "--shortstat", "HEAD..@{u}"]).stdout)
    state["history"] = parse_log(run(git + ["log", "-%d" % HISTORY, fmt, "--shortstat"], check=False).stdout)
    state["ok"] = True
    return state


def main(argv):
    given = None
    if "--chezmoi" in argv:
        i = argv.index("--chezmoi")
        given = argv[i + 1] if i + 1 < len(argv) else None
    cz = find_chezmoi(given)
    if not cz:
        out = {"ok": False, "error": "nochezmoi"}
    else:
        try:
            out = read(cz, "--fetch" in argv)
        except Busy:
            out = {"ok": False, "error": "busy"}
        except Exception:
            out = {"ok": False, "error": "internal"}
    print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv[1:])
