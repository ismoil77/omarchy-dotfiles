#!/usr/bin/env python3
"""Reads the state of a chezmoi setup for the Dotfiles widget.

Prints one JSON object and no human words (the widget owns the texts):

  ok, error      error is "" or nochezmoi / nosource / busy / internal
  host           this machine's name
  remote         "owner/repo" of origin, without any credentials in the URL
  upstream       whether the source branch tracks a remote branch
  local          files changed on this machine and not in the repo yet:
                 [{path, kind}] with kind modified / deleted / added / new, or
                 blocked: Send will leave it out (a folder on its way is not
                 the user's alone)
  pending        files the repo has and this machine has not applied: [{path, kind}]
  scripts        scripts `chezmoi apply` would run
  uncommitted    changed files in the source repo not committed yet
  ahead, behind  commits not pushed / not pulled
  incoming       the commits not pulled, newest first: [{subject, time, files}]
  history        the last commits of the source repo: [{subject, time, files}]
  fetch          {time, error}: when origin was last fetched (0 = never) and
                 why the last try failed ("" / offline / auth / failed)

  state.py [--fetch] [--fresh] [--chezmoi PATH]

--fetch asks origin first (git fetch, no prompts, 25 s at most). Without it an
answer up to 10 s old from another bar is reused; --fresh never reuses.
"""
import fcntl
import json
import os
import re
import shutil
import socket
import stat
import subprocess
import sys
import time

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


def run(cmd, timeout=TIMEOUT, check=True, cwd=None):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=ENV, stdin=subprocess.DEVNULL, cwd=cwd)
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
    # "\n" only: splitlines() also breaks at U+2028, U+0085 and form feeds,
    # which a file name may hold, and would turn one name into forged rows.
    for line in text.split("\n"):
        if len(line) < 4:
            continue
        first, second, path = line[0], line[1], line[3:]
        if second == "R" or first == "R":
            scripts += 1
        elif first != " ":
            local.append({"path": tilde(path), "kind": STATUS_KIND.get(first, "modified")})
        elif second != " ":
            pending.append({"path": tilde(path), "kind": STATUS_KIND.get(second, "modified")})
    return local, pending, scripts


def tilde(path):
    """An absolute path under the home folder as ~/…; a relative one (older
    chezmoi output) is relative to the home folder."""
    home = os.path.expanduser("~")
    if not path.startswith("/"):
        return "~/" + path
    return "~" + path[len(home):] if path == home or path.startswith(home + "/") else path


def owned_alone(path):
    """A folder only its owner can change: ours, not group/other-writable, not a link."""
    try:
        st = os.lstat(path)
    except OSError:
        return False
    return stat.S_ISDIR(st.st_mode) and st.st_uid == os.getuid() and not st.st_mode & 0o022


