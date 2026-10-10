#!/usr/bin/env python3
"""Exercise deployment against local Git repositories without network access."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
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
        self.assertEqual(local_file.read_text(), "new\n")
        refs = self.git(project, "for-each-ref", "--format=%(refname)", "refs/sync-repo/backups/").splitlines()
        self.assertEqual(len(refs), 1)
        self.assertEqual(self.git(project, "show", refs[0] + ":public_html/include/app.php"), "working logo")
        self.assertEqual(self.git(project, "show", refs[0] + "^2:public_html/include/app.php"), "staged logo")
        self.assert_runtime(project)

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

    def test_first_install_preserves_existing_runtime(self):
        project = self.fixture(fresh=True)
        result = self.deploy(project)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((project / "public_html/include/app.php").read_text(), "new\n")
        self.assert_runtime(project)

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
            'SCRIPT_VERSION="1.3.10"', 'SCRIPT_VERSION="1.3.11"', 1).replace(
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
                payload.write_text(SCRIPT.read_text().replace('SCRIPT_VERSION="1.3.10"', 'SCRIPT_VERSION="1.3.11"', 1))
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
        payload.write_text(SCRIPT.read_text().replace('SCRIPT_VERSION="1.3.10"', 'SCRIPT_VERSION="1.3.11"', 1))
        result = self.deploy(project, self.mock_curl(payload))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("1.3.11", result.stdout)
        self.assertEqual((project / ".deploy/sync_repo_from_git.sh").read_text(), SCRIPT.read_text())
        self.assertEqual((project / "public_html/include/app.php").read_text(), "new\n")
        self.assert_runtime(project)

    def test_same_or_older_version_is_not_installed(self):
        for version in ("1.3.10", "1.3.9"):
            with self.subTest(version=version):
                project = self.fixture(name="version-" + version)
                payload = self.root / "other-version.sh"
                payload.write_text(SCRIPT.read_text().replace('SCRIPT_VERSION="1.3.10"', 'SCRIPT_VERSION="' + version + '"', 1) + "\n# changed payload\n")
                result = self.interactive_deploy(project, "", self.mock_curl(payload))
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn("Доступна новая версия", result.stdout)
                self.assertEqual((project / ".deploy/sync_repo_from_git.sh").read_text(), SCRIPT.read_text())
                self.assert_runtime(project)
                shutil.rmtree(self.root / "bin")

    def test_eof_at_update_prompt_does_not_install_download(self):
        project = self.fixture()
        payload = self.root / "new-version.sh"
        payload.write_text(SCRIPT.read_text().replace('SCRIPT_VERSION="1.3.10"', 'SCRIPT_VERSION="1.3.11"', 1))
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


if __name__ == "__main__":
    unittest.main()
