"""Regression checks for release rejection and nested signing order."""
import importlib.util
import hashlib
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile
from unittest.mock import patch
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location("workbench_release", Path(__file__).with_name("release.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    ROOT = Path(__file__).resolve().parents[2]
    IDENTITY = "A" * 40
    TEAM = "ABCDEFGHIJ"
    SIGNATURE = "Authority=Developer ID Application: Example\nTeamIdentifier=ABCDEFGHIJ\nflags=0x10000(runtime)\nTimestamp=Sep 8, 2026\n"

    def make_app(self, root, config):
        app = root / config["bundle"]
        executable = app / "Contents/MacOS" / config["executable"]
        executable.parent.mkdir(parents=True)
        executable.write_bytes(bytes.fromhex("cffaedfe") + b"fixture")
        info = {"CFBundleIdentifier": config["identifier"], "CFBundleExecutable": config["executable"],
                "CFBundleShortVersionString": "1.4.0", "CFBundleVersion": "42"}
        if config["channel"] == "preview":
            info["WorkbenchChannel"] = "preview"
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        return app

    def pack(self, app, archive):
        with zipfile.ZipFile(archive, "w") as package:
            for path in app.rglob("*"):
                if path.is_file():
                    package.write(path, path.relative_to(app.parent))

    def test_configuration_preserves_production_and_isolates_preview(self):
        production = release.configuration(self.ROOT)
        preview = release.configuration(self.ROOT, preview=True)
        original = json.loads((self.ROOT / "scripts/release/config.json").read_text())
        for key in ("bundle", "identifier", "executable", "archive", "build", "regressions", "checks", "entitlements"):
            self.assertEqual(production[key], original[key])
        self.assertEqual(production["channel"], "production")
        self.assertEqual(production["preview_archive"], original["archive"])
        self.assertEqual(preview["bundle"], "Workbench Preview.app")
        self.assertEqual(preview["identifier"], original["identifier"] + ".preview")
        self.assertEqual(preview["executable"], original["executable"] + "Preview")
        self.assertEqual(Path(preview["preview_archive"]).name, "Workbench Preview.zip")
        self.assertEqual(release.release_directory(self.ROOT, "1.4.0", "42", "production"), self.ROOT / ".build/releases/1.4.0-42")
        self.assertNotEqual(release.release_directory(self.ROOT, "1.4.0", "42", "preview"), release.release_directory(self.ROOT, "1.4.0", "42", "production"))

    def test_preview_reuses_builder_while_production_keeps_original_command(self):
        for preview in (False, True):
            config = release.configuration(self.ROOT, preview=preview)
            with patch.object(release, "run") as run, patch.object(release, "preview_tools") as helper:
                helper.return_value.build.return_value = Path("preview.zip")
                result = release.build_archive(self.ROOT, config, self.IDENTITY)
                if preview:
                    helper.return_value.build.assert_called_once_with(config, identity=self.IDENTITY)
                    run.assert_not_called()
                    self.assertEqual(result, Path("preview.zip"))
                else:
                    run.assert_called_once_with(*config["build"])
                    helper.assert_not_called()
                    self.assertEqual(result, self.ROOT / config["archive"])

    def test_both_channels_reject_wrong_bundle_executable_or_channel(self):
        for preview in (False, True):
            config = release.configuration(self.ROOT, preview=preview)
            with tempfile.TemporaryDirectory() as temporary:
                app = self.make_app(Path(temporary), config)
                path = app / "Contents/Info.plist"
                original = plistlib.loads(path.read_bytes())
                release.validate_identity(app, config)
                for key, value in (("CFBundleIdentifier", "wrong.app"), ("CFBundleExecutable", "wrong"),
                                   ("WorkbenchChannel", "production" if preview else "preview"),
                                   ("CFBundleVersion", "../../elsewhere")):
                    path.write_bytes(plistlib.dumps({**original, key: value}))
                    with self.subTest(preview=preview, key=key), self.assertRaises(RuntimeError):
                        release.validate_identity(app, config)
                path.write_bytes(plistlib.dumps(original))
                renamed = app.with_name("Wrong.app")
                app.rename(renamed)
                with self.assertRaises(RuntimeError):
                    release.validate_identity(renamed, config)

    def test_archive_rejects_wrong_app_traversal_and_duplicate_paths(self):
        config = release.configuration(self.ROOT, preview=True)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = self.make_app(root, config)
            archive = root / "preview.zip"
            self.pack(app, archive)
            release.validate_archive(archive, config)
            for name in ("Workbench.app/Contents/Info.plist", "../outside", "/outside", "__MACOSX/Other.app/._Info.plist",
                         f"{config['bundle']}/Contents/./Info.plist"):
                self.pack(app, archive)
                with zipfile.ZipFile(archive, "a") as package:
                    package.writestr(name, "unexpected")
                with self.subTest(name=name), self.assertRaises(RuntimeError):
                    release.validate_archive(archive, config)

    def test_clean_commit_is_rechecked_and_source_changes_rejected(self):
        with patch.object(release, "run", return_value=SimpleNamespace(stdout=" M app.swift\n")):
            with self.assertRaisesRegex(RuntimeError, "Commit or set aside"):
                release.require_clean_source()
        with patch.object(release, "run", side_effect=[SimpleNamespace(stdout=""), SimpleNamespace(stdout="different\n")]):
            with self.assertRaisesRegex(RuntimeError, "source commit changed"):
                release.require_clean_source(expected="original")

    def run_release_fixture(self, preview=False, fail_final_gatekeeper=False):
        config = release.configuration(self.ROOT, preview=preview)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = self.make_app(root / "fixture", config)
            archive = root / "built.zip"
            self.pack(app, archive)
            commands = []

            def command(*args, **kwargs):
                commands.append(args)
                if args[:3] == ("git", "status", "--porcelain"):
                    return SimpleNamespace(stdout="")
                if args[:3] == ("git", "rev-parse", "HEAD"):
                    return SimpleNamespace(stdout="fixture-commit\n")
                if args[0] == "security":
                    return SimpleNamespace(stdout=f'{self.IDENTITY} "Developer ID Application: Example ({self.TEAM})"\n')
                if args[:3] == ("ditto", "-x", "-k"):
                    with zipfile.ZipFile(args[3]) as package:
                        package.extractall(args[4])
                elif args[:2] == ("ditto", "-c"):
                    self.pack(Path(args[-2]), Path(args[-1]))
                elif args[:2] == ("lipo", "-archs"):
                    return SimpleNamespace(stdout="arm64\n")
                elif args[:3] == ("xcrun", "notarytool", "submit"):
                    return SimpleNamespace(stdout=json.dumps({"id": "submission-id"}))
                elif args[:3] == ("xcrun", "notarytool", "info"):
                    return SimpleNamespace(stdout=json.dumps({"id": "submission-id", "status": "Accepted"}))
                elif args[:3] == ("xcrun", "notarytool", "log"):
                    Path(args[-1]).write_text("{}")
                elif args[0] == "spctl" and "verify" in Path(args[-1]).parts and fail_final_gatekeeper:
                    raise RuntimeError("injected final archive Gatekeeper failure")
                return SimpleNamespace(stdout="{}", stderr=self.SIGNATURE)

            arguments = ["release.py", "--identity", self.IDENTITY, "--team-id", self.TEAM, "--keychain-profile", "fixture"]
            if preview:
                arguments.append("--preview")
            with patch.object(release, "__file__", str(root / "scripts/release/release.py")), \
                 patch.object(release, "configuration", return_value=config), \
                 patch.object(release, "build_archive", return_value=archive), \
                 patch.object(release, "run", side_effect=command), \
                 patch.object(release.os, "chdir"), patch.object(release.subprocess, "run"), \
                 patch("sys.argv", arguments):
                if fail_final_gatekeeper:
                    with self.assertRaisesRegex(RuntimeError, "final archive Gatekeeper"):
                        release.main()
                else:
                    release.main()
            output = release.release_directory(root, "1.4.0", "42", config["channel"])
            self.assertEqual(json.loads((output / "candidate.json").read_text())["channel"], config["channel"])
            self.assertEqual(json.loads((output / "submission.json").read_text())["id"], "submission-id")
            self.assertEqual((output / "submission-SHA256SUMS.txt").read_text().split()[0], hashlib.sha256((output / "submission.zip").read_bytes()).hexdigest())
            final = output / Path(config["preview_archive"]).name
            self.assertEqual(final.exists(), not fail_final_gatekeeper)
            self.assertEqual((output / "release.json").exists(), not fail_final_gatekeeper)
            if not fail_final_gatekeeper:
                evidence = json.loads((output / "release.json").read_text())
                self.assertEqual(evidence["channel"], config["channel"])
                self.assertEqual(evidence["bundle"], config["identifier"])
                self.assertEqual(evidence["executable"], config["executable"])
                self.assertEqual(evidence["sha256"], hashlib.sha256(final.read_bytes()).hexdigest())
                self.assertEqual((output / "SHA256SUMS.txt").read_text(), f"{evidence['sha256']}  {final.name}\n")
            self.assertEqual(sum(args[:3] == ("xcrun", "notarytool", "submit") for args in commands), 1)
            self.assertEqual(sum(args[:3] == ("git", "status", "--porcelain") for args in commands), 2)
            self.assertTrue(any(args[0] == "spctl" and "verify" in Path(args[-1]).parts for args in commands))

    def test_full_production_pipeline_preserved_without_apple_operations(self):
        self.run_release_fixture()

    def test_preview_pipeline_keeps_identity_channel_and_final_archive_evidence(self):
        self.run_release_fixture(preview=True)

    def test_failed_final_archive_retains_recovery_but_emits_no_release(self):
        self.run_release_fixture(preview=True, fail_final_gatekeeper=True)

    def test_only_explicit_acceptance_passes(self):
        for result in [{}, {"status": "Invalid"}, {"status": "In Progress"}, {"status": "Rejected"}]:
            with self.subTest(result=result), self.assertRaises(RuntimeError):
                release.require_accepted(result)
        release.require_accepted({"status": "Accepted"})

    def test_reject_wrong_team_or_weakened_signature(self):
        valid = "Authority=Developer ID Application: Example\nTeamIdentifier=ABCDEFGHIJ\nflags=0x10000(runtime)\nTimestamp=Sep 8, 2026\n"
        for missing in ["Authority=Developer ID Application:", "TeamIdentifier=ABCDEFGHIJ", "runtime", "Timestamp="]:
            with self.subTest(missing=missing), patch.object(release, "run", return_value=SimpleNamespace(stderr=valid.replace(missing, ""))):
                with self.assertRaises(RuntimeError):
                    release.check_signature(Path("Example.app"), "ABCDEFGHIJ")

    def test_nested_code_precedes_its_enclosing_bundle(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / "Example.app"
            helper = app / "Contents/XPCServices/Helper.xpc"
            executable = helper / "Contents/MacOS/Helper"
            executable.parent.mkdir(parents=True)
            executable.write_bytes(bytes.fromhex("cffaedfe") + b"test")
            (helper / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "Helper"}))
            resource = app / "Contents/Resources/Data.bundle"
            resource.mkdir(parents=True)
            (resource / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "test.resources"}))
            alias = executable.with_name("Alias")
            alias.symlink_to(executable)
            targets = release.signing_targets(app)
            self.assertEqual(targets, [executable, helper, app])


if __name__ == "__main__":
    unittest.main()
