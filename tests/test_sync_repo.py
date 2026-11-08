#!/usr/bin/env python3
"""Exercise deployment against local Git repositories without network access."""

import os
import json
import errno
import pty
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / ".deploy/sync_repo_from_git.sh"


class SyncRepoTest(unittest.TestCase):
    def run_cmd(self, *args, cwd=None, check=True, env=None, input=None):
        result = subprocess.run(args, cwd=cwd, env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=30, input=input)
        if check and result.returncode:
            self.fail(result.stdout + result.stderr)
        return result

    def git(self, path, *args):
        return self.run_cmd("git", *args, cwd=path).stdout.strip()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.remote = self.root / "remote.git"
        self.source = self.root / "source"
        self.run_cmd("git", "init", "--bare", str(self.remote))
        self.run_cmd("git", "init", "-b", "main", str(self.source))
        self.git(self.source, "config", "user.email", "test@example.invalid")
        self.git(self.source, "config", "user.name", "Sync Repo Test")
        (self.source / "public_html/include").mkdir(parents=True)
        (self.source / "public_html/include/app.php").write_text("old\n")
        (self.source / ".gitignore").write_text(
            "/public_html/upload/\n/public_html/bitrix/.settings.php\n")
        self.git(self.source, "add", ".")
        self.git(self.source, "commit", "-m", "Initial")
        self.git(self.source, "remote", "add", "origin", str(self.remote))
        self.git(self.source, "push", "-u", "origin", "main")
        self.git(self.remote, "symbolic-ref", "HEAD", "refs/heads/main")
        self.base = self.git(self.source, "rev-parse", "HEAD")
        (self.source / "public_html/include/app.php").write_text("new\n")
        self.git(self.source, "commit", "-am", "Update")
        self.git(self.source, "push")
        self.env = dict(os.environ)
        for key in list(self.env):
            if key.startswith(("GIT_", "SYNC_REPO_")):
                self.env.pop(key)
        self.env.update(SYNC_REPO_AUTO_UPDATE="0", GIT_CLEAN="1")

    def fixture(self, name="project", fresh=False):
        project = self.root / name
        if fresh:
            project.mkdir()
        else:
            self.run_cmd("git", "clone", str(self.remote), str(project))
            self.git(project, "reset", "--hard", self.base)
        (project / ".deploy").mkdir()
        shutil.copy2(SCRIPT, project / ".deploy/sync_repo_from_git.sh")
        (project / ".deploy/sync_repo_from_git.conf").write_text(
            f"REPOSITORY_URL={self.remote}\nREMOTE=origin\nBRANCH=main\n"
            "AUTH_MODE=basic\nAUTH_USERNAME=test\nAUTH_SECRET=test\n")
        (project / "public_html/upload").mkdir(parents=True)
        (project / "public_html/upload/photo.jpg").write_bytes(b"photo")
        (project / "public_html/bitrix").mkdir()
        (project / "public_html/bitrix/.settings.php").write_text("local secret")
        (project / "public_html/.htaccess").write_text("local rules")
        return project

    def deploy(self, project, env=None):
        return self.run_cmd("bash", ".deploy/sync_repo_from_git.sh", "--auto",
                            cwd=project, env=env or self.env, check=False)

    def assert_runtime(self, project):
        self.assertEqual((project / "public_html/upload/photo.jpg").read_bytes(), b"photo")
        self.assertEqual((project / "public_html/bitrix/.settings.php").read_text(), "local secret")
        self.assertEqual((project / "public_html/.htaccess").read_text(), "local rules")
        self.assertTrue((project / ".deploy/sync_repo_from_git.sh").is_file())
        self.assertTrue((project / ".deploy/sync_repo_from_git.conf").is_file())

    def interactive_deploy(self, project, answer, env=None):
        return self.run_cmd("bash", ".deploy/sync_repo_from_git.sh", cwd=project,
                            env=env or self.env, check=False, input="1\n" + answer)

    def test_confirmation_restores_repo_and_backs_up_worktree_and_index(self):
        project = self.fixture()
        local_file = project / "public_html/include/app.php"
        local_file.write_text("staged logo\n")
        self.git(project, "add", "public_html/include/app.php")
        local_file.write_text("working logo\n")
        result = self.interactive_deploy(project, "1\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        worktree = result.stdout.index("Изменения в рабочих файлах")
        staged = result.stdout.index("Изменения, подготовленные через git add")
        prompt = result.stdout.index("Заменить эти правки версией origin/main?")
        self.assertIn("-staged logo\n+working logo", result.stdout[worktree:staged])
        self.assertIn("-old\n+staged logo", result.stdout[staged:prompt])
        self.assertEqual(local_file.read_text(), "new\n")
        refs = self.git(project, "for-each-ref", "--format=%(refname)", "refs/sync-repo/backups/").splitlines()
        self.assertEqual(len(refs), 1)
        self.assertEqual(self.git(project, "show", refs[0] + ":public_html/include/app.php"), "working logo")
        self.assertEqual(self.git(project, "show", refs[0] + "^2:public_html/include/app.php"), "staged logo")
        self.assert_runtime(project)

    def test_diff_shows_only_nonempty_sections_before_decline(self):
        for staged in (False, True):
            with self.subTest(staged=staged):
                project = self.fixture(name=f"diff-{staged}")
                local_file = project / "public_html/include/app.php"
                local_file.write_text("local logo\n")
                if staged:
                    self.git(project, "add", "public_html/include/app.php")
                result = self.interactive_deploy(project, "2\n")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                prompt = result.stdout.index("Заменить эти правки версией origin/main?")
                self.assertIn("-old\n+local logo", result.stdout[:prompt])
                self.assertEqual("Изменения в рабочих файлах" in result.stdout, not staged)
                self.assertEqual("Изменения, подготовленные через git add" in result.stdout, staged)
                self.assertEqual(local_file.read_text(), "local logo\n")
                self.assertEqual(self.git(project, "rev-parse", "HEAD"), self.base)

    def test_diff_does_not_run_external_diff_textconv_or_pager(self):
        project = self.fixture()
        helper = self.root / "diff-helper"
        marker = self.root / "diff-helper-called"
        helper.write_text(f'#!/bin/sh\ntouch "{marker}"\nexit 1\n')
        helper.chmod(0o755)
        self.git(project, "config", "diff.external", str(helper))
        self.git(project, "config", "core.pager", str(helper))
        self.git(project, "config", "diff.custom.textconv", str(helper))
        (project / ".git/info/attributes").write_text("*.php diff=custom\n")
        (project / "public_html/include/app.php").write_text("local logo\n")
        result = self.interactive_deploy(project, "2\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("-old\n+local logo", result.stdout)
        self.assertFalse(marker.exists())

    def test_decline_empty_input_or_eof_preserves_local_edits(self):
        for answer in ("2\n", "\n", ""):
            with self.subTest(answer=answer):
                project = self.fixture(name="decline-" + str(len(list(self.root.glob('decline-*')))))
                local_file = project / "public_html/include/app.php"
                local_file.write_text("local logo\n")
                result = self.interactive_deploy(project, answer)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(local_file.read_text(), "local logo\n")
                self.assertEqual(self.git(project, "rev-parse", "HEAD"), self.base)
                self.assertEqual(self.git(project, "for-each-ref", "refs/sync-repo/backups/"), "")
                self.assert_runtime(project)

    def test_confirmed_staged_addition_is_preserved_in_backup(self):
        project = self.fixture()
        path = project / "public_html/local-only.php"
        path.write_text("local addition")
        self.git(project, "add", "public_html/local-only.php")
        result = self.interactive_deploy(project, "1\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(path.exists())
        ref = self.git(project, "for-each-ref", "--format=%(refname)", "refs/sync-repo/backups/")
        self.assertEqual(self.git(project, "show", ref + ":public_html/local-only.php"), "local addition")
        self.assert_runtime(project)

    def test_backup_failure_does_not_reset_edits(self):
        project = self.fixture()
        local_file = project / "public_html/include/app.php"
        local_file.write_text("local logo\n")
        directory = self.root / "mock-git"
        directory.mkdir()
        wrapper = directory / "git"
        real_git = shutil.which("git")
        wrapper.write_text('#!/usr/bin/env bash\n'
                           'if [[ ${1:-} == stash && ${2:-} == create ]]; then exit 1; fi\n'
                           'exec "$REAL_GIT" "$@"\n')
        wrapper.chmod(0o755)
        env = dict(self.env, REAL_GIT=real_git)
        env["PATH"] = str(directory) + os.pathsep + env["PATH"]
        result = self.interactive_deploy(project, "1\n", env)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(local_file.read_text(), "local logo\n")
        self.assertEqual(self.git(project, "rev-parse", "HEAD"), self.base)
        self.assert_runtime(project)

    def test_update_preserves_runtime_even_with_clean_requested(self):
        project = self.fixture()
        result = self.deploy(project)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((project / "public_html/include/app.php").read_text(), "new\n")
        self.assert_runtime(project)

    def test_terminal_sync_never_opens_git_pager(self):
        # A pipe hides this bug: Git starts its pager only with a terminal on stdout.
        for setting in ("core.pager", "pager.log", "GIT_PAGER"):
            with self.subTest(setting=setting):
                project = self.fixture(name="pager-" + setting)
                marker = self.root / (setting + "-called")
                pager = self.root / (setting + "-pager")
                pager.write_text(f'#!/bin/sh\ntouch "{marker}"\ncat\n')
                pager.chmod(0o755)
                env = dict(self.env, TERM="xterm")
                if setting == "GIT_PAGER":
                    env["GIT_PAGER"] = str(pager)
                else:
                    self.git(project, "config", setting, str(pager))
                master, slave = pty.openpty()
                chunks = []

                def read_terminal():
                    while True:
                        try:
                            chunk = os.read(master, 65536)
                        except OSError as error:
                            if error.errno == errno.EIO:
                                break
                            raise
                        if not chunk:
                            break
                        chunks.append(chunk)

                reader = threading.Thread(target=read_terminal, daemon=True)
                reader.start()
                try:
                    with subprocess.Popen(
                            ["bash", ".deploy/sync_repo_from_git.sh", "--auto"],
                            cwd=project, env=env, stdin=subprocess.DEVNULL,
                            stdout=slave, stderr=slave) as process:
                        os.close(slave)
                        slave = None
                        try:
                            returncode = process.wait(timeout=20)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
                            self.fail("Synchronization waited for a terminal pager")
                    reader.join(timeout=5)
                    self.assertFalse(reader.is_alive(), "Terminal did not close")
                finally:
                    if slave is not None:
                        os.close(slave)
                    os.close(master)
                output = b"".join(chunks).decode(errors="replace")
                self.assertEqual(returncode, 0, output)
                self.assertFalse(marker.exists(), output)
                self.assertIn("Update", output)
                self.assertEqual((project / "public_html/include/app.php").read_text(), "new\n")
                self.assert_runtime(project)

    def test_first_install_preserves_existing_runtime(self):
        project = self.fixture(fresh=True)
        result = self.deploy(project)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((project / "public_html/include/app.php").read_text(), "new\n")
        self.assert_runtime(project)

    def legacy_git_env(self, passthrough=False):
        """Emulate unsupported Git options while using real local repositories."""
        directory = self.root / "legacy-bin"
        directory.mkdir(exist_ok=True)
        wrapper = directory / "git"
        wrapper.write_text(
            '#!/usr/bin/env bash\n'
            'if [[ ${1:-} == rev-parse && ${2:-} == --git-path ]]; then\n'
            '  printf "%s\\n" --git-path\n'
            '  if [[ $LEGACY_PASSTHROUGH == 1 ]]; then printf "%s\\n" "$3"; exit 0; fi\n'
            '  echo "fatal: ambiguous argument info/exclude" >&2; exit 128\n'
            'fi\n'
            'if [[ ${1:-} == remote && ${2:-} == get-url ]]; then exit 129; fi\n'
            'if [[ ${1:-} == --list-cmds=* || ${1:-} == restore ]]; then exit 129; fi\n'
            '# Old Git ignores GIT_SSH_COMMAND; exercise its GIT_SSH replacement.\n'
            'if [[ " $* " == *" fetch "* && -n ${SYNC_SSH_PRIVATE_KEY:-} ]]; then\n'
            '  unset GIT_SSH_COMMAND\n'
            '  if [[ $GIT_SSH == "${NOEXEC_DIR:-/nonexistent}/"* ]]; then exit 126; fi\n'
            '  "$GIT_SSH" git@example.invalid git-upload-pack || exit $?\n'
            'fi\n'
            'exec "$REAL_GIT" "$@"\n')
        wrapper.chmod(0o755)
        env = dict(self.env, REAL_GIT=shutil.which("git"),
                   LEGACY_PASSTHROUGH=str(int(passthrough)))
        env["PATH"] = str(directory) + os.pathsep + env["PATH"]
        return env

    def test_legacy_git_first_install_and_repeat_preserve_runtime(self):
        for passthrough in (False, True):
            with self.subTest(passthrough=passthrough):
                project = self.fixture(name=f"legacy-{passthrough}", fresh=True)
                env = self.legacy_git_env(passthrough)
                for _ in range(2):
                    result = self.deploy(project, env)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual((project / "public_html/include/app.php").read_text(), "new\n")
                    self.assertIn("/.deploy/sync_repo_from_git.conf",
                                  (project / ".git/info/exclude").read_text())
                    self.assertFalse((project / "--git-path").exists())
                    self.assert_runtime(project)

    def test_legacy_git_keeps_edits_when_restore_is_unavailable(self):
        project = self.fixture()
        local_file = project / "public_html/include/app.php"
        local_file.write_text("local edit\n")
        result = self.interactive_deploy(project, "1\n", self.legacy_git_env())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Git 2.23", result.stderr)
        self.assertEqual(local_file.read_text(), "local edit\n")
        self.assertEqual(self.git(project, "rev-parse", "HEAD"), self.base)
        self.assertEqual(self.git(project, "for-each-ref", "refs/sync-repo/backups/"), "")
        self.assert_runtime(project)

    def test_legacy_git_ssh_uses_selected_key_and_removes_wrapper(self):
        project = self.fixture(fresh=True)
        key = project / ".deploy/key with spaces"
        key.write_text("test key")
        (project / ".deploy/sync_repo_from_git.conf").write_text(
            f"REPOSITORY_URL={self.remote}\nREMOTE=origin\nBRANCH=main\n"
            f"AUTH_MODE=ssh\nSSH_PRIVATE_KEY={key}\n")
        env = self.legacy_git_env()
        ssh = self.root / "legacy-bin/ssh"
        ssh.write_text('#!/usr/bin/env python3\nimport json, os, sys\n'
                       'open(os.environ["SSH_MARKER"], "w").write(json.dumps({"args":sys.argv[1:], "helper":os.environ["GIT_SSH"]}))\n'
                       'sys.exit(int(os.environ.get("SSH_EXIT_CODE", "0")))\n')
        ssh.chmod(0o755)
        marker = self.root / "ssh-args"
        noexec = self.root / "noexec-tmp"
        noexec.mkdir()
        env.update(SSH_MARKER=str(marker), TMPDIR=str(noexec), NOEXEC_DIR=str(noexec))
        result = self.deploy(project, env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        record = json.loads(marker.read_text())
        args = record["args"]
        self.assertEqual(Path(record["helper"]).parent, project / ".deploy")
        self.assertFalse(Path(record["helper"]).exists())
        self.assertEqual(args[:2], ["-i", str(key)])
        self.assertIn("IdentitiesOnly=yes", args)
        self.assertIn("StrictHostKeyChecking=accept-new", args)
        self.assertEqual(args[-2:], ["git@example.invalid", "git-upload-pack"])
        self.assertEqual(list(self.root.glob("sync-repo-ssh.*")), [])
        self.assertEqual(list(noexec.iterdir()), [])
        self.assertEqual(list((project / ".deploy").glob(".sync-repo-ssh.*")), [])
        # The EXIT trap must also remove the helper after a failed SSH fetch.
        result = self.deploy(project, dict(env, SSH_EXIT_CODE="1"))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list((project / ".deploy").glob(".sync-repo-ssh.*")), [])
        self.assertEqual((project / "public_html/include/app.php").read_text(), "new\n")
        self.assert_runtime(project)

    def test_askpass_avoids_noexec_tmp_and_is_cleaned(self):
        project = self.fixture(fresh=True)
        config = project / ".deploy/sync_repo_from_git.conf"
        config.write_text(config.read_text().replace(str(self.remote), "https://example.invalid/repo.git"))
        directory = self.root / "askpass-bin"
        directory.mkdir()
        wrapper = directory / "git"
        wrapper.write_text(
            '#!/usr/bin/env bash\nset -euo pipefail\n'
            'if [[ " $* " == *" fetch "* ]]; then\n'
            '  [[ $GIT_ASKPASS != "$TMPDIR/"* ]] || exit 126\n'
            '  [[ $("$GIT_ASKPASS" Username) == test ]]\n'
            '  [[ $("$GIT_ASKPASS" Password) == test ]]\n'
            '  "$REAL_GIT" check-ignore -- "$GIT_ASKPASS" >/dev/null\n'
            '  printf "%s\\n" "$GIT_ASKPASS" > "$HELPER_MARKER"\n'
            '  [[ ${FAIL_FETCH:-0} == 0 ]] || exit 1\n'
            '  exec "$REAL_GIT" fetch --prune "$LOCAL_REMOTE" "+refs/heads/*:refs/remotes/origin/*"\n'
            'fi\nexec "$REAL_GIT" "$@"\n')
        wrapper.chmod(0o755)
        noexec = self.root / "noexec-tmp"
        noexec.mkdir()
        marker = self.root / "askpass-path"
        env = dict(self.env, REAL_GIT=shutil.which("git"), LOCAL_REMOTE=str(self.remote),
                   HELPER_MARKER=str(marker), TMPDIR=str(noexec))
        env["PATH"] = str(directory) + os.pathsep + env["PATH"]
        for fail_fetch in ("0", "1"):
            result = self.deploy(project, dict(env, FAIL_FETCH=fail_fetch))
            self.assertEqual(result.returncode == 0, fail_fetch == "0", result.stdout + result.stderr)
            helper = Path(marker.read_text().strip())
            self.assertEqual(helper.parent, project / ".deploy")
            self.assertFalse(helper.exists())
            self.assertEqual(list(noexec.iterdir()), [])
            self.assertEqual((project / "public_html/include/app.php").read_text(), "new\n")
            self.assert_runtime(project)

    def test_linked_worktree_uses_common_excludes(self):
        main_project = self.root / "main-project"
        self.run_cmd("git", "clone", str(self.remote), str(main_project))
        self.git(main_project, "checkout", "--detach")
        project = self.root / "linked-project"
        self.git(main_project, "worktree", "add", "-b", "deployment", str(project), self.base)
        (project / ".deploy").mkdir()
        shutil.copy2(SCRIPT, project / ".deploy/sync_repo_from_git.sh")
        (project / ".deploy/sync_repo_from_git.conf").write_text(
            f"REPOSITORY_URL={self.remote}\nREMOTE=origin\nBRANCH=main\n"
            "AUTH_MODE=basic\nAUTH_USERNAME=test\nAUTH_SECRET=test\n")
        result = self.deploy(project)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("/.deploy/sync_repo_from_git.conf",
                      (main_project / ".git/info/exclude").read_text())
        self.assertEqual((project / "public_html/include/app.php").read_text(), "new\n")

    def test_local_edits_are_not_lost(self):
        for staged in (False, True):
            with self.subTest(staged=staged):
                project = self.fixture(name=f"project-{staged}")
                local_file = project / "public_html/include/app.php"
                local_file.write_text("local logo\n")
                if staged:
                    self.git(project, "add", "public_html/include/app.php")
                self.assertNotEqual(self.deploy(project).returncode, 0)
                self.assertEqual(local_file.read_text(), "local logo\n")
                self.assertEqual(self.git(project, "rev-parse", "HEAD"), self.base)
                self.assert_runtime(project)

    def test_unpublished_commits_are_not_reset(self):
        project = self.fixture()
        self.git(project, "config", "user.email", "test@example.invalid")
        self.git(project, "config", "user.name", "Sync Repo Test")
        (project / "local.txt").write_text("local")
        self.git(project, "add", "local.txt")
        self.git(project, "commit", "-m", "Local commit")
        head = self.git(project, "rev-parse", "HEAD")
        self.assertNotEqual(self.deploy(project).returncode, 0)
        self.assertEqual(self.git(project, "rev-parse", "HEAD"), head)

    def test_path_collisions_preserve_untracked_and_ignored_files(self):
        for ignored in (False, True):
            with self.subTest(ignored=ignored):
                self.git(self.source, "reset", "--hard", self.base)
                target = "public_html/bitrix/.settings.php" if ignored else "public_html/.htaccess"
                path = self.source / target
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("remote replacement")
                self.git(self.source, "add", "-f", target)
                self.git(self.source, "commit", "-m", "Colliding path")
                self.git(self.source, "push", "--force", "origin", "main")
                project = self.fixture(name=f"collision-{ignored}")
                self.assertNotEqual(self.deploy(project).returncode, 0)
                self.assertEqual(self.git(project, "rev-parse", "HEAD"), self.base)
                self.assert_runtime(project)

    def mock_curl(self, payload):
        directory = self.root / "bin"
        directory.mkdir()
        curl = directory / "curl"
        curl.write_text("#!/usr/bin/env bash\nset -euo pipefail\n"
                        "while (( $# )); do\n"
                        "  if [[ $1 == -o ]]; then cp -- \"$MOCK_UPDATE_CONTENT\" \"$2\"; exit 0; fi\n"
                        "  shift\ndone\nexit 1\n")
        curl.chmod(0o755)
        env = dict(self.env, SYNC_REPO_AUTO_UPDATE="1",
                   MOCK_UPDATE_CONTENT=str(payload))
        env["PATH"] = str(directory) + os.pathsep + env["PATH"]
        return env

    def test_confirmed_self_update_restarts_new_script(self):
        project = self.fixture()
        payload = self.root / "updated.sh"
        payload.write_text(SCRIPT.read_text().replace(
            'SCRIPT_VERSION="1.4.5"', 'SCRIPT_VERSION="1.4.6"', 1).replace(
            "set -Eeuo pipefail", 'set -Eeuo pipefail\nprintf \'%s\\n\' "$*" > "$UPDATE_MARKER"', 1))
        env = self.mock_curl(payload)
        marker = self.root / "update-marker"
        env["UPDATE_MARKER"] = str(marker)
        result = self.interactive_deploy(project, "1\n", env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(marker.read_text(), "\n")
        self.assertEqual((project / ".deploy/sync_repo_from_git.sh").read_text(), payload.read_text())
        self.assertEqual(list((project / ".deploy").glob(".sync-repo-update.*")), [])
        self.assert_runtime(project)

    def test_declined_self_update_continues_with_installed_script(self):
        for answer in ("2\n", "\n"):
            with self.subTest(answer=answer):
                project = self.fixture(name="skip-update-" + str(len(list(self.root.glob('skip-update-*')))))
                payload = self.root / "new-version.sh"
                payload.write_text(SCRIPT.read_text().replace('SCRIPT_VERSION="1.4.5"', 'SCRIPT_VERSION="1.4.6"', 1))
                env = self.mock_curl(payload)
                result = self.run_cmd("bash", ".deploy/sync_repo_from_git.sh", cwd=project,
                                      env=env, check=False, input=answer + "1\n")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((project / ".deploy/sync_repo_from_git.sh").read_text(), SCRIPT.read_text())
                self.assertEqual((project / "public_html/include/app.php").read_text(), "new\n")
                self.assertEqual(list((project / ".deploy").glob(".sync-repo-update.*")), [])
                self.assert_runtime(project)
                shutil.rmtree(self.root / "bin")

    def test_auto_mode_reports_update_without_installing_or_waiting(self):
        project = self.fixture()
        payload = self.root / "new-version.sh"
        payload.write_text(SCRIPT.read_text().replace('SCRIPT_VERSION="1.4.5"', 'SCRIPT_VERSION="1.4.6"', 1))
        result = self.deploy(project, self.mock_curl(payload))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("1.4.6", result.stdout)
        self.assertEqual((project / ".deploy/sync_repo_from_git.sh").read_text(), SCRIPT.read_text())
        self.assertEqual((project / "public_html/include/app.php").read_text(), "new\n")
        self.assert_runtime(project)

    def test_same_or_older_version_is_not_installed(self):
        for version in ("1.4.5", "1.3.10"):
            with self.subTest(version=version):
                project = self.fixture(name="version-" + version)
                payload = self.root / "other-version.sh"
                payload.write_text(SCRIPT.read_text().replace('SCRIPT_VERSION="1.4.5"', 'SCRIPT_VERSION="' + version + '"', 1) + "\n# changed payload\n")
                result = self.interactive_deploy(project, "", self.mock_curl(payload))
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn("Доступна новая версия", result.stdout)
                self.assertEqual((project / ".deploy/sync_repo_from_git.sh").read_text(), SCRIPT.read_text())
                self.assert_runtime(project)
                shutil.rmtree(self.root / "bin")

    def test_eof_at_update_prompt_does_not_install_download(self):
        project = self.fixture()
        payload = self.root / "new-version.sh"
        payload.write_text(SCRIPT.read_text().replace('SCRIPT_VERSION="1.4.5"', 'SCRIPT_VERSION="1.4.6"', 1))
        result = self.run_cmd("bash", ".deploy/sync_repo_from_git.sh", cwd=project,
                              env=self.mock_curl(payload), check=False, input="")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((project / ".deploy/sync_repo_from_git.sh").read_text(), SCRIPT.read_text())
        self.assertEqual(self.git(project, "rev-parse", "HEAD"), self.base)
        self.assert_runtime(project)

    def test_invalid_self_update_does_not_replace_script(self):
        project = self.fixture()
        payload = self.root / "invalid.sh"
        payload.write_text("#!/usr/bin/env bash\nif then\n")
        result = self.deploy(project, self.mock_curl(payload))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((project / ".deploy/sync_repo_from_git.sh").read_text(), SCRIPT.read_text())
        self.assertEqual(list((project / ".deploy").glob(".sync-repo-update.*")), [])
        self.assert_runtime(project)

    FAKE_GH = """#!/usr/bin/env bash
echo "gh $* [token=${GH_TOKEN:-}]" >> "$FAKE_GH_LOG"
case "$1" in
  --version) echo "gh version 0.0.0" ;;
  secret)
    if [[ "${FAKE_GH_FAIL_SECRET:-}" == "$3" ]]; then exit 1; fi
    echo "SECRET $3 <<$(cat)>>" >> "$FAKE_GH_LOG" ;;
  api)
    if [[ -n "${FAKE_GH_API_ERROR:-}" ]]; then echo "$FAKE_GH_API_ERROR" >&2; exit 1; fi
    for a in "$@"; do
      if [[ "$a" == "PUT" ]]; then echo "PUT $*" >> "$FAKE_GH_LOG"; fi
    done ;;
esac
exit 0
"""

    def wizard(self, answers, extra_env=None):
        project = self.fixture()
        self.git(project, "remote", "set-url", "origin", "git@github.com:acme/site.git")
        fake = self.root / "fake_gh"
        fake.write_text(self.FAKE_GH)
        fake.chmod(0o755)
        log = self.root / "gh.log"
        home = self.root / "home"
        home.mkdir()
        tools = self.root / "fake_tools"
        tools.mkdir()
        (tools / "ssh-keygen").write_text(
            "#!/usr/bin/env bash\n"
            "while [[ $# -gt 0 ]]; do [[ $1 == -f ]] && f=$2; shift; done\n"
            "printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\\nFAKEKEY\\n-----END OPENSSH PRIVATE KEY-----\\n' > \"$f\"\n"
            "echo 'ssh-ed25519 AAAAFAKE test' > \"$f.pub\"\n")
        (tools / "ssh-keyscan").write_text("#!/usr/bin/env bash\necho '127.0.0.1 ssh-ed25519 AAAAHOST'\n")
        (tools / "ssh").write_text("#!/usr/bin/env bash\nexit 1\n")
        for tool in tools.iterdir():
            tool.chmod(0o755)
        env = dict(self.env, HOME=str(home), SYNC_REPO_GH_BIN=str(fake), FAKE_GH_LOG=str(log),
                   PATH=str(tools) + os.pathsep + self.env["PATH"])
        env.pop("GH_TOKEN", None)
        env.pop("GITHUB_TOKEN", None)
        env.update(extra_env or {})
        # меню: 3 → хост, порт, пользователь, путь, затем ответы мастера
        result = self.run_cmd("bash", ".deploy/sync_repo_from_git.sh", cwd=project, env=env,
                              check=False, input="3\n127.0.0.1\n9\nsiteuser\n/srv/site\n" + answers + "\n4\n")
        return project, result, (log.read_text() if log.exists() else "")

    def test_wizard_configures_github_automatically_without_manual_copy(self):
        project, result, log = self.wizard("y\nghp_secret_token\n\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name in ("DEPLOY_HOST", "DEPLOY_PORT", "DEPLOY_USER", "DEPLOY_PATH",
                     "DEPLOY_KNOWN_HOSTS", "DEPLOY_SSH_KEY"):
            self.assertIn("SECRET " + name, log)
        self.assertIn("SECRET DEPLOY_HOST <<127.0.0.1>>", log)
        self.assertIn("SECRET DEPLOY_USER <<siteuser>>", log)
        self.assertIn("-----BEGIN OPENSSH PRIVATE KEY-----", log)
        self.assertIn("repos/acme/site/contents/.github/workflows/deploy.yml", log)
        self.assertIn("branch=main", log)
        # ручной вывод секретов не показывается, токен не утёк в вывод и файлы
        self.assertNotIn("BEGIN DEPLOY_SSH_KEY", result.stdout)
        self.assertNotIn("ghp_secret_token", result.stdout + result.stderr)
        for path in project.rglob("*"):
            if path.is_file() and ".git/" not in str(path):
                self.assertNotIn("ghp_secret_token", path.read_text(errors="ignore"), str(path))
        # локальная копия workflow убрана, чтобы не блокировать будущий pull
        self.assertFalse((project / ".github/workflows/deploy.yml").exists())

    def test_wizard_falls_back_to_manual_instructions_on_failure(self):
        project, result, log = self.wizard("y\nghp_secret_token\n\n",
                                          {"FAKE_GH_FAIL_SECRET": "DEPLOY_USER"})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Автонастройка не удалась", result.stdout + result.stderr)
        self.assertIn("DEPLOY_SSH_KEY — КОПИРУЙТЕ ТОЛЬКО ЖЁЛТЫЙ БЛОК", result.stdout)
        self.assertTrue((project / ".github/workflows/deploy.yml").exists())

    def test_wizard_shows_github_error_and_trims_token(self):
        project, result, log = self.wizard("y\n  ghp_bad_token \n\n",
                                          {"FAKE_GH_API_ERROR": "gh: Not Found (HTTP 404)"})
        out = result.stdout + result.stderr
        self.assertIn("Ответ GitHub: gh: Not Found (HTTP 404)", out)
        self.assertIn("[token=ghp_bad_token]", log)
        self.assertNotIn("ghp_bad_token", out)

    def test_wizard_manual_choice_skips_github_cli(self):
        project, result, log = self.wizard("n\n\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("SECRET", log)
        self.assertIn("DEPLOY_SSH_KEY — КОПИРУЙТЕ ТОЛЬКО ЖЁЛТЫЙ БЛОК", result.stdout)

    def test_github_slug_parsing(self):
        script = (str(SCRIPT))
        cases = {
            "https://github.com/acme/site.git": "acme/site",
            "git@github.com:acme/site.git": "acme/site",
            "git@github-site:acme/site": "acme/site",
            "ssh://git@github.com/acme/site.git": "acme/site",
            "https://user:tok@github.com/acme/site": "acme/site",
        }
        func = subprocess.run(["bash", "-c", "sed -n '/^github_slug_from_url()/,/^}/p' " + script],
                              text=True, capture_output=True).stdout
        for url, slug in cases.items():
            out = self.run_cmd("bash", "-c", func + '\ngithub_slug_from_url "$1"', "x", url).stdout.strip()
            self.assertEqual(out, slug, url)


    def test_gh_install_falls_back_when_project_dir_is_noexec(self):
        # gh из .deploy/bin «не запускается» (имитация noexec) — берётся каталог в $HOME
        tools = self.root / "fake_tools"
        tools.mkdir()
        pkg = self.root / "pkg/gh_2.89.0_linux_amd64/bin"
        pkg.mkdir(parents=True)
        (pkg / "gh").write_text(
            "#!/usr/bin/env bash\ncase \"$0\" in */cfg/bin/*) echo 'noexec' >&2; exit 126;; esac\n"
            "echo 'gh version 2.89.0'\n")
        (pkg / "gh").chmod(0o755)
        tarball = self.root / "gh.tar.gz"
        self.run_cmd("tar", "-czf", str(tarball), "-C", str(self.root / "pkg"), "gh_2.89.0_linux_amd64")
        (tools / "curl").write_text(
            "#!/usr/bin/env bash\nwhile [[ $# -gt 0 ]]; do [[ $1 == -o ]] && o=$2; shift; done\n"
            f"cp {tarball} \"$o\"\n")
        (tools / "curl").chmod(0o755)
        cfg = self.root / "cfg"
        cfg.mkdir()
        home = self.root / "home2"
        home.mkdir()
        func = subprocess.run(["bash", "-c", "sed -n '/^limit_go_threads()/,/^}/p;/^gh_runs()/,/^}/p;/^ensure_gh_cli()/,/^}/p' " + str(SCRIPT)],
                              text=True, capture_output=True).stdout
        env = dict(self.env, HOME=str(home), PATH=str(tools) + os.pathsep + "/usr/bin:/bin")
        env.pop("SYNC_REPO_GH_BIN", None)
        result = self.run_cmd("bash", "-c",
                              f"GH_BIN=''; GH_CLI_VERSION=2.89.0; PROJECT_CONFIG_DIR={cfg}\n{func}\n"
                              'ensure_gh_cli && echo "BIN=$GH_BIN"', env=env, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"BIN={home}/.local/bin/gh", result.stdout)
        self.assertIn("не запускается: noexec", result.stderr)
        self.assertFalse((cfg / "bin/gh").exists())
        self.assertEqual(list(cfg.glob(".sync-repo-gh.*")), [])


    def test_gh_install_retries_with_single_thread_limit(self):
        # gh «падает» без GOMAXPROCS=1 (лимит потоков хостинга) — скрипт включает его сам
        tools = self.root / "fake_tools2"
        tools.mkdir()
        pkg = self.root / "pkg2/gh_2.89.0_linux_amd64/bin"
        pkg.mkdir(parents=True)
        (pkg / "gh").write_text(
            "#!/usr/bin/env bash\n[[ ${GOMAXPROCS:-} == 1 ]] || { echo 'runtime: failed to create new OS thread' >&2; exit 2; }\n"
            "echo 'gh version 2.89.0'\n")
        (pkg / "gh").chmod(0o755)
        tarball = self.root / "gh2.tar.gz"
        self.run_cmd("tar", "-czf", str(tarball), "-C", str(self.root / "pkg2"), "gh_2.89.0_linux_amd64")
        (tools / "curl").write_text(
            "#!/usr/bin/env bash\nwhile [[ $# -gt 0 ]]; do [[ $1 == -o ]] && o=$2; shift; done\n"
            f"cp {tarball} \"$o\"\n")
        (tools / "curl").chmod(0o755)
        cfg = self.root / "cfg2"
        cfg.mkdir()
        home = self.root / "home3"
        home.mkdir()
        func = subprocess.run(["bash", "-c", "sed -n '/^limit_go_threads()/,/^}/p;/^gh_runs()/,/^}/p;/^ensure_gh_cli()/,/^}/p' " + str(SCRIPT)],
                              text=True, capture_output=True).stdout
        env = dict(self.env, HOME=str(home), PATH=str(tools) + os.pathsep + "/usr/bin:/bin")
        env.pop("SYNC_REPO_GH_BIN", None)
        env.pop("GOMAXPROCS", None)
        result = self.run_cmd("bash", "-c",
                              f"GH_BIN=''; GH_CLI_VERSION=2.89.0; PROJECT_CONFIG_DIR={cfg}\n{func}\n"
                              'ensure_gh_cli && echo "BIN=$GH_BIN GOMAXPROCS=$GOMAXPROCS"', env=env, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"BIN={cfg}/bin/gh GOMAXPROCS=1", result.stdout)


if __name__ == "__main__":
    unittest.main()


