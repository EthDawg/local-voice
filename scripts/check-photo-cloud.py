#!/usr/bin/env python3
"""Validate private photo handoff signing locally; optionally write scoped entitlements.

Without --entitlements-out this only reads files and runs signature/profile checks.
The optional output is created exclusively, never overwritten. No capability is
created, no app is signed, and no account or CloudKit service is contacted.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from xml.parsers.expat import ExpatError

CONTAINER = 'iCloud.com.ethdawg.workbench.preview'
BUNDLES = {'ios': 'com.ethdawg.workbench.mobile.preview', 'macos': 'com.ethdawg.workbench.preview'}
IDENTIFIER_KEYS = ('application-identifier', 'com.apple.application-identifier')


def check_expected(*, platform, container, environment, bundle, team):
    if not isinstance(platform, str) or platform not in BUNDLES:
        raise ValueError('Select the iOS or macOS platform.')
    if not isinstance(team, str) or re.fullmatch(r'[A-Z0-9]{10}', team) is None:
        raise ValueError('The selected team must be a ten-character Apple team identifier.')
    identifier = r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+'
    if not isinstance(bundle, str) or len(bundle) > 255 or re.fullmatch(identifier, bundle) is None:
        raise ValueError('The selected bundle identifier is malformed; wildcards are not supported.')
    if (not isinstance(container, str) or not container.startswith('iCloud.')
            or len(container) > 200 or re.fullmatch(identifier, container) is None):
        raise ValueError('The selected iCloud container identifier is malformed.')
    if not isinstance(environment, str) or environment not in ('Development', 'Production'):
        raise ValueError('Select the Development or Production CloudKit environment.')
    # This is Workbench's paired Preview release policy, not an Apple platform limitation.
    if platform == 'macos' and environment != 'Production':
        raise ValueError('Workbench paired Preview policy requires Production on Mac; this is not an Apple platform restriction.')


def require_dictionary(value, label):
    if not isinstance(value, dict):
        raise ValueError(f'{label} must be a property-list dictionary.')
    return value


def string_list(value, label):
    # Membership on a string or dictionary would otherwise accept substrings/keys.
    if (not isinstance(value, list) or not value
            or any(not isinstance(item, str) or not item for item in value)
            or len(value) != len(set(value))):
        raise ValueError(f'{label} must be a nonempty array of distinct strings.')
    return value


def load_dictionary(data, label):
    try:
        value = plistlib.loads(data)
    except (plistlib.InvalidFileException, ExpatError, ValueError, TypeError, OverflowError):
        # Parser diagnostics can contain supplied profile values. Keep logs scoped.
        raise ValueError(f'{label} is not a valid property list.') from None
    return require_dictionary(value, label)


def _check_identity_and_container(entitlements, *, platform, container, environment, bundle, team):
    check_expected(platform=platform, container=container, environment=environment, bundle=bundle, team=team)
    require_dictionary(entitlements, 'Entitlements')
    required_identifier_key = 'com.apple.application-identifier' if platform == 'macos' else 'application-identifier'
    if required_identifier_key not in entitlements:
        raise ValueError('The application identifier entitlement for the selected native platform is missing.')
    identifiers = [entitlements[key] for key in IDENTIFIER_KEYS if key in entitlements]
    if not identifiers or any(identifier != f'{team}.{bundle}' for identifier in identifiers):
        raise ValueError('Every application identifier must exactly match the selected team and bundle.')
    if entitlements.get('com.apple.developer.team-identifier') != team:
        raise ValueError('The team entitlement does not match the selected team.')
    containers = string_list(entitlements.get('com.apple.developer.icloud-container-identifiers'), 'iCloud containers')
    if container not in containers or any('*' in value for value in containers):
        raise ValueError('The shared photo container is not authorised.')


def _check_cloudkit_service_claim(value):
    services = string_list(value, 'iCloud services')
    if 'CloudKit' not in services or any('*' in service for service in services):
        raise ValueError('The CloudKit service is not authorised.')


def check_entitlements(entitlements, **expected):
    """Check claims embedded in an app signature, never profile allowlists."""
    _check_identity_and_container(entitlements, **expected)
    _check_cloudkit_service_claim(entitlements.get('com.apple.developer.icloud-services'))
    if entitlements.get('com.apple.developer.icloud-container-environment') != expected['environment']:
        raise ValueError('The entitlement does not match the selected CloudKit environment.')


def check_profile_entitlements(entitlements, **expected):
    # TN3125 distinguishes a profile's authorization allowlist from the app's
    # exact claims. Issued Apple profiles can authorize all iCloud services with
    # the literal string "*", and one or both environments in a string array.
    _check_identity_and_container(entitlements, **expected)
    services = entitlements.get('com.apple.developer.icloud-services')
    if not (isinstance(services, str) and services == '*'):
        _check_cloudkit_service_claim(services)
    environments = entitlements.get('com.apple.developer.icloud-container-environment')
    if isinstance(environments, str):
        environments = [environments]
    else:
        environments = string_list(environments, 'Profile iCloud environments')
    if (any(value not in ('Development', 'Production') for value in environments)
            or expected['environment'] not in environments):
        raise ValueError('The profile does not authorise the selected CloudKit environment.')


def utc_date(value, label):
    if not isinstance(value, datetime):
        raise ValueError(f'{label} must be a date.')
    # plistlib historically returns naive UTC dates. Preserve aware instants too.
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def check_profile(profile, *, now=None, **expected):
    check_expected(**expected)
    require_dictionary(profile, 'Provisioning profile')
    now = utc_date(datetime.now(timezone.utc) if now is None else now, 'Current time')
    expiry = utc_date(profile.get('ExpirationDate'), 'Profile expiry')
    if expiry <= now:
        raise ValueError('The provisioning profile has expired.')
    if expected['team'] not in string_list(profile.get('TeamIdentifier'), 'Profile teams'):
        raise ValueError('The provisioning profile belongs to another team.')
    platform = 'iOS' if expected['platform'] == 'ios' else 'OSX'
    if platform not in string_list(profile.get('Platform'), 'Profile platforms'):
        raise ValueError('The provisioning profile is for a different platform.')
    check_profile_entitlements(profile.get('Entitlements', {}), **expected)


def load_profile(path):
    result = subprocess.run(['security', 'cms', '-D', '-i', str(path)], check=True, capture_output=True)
    return load_dictionary(result.stdout, 'Decoded provisioning profile')


def check_app(path, expected):
    check_expected(**expected)
    info_path = path / ('Contents/Info.plist' if expected['platform'] == 'macos' else 'Info.plist')
    info = load_dictionary(info_path.read_bytes(), 'App Info.plist')
    if info.get('CFBundleIdentifier') != expected['bundle']:
        raise ValueError('This is not the selected app bundle.')
    marker = info.get('WorkbenchPhotoCloudProvisioned')
    # Xcode substitutes YES into the mobile string key; Mac packaging emits a
    # plist Boolean. Match the runtime's exact accepted forms, never truthiness.
    if marker is not True and not (isinstance(marker, str) and marker in ('YES', 'true', '1')):
        raise ValueError('The app must explicitly enable photo handoff with a supported provisioning marker.')
    if info.get('WorkbenchPhotoCloudContainer') != expected['container'] or info.get('WorkbenchPhotoCloudEnvironment') != expected['environment']:
        raise ValueError('The app configuration does not match the intended container and environment.')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(path)], check=True, capture_output=True)
    # Verify the signing identity independently of self-reported entitlements.
    # Apply this app's identifier only to the outer app; nested code has its own IDs.
    requirement = f'identifier "{expected["bundle"]}" and anchor apple generic and certificate leaf[subject.OU] = "{expected["team"]}"'
    subprocess.run(['codesign', '--verify', '--strict', f'-R={requirement}', str(path)], check=True, capture_output=True)
    details = subprocess.run(['codesign', '-d', '--verbose=4', str(path)], check=True, capture_output=True)
    lines = details.stderr.decode('utf-8', errors='replace').splitlines()
    teams = [line.removeprefix('TeamIdentifier=') for line in lines if line.startswith('TeamIdentifier=')]
    if teams != [expected['team']] or 'Signature=adhoc' in lines:
        raise ValueError('The app signature does not identify the selected team.')
    # Force plist output; current codesign can otherwise display human-readable DER.
    signed = subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', str(path)], check=True, capture_output=True)
    check_entitlements(load_dictionary(signed.stdout, 'Signed app entitlements'), **expected)
    embedded = path / ('Contents/embedded.provisionprofile' if expected['platform'] == 'macos' else 'embedded.mobileprovision')
    check_profile(load_profile(embedded), **expected)


def write_scoped_entitlements(path, profile, expected):
    # Validate again so this helper cannot emit entitlements from unchecked data.
    check_profile(profile, **expected)
    allowed = {*IDENTIFIER_KEYS, 'com.apple.developer.team-identifier',
               'com.apple.developer.icloud-container-identifiers', 'com.apple.developer.icloud-services',
               'com.apple.developer.icloud-container-environment'}
    entitlements = {key: value for key, value in profile['Entitlements'].items() if key in allowed}
    entitlements['com.apple.developer.icloud-container-identifiers'] = [expected['container']]
    entitlements['com.apple.developer.icloud-services'] = ['CloudKit']
    entitlements['com.apple.developer.icloud-container-environment'] = expected['environment']
    if expected['platform'] == 'macos':
        entitlements.update({'com.apple.security.device.audio-input': True, 'com.apple.security.device.camera': True})
    check_entitlements(entitlements, **expected)
    payload = plistlib.dumps(entitlements)
    # Serialize before exclusive creation; leave existing reviewed output intact.
    with path.open('xb') as stream:
        try:
            stream.write(payload)
            stream.flush()
        except OSError:
            path.unlink(missing_ok=True)
            raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=BUNDLES, required=True)
    parser.add_argument('--team', required=True)
    parser.add_argument('--environment', choices=['Development', 'Production'], required=True)
    parser.add_argument('--container', default=CONTAINER)
    parser.add_argument('--bundle', help='Defaults to the platform Preview identifier.')
    parser.add_argument('--entitlements-out', type=Path, help='Create narrowly scoped signing entitlements from a validated profile; never overwrite an existing file or export the profile itself.')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--profile', type=Path)
    group.add_argument('--app', type=Path)
    args = parser.parse_args(argv)
    expected = dict(platform=args.platform, container=args.container, environment=args.environment,
                    team=args.team, bundle=BUNDLES[args.platform] if args.bundle is None else args.bundle)
    try:
        check_expected(**expected)
        if args.profile:
            profile = load_profile(args.profile)
            check_profile(profile, **expected)
            if args.entitlements_out:
                write_scoped_entitlements(args.entitlements_out, profile, expected)
        else:
            if args.entitlements_out:
                raise ValueError('--entitlements-out requires --profile.')
            check_app(args.app, expected)
    except (ValueError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        # CMS output can contain device IDs; never echo it into public build logs.
        print('Photo handoff preflight failed: ' + (str(error) if not isinstance(error, subprocess.CalledProcessError) else 'Signature/profile verification did not succeed.'), file=sys.stderr)
        return 1
    print(json.dumps({'verified': 'profile configuration' if args.profile else 'app signature and matching profile configuration', **expected,
                      'entitlements_written': bool(args.entitlements_out),
                      'limit': 'Does not prove profile issuance/revocation, signing-certificate membership in the profile, account availability, CloudKit schema deployment, or a two-device transfer.'}, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