def sendable(path):
    """Send (actions.sh) takes a file only when every folder from the home
    folder down to it is the user's alone; the widget says so beforehand."""
    home = os.path.expanduser("~")
    path = os.path.expanduser(path)
    if any(ord(c) < 32 for c in path) or not (path.startswith(home + "/")):
        return False
    d = os.path.dirname(path)
    while True:
        if not owned_alone(d):
            return False
        if d == home:
            break
        d = os.path.dirname(d)
    # A new folder is added with everything in it: every folder inside counts too.
    if os.path.isdir(path) and not os.path.islink(path):
        for folder, _, _ in os.walk(path):
            if not owned_alone(folder):
                return False
    return True


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
    """Any remote URL -> "owner/repo", never with a user, token or query in it."""
    url = url.strip()
    url = re.split(r"[?#]", url, maxsplit=1)[0]
    # Everything up to the last @ before the path is credentials (a password may hold an @).
    url = re.sub(r"^([a-z+]+://)[^/]*@", r"\1", url)
    url = re.sub(r"/+$", "", url)
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
    p = run([cz, "unmanaged", "-0", "--path-style=absolute", "--", *folders], check=False)
    out = []
    for line in p.stdout.split("\0"):
        if not line:
            continue
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
    # The repo is git's working directory, not an argument (argv is public to local accounts).
    def g(args, **kw):
        return run(["git", *args], cwd=src, **kw)

    origin = g(["remote", "get-url", "origin"], check=False)
    state["remote"] = short_remote(origin.stdout) if origin.returncode == 0 else ""
    state["upstream"] = g(["rev-parse", "--abbrev-ref", "@{u}"], check=False).returncode == 0

    fetch_error = ""
    # The other bar may have asked a moment ago: one fetch serves both.
    if do_fetch and origin.returncode == 0 and time.time() - fetch_head_time(src) > 30:
        try:
            p = g(["fetch", "--quiet", "origin"], timeout=FETCH_TIMEOUT, check=False)
            if p.returncode != 0:
                fetch_error = classify_fetch(p.stderr)
        except Busy:
            fetch_error = "offline"
    state["fetch"] = {"time": fetch_head_time(src), "error": fetch_error}

    # status does not fetch externals or run scripts; it does render templates
    # (and so calls whatever they call) to know what apply would write.
    status = run([cz, "status", "--exclude=externals", "--path-style=absolute"])
    state["local"], state["pending"], state["scripts"] = parse_status(status.stdout)
    state["local"] += new_files(cz, watch_folders(cz))
    # What Send will leave out (a folder on the way is not the user's alone).
    for row in state["local"]:
        if not sendable(row["path"]):
            row["kind"] = "blocked"

    state["uncommitted"] = len([l for l in g(["status", "--porcelain"]).stdout.splitlines() if l.strip()])
    fmt = "--format=%x1e%ct%x1f%s"
    if state["upstream"]:
        state["ahead"], state["behind"] = count_ahead_behind(
            g(["rev-list", "--left-right", "--count", "HEAD...@{u}"]).stdout)
        if state["behind"]:
            state["incoming"] = parse_log(g(["log", "-%d" % INCOMING, fmt, "--shortstat", "HEAD..@{u}"]).stdout)
    state["history"] = parse_log(g(["log", "-%d" % HISTORY, fmt, "--shortstat"], check=False).stdout)
    state["ok"] = True
    return state


# Every bar (one per monitor) asks at about the same time: an answer this
# fresh is shared. A fetch always reads anew.
SHARED_FOR = 10


def shared_dir():
    """$XDG_RUNTIME_DIR/ismoil-dotfiles, only when it is ours alone (0700, not
    a link): the cached rows later become paths the widget opens."""
    run_dir = os.environ.get("XDG_RUNTIME_DIR")
    if not run_dir:
        return None
    d = os.path.join(run_dir, "ismoil-dotfiles")
    try:
        os.mkdir(d, 0o700)
    except FileExistsError:
        pass
    except OSError:
        return None
    try:
        st = os.lstat(d)
    except OSError:
        return None
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
        return None
    return d


def shared_path():
    d = shared_dir()
    return os.path.join(d, "state.json") if d else None


def read_shared(now):
    path = shared_path()
    try:
        if path and now - os.path.getmtime(path) < SHARED_FOR:
            with open(path) as f:
                return json.load(f)
    except (OSError, ValueError):
        pass
    return None


def write_shared(state):
    path = shared_path()
    if not path or not state.get("ok"):
        return
    tmp = "%s.%d.tmp" % (path, os.getpid())
    try:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump(state, f)
        os.replace(tmp, path)
    except OSError:
        pass


def answer(cz, fetch, fresh):
    """The state, read once for all bars: they ask in the same instant, and a
    lock makes the second one wait and take the first one's answer."""
    d = shared_dir()
    lock = None
    if d:
        try:
            lock = os.open(os.path.join(d, "lock"), os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
            fcntl.flock(lock, fcntl.LOCK_EX)
        except OSError:
            lock = None
    try:
        out = None if fetch or fresh else read_shared(time.time())
        if out is None:
            out = read(cz, fetch)
            write_shared(out)
        return out
    finally:
        if lock is not None:
            os.close(lock)


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
            out = answer(cz, "--fetch" in argv, "--fresh" in argv)
        except Busy:
            out = {"ok": False, "error": "busy"}
        except Exception:
            out = {"ok": False, "error": "internal"}
    print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv[1:])
