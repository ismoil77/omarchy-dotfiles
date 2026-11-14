"""state.py parsers, and state.py + actions.sh end to end on two sandbox machines.

The end-to-end part needs chezmoi and git; it is skipped without them.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)
import state  # noqa: E402

STATE = os.path.join(ROOT, "state.py")
ACTIONS = os.path.join(ROOT, "actions.sh")


def real_chezmoi():
    """The binary itself: a mise shim only works with the real HOME."""
    try:
        out = subprocess.run(["mise", "which", "chezmoi"], capture_output=True, text=True).stdout.strip()
        if out:
            return out
    except OSError:
        pass
    found = shutil.which("chezmoi")
    return found if found and "/shims/" not in found else None


class Parsers(unittest.TestCase):
    def test_status_columns(self):
        local, pending, scripts = state.parse_status(
            "MM .config/a\n M .config/b\n A .config/c\nD  .config/d\n R run_x.sh\n\n")
        self.assertEqual(local, [{"path": "~/.config/a", "kind": "modified"},
                                 {"path": "~/.config/d", "kind": "deleted"}])
        self.assertEqual(pending, [{"path": "~/.config/b", "kind": "modified"},
                                   {"path": "~/.config/c", "kind": "added"}])
        self.assertEqual(scripts, 1)

    def test_status_path_with_spaces(self):
        local, _, _ = state.parse_status("MM Рабочий стол/x y\n")
        self.assertEqual(local[0]["path"], "~/Рабочий стол/x y")

    def test_log(self):
        text = ("\x1e1700000000\x1fsync from pc\n\n 2 files changed, 3 insertions(+)\n"
                "\x1e1690000000\x1finit\n\n 1 file changed, 1 insertion(+)\n"
                "\x1e1680000000\x1fempty\n")
        self.assertEqual(state.parse_log(text), [
            {"subject": "sync from pc", "time": 1700000000, "files": 2},
            {"subject": "init", "time": 1690000000, "files": 1},
            {"subject": "empty", "time": 1680000000, "files": 0}])
        self.assertEqual(state.parse_log(""), [])

    def test_fetch_errors(self):
        self.assertEqual(state.classify_fetch("fatal: unable to access 'https://x': Could not resolve host: github.com"), "offline")
        self.assertEqual(state.classify_fetch("fatal: could not read Username for 'https://github.com'"), "auth")
        self.assertEqual(state.classify_fetch("git@github.com: Permission denied (publickey)."), "auth")
        self.assertEqual(state.classify_fetch("fatal: something odd"), "failed")

    def test_remote_never_shows_credentials(self):
        # Built at run time so secret scanners do not flag this file.
        with_password = "https://user:" + "x" * 12 + "@github.com/me/dotfiles.git\n"
        self.assertEqual(state.short_remote(with_password), "me/dotfiles")
        self.assertEqual(state.short_remote("git@github.com:me/dotfiles.git"), "me/dotfiles")
        self.assertEqual(state.short_remote("https://gitlab.com/group/dots"), "group/dots")
        self.assertEqual(state.short_remote(""), "")

    def test_ahead_behind(self):
        self.assertEqual(state.count_ahead_behind("2\t5\n"), (2, 5))
        self.assertEqual(state.count_ahead_behind(""), (0, 0))


@unittest.skipUnless(real_chezmoi() and shutil.which("git"), "chezmoi and git are needed")
class TwoMachines(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="dotfiles-test ")
        self.cz = real_chezmoi()
        self.remote = os.path.join(self.tmp, "remote.git")
        self.a = self.home("a")
        self.b = self.home("b")
        # Same environment as the machines, so the default branch names match.
        self.sh(self.a, "git", "init", "-q", "--bare", self.remote)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def home(self, name):
        h = os.path.join(self.tmp, name)
        os.makedirs(h)
        return h

    def env(self, home):
        env = {k: v for k, v in os.environ.items() if not k.startswith("XDG_") and not k.startswith("GIT_")}
        # No mise shims (they break with another HOME), so no gitleaks either.
        env["PATH"] = ":".join(p for p in env["PATH"].split(":") if "mise" not in p)
        env.update(HOME=home, CHEZMOI=self.cz, LANG="C", DOTFILES_LANG="en",
                   GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
        return env

    def sh(self, home, *cmd, ok=True):
        p = subprocess.run(list(cmd), env=self.env(home), capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=60)
        if ok and p.returncode != 0:
            self.fail("%s failed: %s %s" % (cmd, p.stdout, p.stderr))
        return p

    def read(self, home, fetch=False):
        args = [sys.executable, "-I", STATE, "--chezmoi", self.cz] + (["--fetch"] if fetch else [])
        return json.loads(self.sh(home, *args).stdout)

    def write(self, home, rel, text):
        path = os.path.join(home, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)

    def test_no_source(self):
        self.assertEqual(self.read(self.a)["error"], "nosource")

    def test_save_on_one_apply_on_the_other(self):
        a, b = self.a, self.b
        # Machine A: one config, a watched skills folder, a first save.
        self.write(a, ".cfg/app.conf", "x=1\n")
        self.write(a, ".skills/one/SKILL.md", "one\n")
        self.sh(a, self.cz, "init")
        src = os.path.join(a, ".local/share/chezmoi")
        self.write(src, ".chezmoidata/dotfiles.toml", '[dotfiles]\nwatch = ["~/.skills"]\n')
        self.sh(a, self.cz, "add", os.path.join(a, ".cfg/app.conf"), os.path.join(a, ".skills/one"))
        self.sh(a, "git", "-C", src, "remote", "add", "origin", self.remote)
        s = self.read(a)
        self.assertTrue(s["ok"], s)
        self.assertEqual(s["uncommitted"], 3)
        self.assertFalse(s["upstream"])
        self.sh(a, ACTIONS, "save")
        s = self.read(a, fetch=True)
        self.assertEqual((s["local"], s["uncommitted"], s["ahead"], s["behind"]), ([], 0, 0, 0), s)
        self.assertTrue(s["upstream"])
        self.assertEqual(s["history"][0]["subject"], "sync from " + s["host"])
        self.assertEqual(s["history"][0]["files"], 3)

        # Machine B starts from the repo.
        self.sh(b, self.cz, "init", "--apply", self.remote)
        with open(os.path.join(b, ".cfg/app.conf")) as f:
            self.assertEqual(f.read(), "x=1\n")

        # A edits a file and adds a skill: both are "not sent".
        self.write(a, ".cfg/app.conf", "x=2\n")
        self.write(a, ".skills/two/SKILL.md", "two\n")
        s = self.read(a)
        self.assertEqual(sorted((r["path"], r["kind"]) for r in s["local"]),
                         [("~/.cfg/app.conf", "modified"), ("~/.skills/two", "new")])
        self.sh(a, ACTIONS, "save")
        self.assertEqual(self.read(a)["local"], [])

        # B sees one incoming save after a fetch, and nothing before it.
        self.assertEqual(self.read(b)["behind"], 0)
        s = self.read(b, fetch=True)
        self.assertEqual(s["behind"], 1)
        self.assertEqual(s["incoming"][0]["files"], 2)
        self.assertEqual(s["fetch"]["error"], "")
        self.sh(b, ACTIONS, "apply")
        s = self.read(b)
        self.assertEqual((s["behind"], s["pending"], s["local"]), (0, [], []), s)
        with open(os.path.join(b, ".skills/two/SKILL.md")) as f:
            self.assertEqual(f.read(), "two\n")

    def test_both_machines_saved_different_files(self):
        a, b = self.a, self.b
        self.write(a, ".cfg/one", "1\n")
        self.write(a, ".cfg/two", "2\n")
        self.sh(a, self.cz, "init")
        src = os.path.join(a, ".local/share/chezmoi")
        self.sh(a, self.cz, "add", os.path.join(a, ".cfg"))
        self.sh(a, "git", "-C", src, "remote", "add", "origin", self.remote)
        self.sh(a, ACTIONS, "save")
        self.sh(b, self.cz, "init", "--apply", self.remote)

        self.write(a, ".cfg/one", "1a\n")
        self.sh(a, ACTIONS, "save")
        self.write(b, ".cfg/two", "2b\n")
        # B's save puts its commit on top of A's instead of failing the push.
        self.sh(b, ACTIONS, "save")
        s = self.read(b, fetch=True)
        self.assertEqual((s["ahead"], s["behind"]), (0, 0), s)
        self.assertEqual(s["pending"], [{"path": "~/.cfg/one", "kind": "modified"}])
        self.sh(b, ACTIONS, "apply")
        with open(os.path.join(b, ".cfg/one")) as f:
            self.assertEqual(f.read(), "1a\n")

    def test_offline_fetch_is_reported_not_fatal(self):
        a = self.a
        self.write(a, ".cfg/one", "1\n")
        self.sh(a, self.cz, "init")
        src = os.path.join(a, ".local/share/chezmoi")
        self.sh(a, self.cz, "add", os.path.join(a, ".cfg/one"))
        self.sh(a, "git", "-C", src, "remote", "add", "origin", "https://127.0.0.1:9/nobody/none.git")
        s = self.read(a, fetch=True)
        self.assertTrue(s["ok"])
        self.assertEqual(s["fetch"]["error"], "offline")
        self.assertEqual(s["remote"], "nobody/none")


if __name__ == "__main__":
    unittest.main()
