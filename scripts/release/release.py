#!/usr/bin/env python3
"""Build, sign, notarize and verify an official Workbench direct-download release.

Mirrored in both Workbench repositories. Credentials are read by notarytool from
Keychain; this script never accepts passwords or private-key files.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile


def run(*args, capture=False, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, text=True,
                          stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.PIPE if capture else None, **kwargs)


def signing_targets(app):
    """Nested Mach-O code first, then enclosing code bundles, then the app."""
    targets = []
    for path in app.rglob("*"):
        if path.is_symlink():
            continue
        if path.is_file():
            with path.open("rb") as stream:
                magic = stream.read(4)
            if magic in {bytes.fromhex(value) for value in
                         ("feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}:
                targets.append(path)
        elif path.suffix in {".app", ".framework", ".xpc", ".bundle"}:
            # Resource-only SwiftPM bundles need no independent signature.
            candidates = [path / "Contents/Info.plist", path / "Info.plist",
                          path / "Resources/Info.plist"]
            for info in candidates:
                if info.exists():
                    if plistlib.loads(info.read_bytes()).get("CFBundleExecutable"):
                        targets.append(path)
                    break
    return sorted(set(targets), key=lambda p: (-len(p.parts), str(p))) + [app]


def check_signature(app, team):
    run("codesign", "--verify", "--deep", "--strict", "--verbose=2", app)
    details = run("codesign", "-d", "--verbose=4", app, capture=True).stderr
    if (f"TeamIdentifier={team}" not in details
            or "Authority=Developer ID Application:" not in details
            or "runtime" not in details or "Timestamp=" not in details):
        raise RuntimeError("Signature is missing the expected Developer ID, team, timestamp or hardened runtime")
    return details


def require_accepted(result):
    if result.get("status") != "Accepted":
        raise RuntimeError(f"Notarization not accepted: {result.get('status', 'unknown')}. See the saved log.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", required=True, help="SHA-1 fingerprint of a Developer ID Application identity")
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--keychain-profile", required=True, help="Existing notarytool Keychain profile name")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Fa-f0-9]{40}", args.identity):
        parser.error("--identity must be the certificate SHA-1 fingerprint, not an ad-hoc identity")
    if not re.fullmatch(r"[A-Z0-9]{10}", args.team_id):
        parser.error("Invalid Apple team ID")
    root = Path(__file__).resolve().parents[2]
    os.chdir(root)
    config = json.loads((root / "scripts/release/config.json").read_text())
    if run("git", "status", "--porcelain", capture=True).stdout.strip():
        raise RuntimeError("Commit or set aside working changes before making an official release")
    source = run("git", "rev-parse", "HEAD", capture=True).stdout.strip()
    identities = run("security", "find-identity", "-v", "-p", "codesigning", capture=True).stdout
    match = next((line for line in identities.splitlines() if args.identity.upper() in line.upper()), "")
    if "Developer ID Application:" not in match or f"({args.team_id})" not in match:
        raise RuntimeError("Expected Developer ID Application identity and private key are not available in Keychain")
    # Check authentication before spending time on builds. No secret is printed.
    run("xcrun", "notarytool", "history", "--keychain-profile", args.keychain_profile,
        "--output-format", "json", capture=True)
    run(*config["regressions"])
    run(*config["build"])
    with tempfile.TemporaryDirectory(prefix="workbench-release-") as temporary:
        staging = Path(temporary)
        run("ditto", "-x", "-k", root / config["archive"], staging)
        app = staging / config["bundle"]
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        if info["CFBundleIdentifier"] != config["identifier"]:
            raise RuntimeError("Unexpected bundle identifier")
        version = info["CFBundleShortVersionString"]
        build = info["CFBundleVersion"]
        if not re.fullmatch(r"[0-9.]+", version) or not re.fullmatch(r"[0-9.]+", build):
            raise RuntimeError("Unexpected version format")
        output = root / ".build/releases" / f"{version}-{build}"
        output.mkdir(parents=True, exist_ok=False)  # Never replace a release.
        for path in signing_targets(app):
            command = ["codesign", "--force", "--sign", args.identity,
                       "--timestamp", "--options", "runtime"]
            if path == app and config.get("entitlements"):
                command += ["--entitlements", str(root / config["entitlements"])]
            run(*command, path)
        signature = check_signature(app, args.team_id)
        (output / "signature.txt").write_text(signature)
        executable = app / "Contents/MacOS" / config["executable"]
        architectures = run("lipo", "-archs", executable, capture=True).stdout.strip()
        if "arm64" not in architectures.split():
            raise RuntimeError("Apple Silicon executable is missing")
        for check in config["checks"]:
            run(executable, *check)
        upload = staging / "notarization.zip"
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, upload)
        # Submit once, persist the ID before waiting, so an interrupted run can
        # be recovered through notarytool info/log without duplicate submissions.
        submission = json.loads(run("xcrun", "notarytool", "submit", upload,
            "--keychain-profile", args.keychain_profile, "--output-format", "json", capture=True).stdout)
        (output / "submission.json").write_text(json.dumps(submission, indent=2) + "\n")
        submission_id = submission["id"]
        print(f"Notarization submitted: {submission_id}", flush=True)
        # A rejected submission can make wait return nonzero; still retrieve its
        # status and diagnostic log before rejecting the release.
        subprocess.run(["xcrun", "notarytool", "wait", submission_id,
                        "--keychain-profile", args.keychain_profile], check=False)
        result = json.loads(run("xcrun", "notarytool", "info", submission_id,
            "--keychain-profile", args.keychain_profile, "--output-format", "json", capture=True).stdout)
        (output / "notarization.json").write_text(json.dumps(result, indent=2) + "\n")
        run("xcrun", "notarytool", "log", submission_id, "--keychain-profile",
            args.keychain_profile, output / "notarization-log.json")
        require_accepted(result)
        run("xcrun", "stapler", "staple", app)
        run("xcrun", "stapler", "validate", app)
        check_signature(app, args.team_id)
        run("spctl", "--assess", "--type", "execute", "--verbose=4", app)
        final = output / Path(config["archive"]).name
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, final)
        # Verify the exact archive after repackaging the stapled app.
        extracted = staging / "verify"
        run("ditto", "-x", "-k", final, extracted)
        check_signature(extracted / config["bundle"], args.team_id)
        run("xcrun", "stapler", "validate", extracted / config["bundle"])
        digest = hashlib.sha256(final.read_bytes()).hexdigest()
        (output / "SHA256SUMS.txt").write_text(f"{digest}  {final.name}\n")
        (output / "release.json").write_text(json.dumps({
            "source": source, "bundle": config["identifier"], "version": version,
            "build": build, "architectures": architectures, "team": args.team_id,
            "notarization": submission_id, "sha256": digest,
            "fresh_mac_interactive_test": "required before publication"
        }, indent=2) + "\n")
        print(f"Signed, notarized and stapled: {final}")
        print("Complete the native first-run checklist before publishing. No assets were uploaded to GitHub.")


if __name__ == "__main__":
    main()
