#!/usr/bin/env python3
"""Synthetic signing-preflight checks. No Apple tools, profiles, accounts or network."""
from contextlib import redirect_stderr, redirect_stdout
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location('photo_cloud_check', Path(__file__).with_name('check-photo-cloud.py'))
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)
TEAM = 'TESTTEAM01'
NOW = datetime(2030, 1, 1, tzinfo=timezone.utc)


def expected(platform='ios', environment='Production'):
    return dict(platform=platform, environment=environment, team=TEAM,
                bundle=CHECK.BUNDLES[platform], container=CHECK.CONTAINER)


def profile_for(config=None):
    config = config or expected()
    identifier_key = 'com.apple.application-identifier' if config['platform'] == 'macos' else 'application-identifier'
    return {
        'ExpirationDate': datetime(2099, 1, 1),
        'TeamIdentifier': [config['team']],
        'Platform': ['OSX' if config['platform'] == 'macos' else 'iOS'],
        'Entitlements': {
            identifier_key: f'{config["team"]}.{config["bundle"]}',
            'com.apple.developer.team-identifier': config['team'],
            'com.apple.developer.icloud-container-identifiers': [config['container']],
            'com.apple.developer.icloud-services': ['CloudKit'],
            'com.apple.developer.icloud-container-environment': config['environment'],
        },
    }


def info_for(config):
    return dict(CFBundleIdentifier=config['bundle'], WorkbenchPhotoCloudProvisioned=True,
                WorkbenchPhotoCloudContainer=config['container'],
                WorkbenchPhotoCloudEnvironment=config['environment'])


def issued_shape_profile(config):
    """Synthetic values with the shapes observed in issued Apple profiles."""
    profile = profile_for(config)
    profile['Entitlements']['com.apple.developer.icloud-services'] = '*'
    profile['Entitlements']['com.apple.developer.icloud-container-environment'] = (
        ['Production', 'Development'] if config['platform'] == 'ios' else 'Production')
    return profile


def make_app(root, config, info=None):
    app = Path(root) / 'Synthetic Preview.app'
    contents = app / 'Contents' if config['platform'] == 'macos' else app
    contents.mkdir(parents=True)
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info_for(config) if info is None else info))
    embedded = contents / ('embedded.provisionprofile' if config['platform'] == 'macos' else 'embedded.mobileprovision')
    embedded.write_bytes(b'SYNTHETIC CMS PLACEHOLDER, NEVER PASSED TO SECURITY')
    return app, embedded


def signed_results(config, *, entitlements=None, metadata=None):
    entitlements = profile_for(config)['Entitlements'] if entitlements is None else entitlements
    metadata = f'TeamIdentifier={config["team"]}\nSignature size=1234\n'.encode() if metadata is None else metadata
    return [subprocess.CompletedProcess([], 0, b'', b''),
            subprocess.CompletedProcess([], 0, b'', b''),
            subprocess.CompletedProcess([], 0, b'', metadata),
            subprocess.CompletedProcess([], 0, plistlib.dumps(entitlements), b'')]


class PhotoCloudChecks(unittest.TestCase):
    def setUp(self):
        # Any forgotten mock fails safely instead of inspecting a real profile/app.
        self.run_guard = patch.object(CHECK.subprocess, 'run', side_effect=AssertionError('Unmocked Apple tool invocation'))
        self.run_guard.start()
        self.addCleanup(self.run_guard.stop)

    def test_valid_platforms_and_explicit_configuration(self):
        for config in (expected(), expected('macos'), expected(environment='Development')):
            with self.subTest(config=config):
                CHECK.check_profile(profile_for(config), now=NOW, **config)
        # Explicit overrides remain supported; defaults remain the paired Preview IDs.
        config = dict(expected(), bundle='com.example.private.preview', container='iCloud.com.example.private.preview')
        CHECK.check_profile(profile_for(config), now=NOW, **config)

    def test_issued_profile_service_wildcard_and_environment_allowlist(self):
        for config in (expected(), expected('macos'), expected(environment='Development')):
            with self.subTest(config=config):
                CHECK.check_profile(issued_shape_profile(config), now=NOW, **config)
        for environments in (['Production'], ['Development', 'Production'], 'Production'):
            profile = issued_shape_profile(expected())
            profile['Entitlements']['com.apple.developer.icloud-container-environment'] = environments
            CHECK.check_profile(profile, now=NOW, **expected())

    def test_profile_allowlists_reject_wrong_values_substrings_and_malformed_types(self):
        cases = {
            'com.apple.developer.icloud-services': [
                None, True, 1, [], {}, {'*': True}, ['*'], ['CloudKit', '*'],
                'CloudKit', '*CloudKit*', ' * ', 'CloudKit,CloudDocuments',
                ['prefixCloudKitsuffix'], ['CloudDocuments'], ['CloudKit', 1],
                ['CloudKit', ''], ['CloudKit', 'CloudKit'], ['CloudKit', 'Cloud*'],
            ],
            'com.apple.developer.icloud-container-environment': [
                None, True, 1, [], {}, {'Production': True}, ['Development'],
                'Development', '*', ['*'], 'production', ' Production ',
                'Production,Development', 'prefixProductionsuffix',
                ['Production', '*'], ['Production', 'Sandbox'], ['Production', ''],
                ['Production', 1], ['Production', 'Production'], [['Production']],
            ],
            'com.apple.developer.icloud-container-identifiers': [
                '*', ['*'], [CHECK.CONTAINER, '*'], CHECK.CONTAINER,
                {'*': True}, [CHECK.CONTAINER, 1], ['prefix' + CHECK.CONTAINER],
            ],
        }
        for key, values in cases.items():
            for value in values:
                profile = issued_shape_profile(expected())
                profile['Entitlements'][key] = value
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    CHECK.check_profile(profile, now=NOW, **expected())

    def test_profile_authorization_does_not_relax_binary_claims(self):
        for config in (expected(), expected('macos')):
            with self.subTest(platform=config['platform']), tempfile.TemporaryDirectory() as root:
                app, embedded = make_app(root, config)
                profile = issued_shape_profile(config)
                with patch.object(CHECK.subprocess, 'run', side_effect=signed_results(config)), patch.object(CHECK, 'load_profile', return_value=profile) as load:
                    CHECK.check_app(app, config)
                    load.assert_called_once_with(embedded)
                cases = [
                    ('com.apple.developer.icloud-services', '*'),
                    ('com.apple.developer.icloud-services', ['CloudKit', '*']),
                    ('com.apple.developer.icloud-services', ['CloudKit', 'Cloud*']),
                    ('com.apple.developer.icloud-container-environment', ['Production']),
                    ('com.apple.developer.icloud-container-environment', ['Production', 'Development']),
                    ('com.apple.developer.icloud-container-identifiers', [CHECK.CONTAINER, '*']),
                ]
                for key, value in cases:
                    signed = dict(profile_for(config)['Entitlements'], **{key: value})
                    with self.subTest(key=key, value=value), patch.object(CHECK.subprocess, 'run', side_effect=signed_results(config, entitlements=signed)), patch.object(CHECK, 'load_profile', return_value=profile) as load:
                        with self.assertRaises(ValueError):
                            CHECK.check_app(app, config)
                        load.assert_not_called()

    def test_profile_authorization_is_narrowed_to_exact_output_claims(self):
        for config in (expected(), expected('macos'), expected(environment='Development')):
            with self.subTest(config=config), tempfile.TemporaryDirectory() as root:
                profile = issued_shape_profile(config)
                original = deepcopy(profile)
                output = Path(root) / 'scoped.entitlements'
                CHECK.write_scoped_entitlements(output, profile, config)
                claims = plistlib.loads(output.read_bytes())
                self.assertEqual(claims['com.apple.developer.icloud-services'], ['CloudKit'])
                self.assertEqual(claims['com.apple.developer.icloud-container-environment'], config['environment'])
                self.assertEqual(claims['com.apple.developer.icloud-container-identifiers'], [config['container']])
                CHECK.check_entitlements(claims, **config)
                self.assertEqual(profile, original)
                self.assertNotIn(b'<string>*</string>', output.read_bytes())

    def test_wrong_profile_environment_creates_no_signing_output(self):
        profile = issued_shape_profile(expected())
        profile['Entitlements']['com.apple.developer.icloud-container-environment'] = ['Development']
        with tempfile.TemporaryDirectory() as root:
            output = Path(root) / 'scoped.entitlements'
            with self.assertRaisesRegex(ValueError, 'does not authorise'):
                CHECK.write_scoped_entitlements(output, profile, expected())
            self.assertFalse(output.exists())

    def test_malformed_expected_configuration_fails_closed(self):
        cases = {
            'platform': [None, [], 'visionos'],
            'environment': [None, [], 'production'],
            'team': [None, [], '', 'SHORT', 'TESTTEAM01\n', 'TESTTEAM0*'],
            'bundle': [None, [], '', 'com.example.*', '../Preview', 'a' * 256],
            'container': [None, [], '', 'com.example.preview', 'iCloud.com.*', 'iCloud.' + 'a' * 201],
        }
        for field, values in cases.items():
            for value in values:
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    CHECK.check_profile(profile_for(), now=NOW, **dict(expected(), **{field: value}))

    def test_mac_production_requirement_is_identified_as_project_policy(self):
        config = expected('macos', 'Development')
        with self.assertRaisesRegex(ValueError, 'Workbench paired Preview policy.*not an Apple platform restriction'):
            CHECK.check_profile(profile_for(config), now=NOW, **config)

    def test_non_dictionary_profile_and_entitlements_are_rejected(self):
        for value in (None, [], 'profile', 1, True):
            with self.subTest(value=value), self.assertRaises(ValueError):
                CHECK.check_profile(value, now=NOW, **expected())
            with self.subTest(entitlements=value), self.assertRaises(ValueError):
                CHECK.check_profile(dict(profile_for(), Entitlements=value), now=NOW, **expected())

    def test_profile_team_and_platform_require_real_string_arrays(self):
        for field, good in (('TeamIdentifier', TEAM), ('Platform', 'iOS')):
            bad_values = [None, [], good, f'prefix{good}suffix', {good: True}, [good, 1], [good, ''], [good, good], ['other']]
            for bad in bad_values:
                with self.subTest(field=field, value=bad), self.assertRaises(ValueError):
                    CHECK.check_profile(dict(profile_for(), **{field: bad}), now=NOW, **expected())

    def test_missing_profile_fields_and_wrong_platform_are_rejected(self):
        for key in ('ExpirationDate', 'TeamIdentifier', 'Platform', 'Entitlements'):
            profile = profile_for()
            del profile[key]
            with self.subTest(missing=key), self.assertRaises(ValueError):
                CHECK.check_profile(profile, now=NOW, **expected())
        for config, platform in ((expected(), 'OSX'), (expected('macos'), 'iOS')):
            with self.subTest(platform=platform), self.assertRaisesRegex(ValueError, 'different platform'):
                CHECK.check_profile(dict(profile_for(config), Platform=[platform]), now=NOW, **config)

    def test_expiry_boundary_and_malformed_dates(self):
        for expiry in (None, '', NOW.timestamp(), True, [], NOW, NOW - timedelta(seconds=1)):
            with self.subTest(expiry=expiry), self.assertRaises(ValueError):
                CHECK.check_profile(dict(profile_for(), ExpirationDate=expiry), now=NOW, **expected())
        CHECK.check_profile(dict(profile_for(), ExpirationDate=NOW + timedelta(microseconds=1)), now=NOW, **expected())
        with self.assertRaises(ValueError):
            CHECK.check_profile(profile_for(), now='2030-01-01', **expected())

    def test_expiry_preserves_timezone_instant_and_naive_utc(self):
        # A future local clock can already be expired in UTC, and vice versa.
        expired = datetime(2030, 1, 1, 9, tzinfo=timezone(timedelta(hours=10)))
        future = datetime(2029, 12, 31, 19, tzinfo=timezone(timedelta(hours=-6)))
        with self.assertRaisesRegex(ValueError, 'expired'):
            CHECK.check_profile(dict(profile_for(), ExpirationDate=expired), now=NOW, **expected())
        CHECK.check_profile(dict(profile_for(), ExpirationDate=future), now=NOW, **expected())
        CHECK.check_profile(dict(profile_for(), ExpirationDate=datetime(2030, 1, 1, 0, 0, 1)),
                            now=NOW.astimezone(timezone(timedelta(hours=10))), **expected())
        with self.assertRaisesRegex(ValueError, 'expired'):
            CHECK.check_profile(dict(profile_for(), ExpirationDate=datetime(2030, 1, 1)),
                                now=NOW.replace(tzinfo=None), **expected())

    def test_identifiers_cannot_use_wildcards_wrong_team_or_conflicting_aliases(self):
        for config in (expected(), expected('macos')):
            key = 'com.apple.application-identifier' if config['platform'] == 'macos' else 'application-identifier'
            good = profile_for(config)['Entitlements']
            CHECK.check_entitlements(good, **config)
            for value in (None, '', True, [], f'{TEAM}.*', 'OTHERTEAM1.' + config['bundle'], f'{TEAM}.com.ethdawg.workbench.mobile'):
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    CHECK.check_entitlements(dict(good, **{key: value}), **config)
        entitlements = profile_for()['Entitlements']
        with self.assertRaises(ValueError):
            CHECK.check_entitlements(dict(entitlements, **{'com.apple.application-identifier': 'WRONG'}), **expected())
        with self.assertRaises(ValueError):
            CHECK.check_entitlements(dict(entitlements, **{'application-identifier': '', 'com.apple.application-identifier': entitlements['application-identifier']}), **expected())
        entitlements.pop('application-identifier')
        with self.assertRaises(ValueError):
            CHECK.check_entitlements(entitlements, **expected())

    def test_native_platform_requires_its_identifier_key_and_matching_aliases(self):
        for config in (expected(), expected('macos')):
            entitlements = profile_for(config)['Entitlements']
            key = 'com.apple.application-identifier' if config['platform'] == 'macos' else 'application-identifier'
            alternate = next(value for value in CHECK.IDENTIFIER_KEYS if value != key)
            entitlements[alternate] = entitlements[key]
            CHECK.check_entitlements(entitlements, **config)
            del entitlements[key]
            with self.subTest(platform=config['platform']), self.assertRaisesRegex(ValueError, 'native platform'):
                CHECK.check_entitlements(entitlements, **config)

    def test_container_service_team_and_environment_fail_closed(self):
        entitlements = profile_for()['Entitlements']
        for key, good in (('com.apple.developer.icloud-container-identifiers', CHECK.CONTAINER),
                          ('com.apple.developer.icloud-services', 'CloudKit')):
            for value in (None, [], good, f'prefix{good}suffix', {good: True}, [good, 1], [good, ''], [good, good], ['*'], ['other']):
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    CHECK.check_entitlements(dict(entitlements, **{key: value}), **expected())
        for key in ('com.apple.developer.team-identifier', 'com.apple.developer.icloud-container-environment'):
            for value in (None, [], True, 'Wrong', ['Production']):
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    CHECK.check_entitlements(dict(entitlements, **{key: value}), **expected())
        for key in entitlements:
            missing = deepcopy(entitlements)
            del missing[key]
            with self.subTest(missing=key), self.assertRaises(ValueError):
                CHECK.check_entitlements(missing, **expected())

    def test_cms_decode_uses_no_shell_and_rejects_invalid_plists(self):
        path = Path('/synthetic only/$(not executed).mobileprovision')
        with patch.object(CHECK.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, plistlib.dumps(profile_for()), b'')) as run:
            self.assertEqual(CHECK.load_profile(path), profile_for())
            run.assert_called_once_with(['security', 'cms', '-D', '-i', str(path)], check=True, capture_output=True)
        for data in (b'not a plist', b'<?xml version="1.0"?><plist><dict>', plistlib.dumps(['not a dictionary'])):
            with self.subTest(data=data), patch.object(CHECK.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, data, b'')), self.assertRaises(ValueError):
                CHECK.load_profile(path)

    def test_signed_apps_match_info_signature_entitlements_and_embedded_profile(self):
        for config in (expected(), expected('macos')):
            with self.subTest(platform=config['platform']), tempfile.TemporaryDirectory() as root:
                app, embedded = make_app(root, config)
                with patch.object(CHECK.subprocess, 'run', side_effect=signed_results(config)) as run, patch.object(CHECK, 'load_profile', return_value=profile_for(config)) as load:
                    CHECK.check_app(app, config)
                    commands = [call.args[0] for call in run.call_args_list]
                    self.assertEqual(commands[0], ['codesign', '--verify', '--deep', '--strict', str(app)])
                    self.assertEqual(commands[1], ['codesign', '--verify', '--strict',
                                                  f'-R=identifier "{config["bundle"]}" and anchor apple generic and certificate leaf[subject.OU] = "{TEAM}"', str(app)])
                    self.assertEqual(commands[2], ['codesign', '-d', '--verbose=4', str(app)])
                    self.assertEqual(commands[3], ['codesign', '-d', '--entitlements', '-', '--xml', str(app)])
                    load.assert_called_once_with(embedded)

    def test_app_info_requires_matching_identity_and_explicit_opt_in(self):
        config = expected()
        cases = [('CFBundleIdentifier', 'com.ethdawg.workbench.mobile'),
                 ('WorkbenchPhotoCloudContainer', 'iCloud.com.other.preview'),
                 ('WorkbenchPhotoCloudEnvironment', 'Development')]
        cases += [('WorkbenchPhotoCloudProvisioned', value) for value in (False, 1, 'NO', 'false', '0', 'yes', ' true ', '$(WORKBENCH_PHOTO_CLOUD_PROVISIONED)', [])]
        for key, value in cases:
            with self.subTest(key=key, value=value), tempfile.TemporaryDirectory() as root:
                app, _ = make_app(root, config, dict(info_for(config), **{key: value}))
                with self.assertRaises(ValueError):
                    CHECK.check_app(app, config)
        for marker in (True, 'YES', 'true', '1'):
            with self.subTest(marker=marker), tempfile.TemporaryDirectory() as root:
                app, _ = make_app(root, config, dict(info_for(config), WorkbenchPhotoCloudProvisioned=marker))
                with patch.object(CHECK.subprocess, 'run', side_effect=signed_results(config)), patch.object(CHECK, 'load_profile', return_value=profile_for(config)):
                    CHECK.check_app(app, config)
        with tempfile.TemporaryDirectory() as root:
            app, _ = make_app(root, config, ['malformed root'])
            with self.assertRaises(ValueError):
                CHECK.check_app(app, config)

    def test_actual_signature_team_cannot_be_spoofed_by_entitlements(self):
        config = expected()
        metadata_cases = [b'', b'TeamIdentifier=OTHERTEAM1\n', b'TeamIdentifier=not set\n',
                          f'TeamIdentifier={TEAM}\nSignature=adhoc\n'.encode(),
                          f'TeamIdentifier={TEAM}\nTeamIdentifier=OTHERTEAM1\n'.encode()]
        for metadata in metadata_cases:
            with self.subTest(metadata=metadata), tempfile.TemporaryDirectory() as root:
                app, _ = make_app(root, config)
                with patch.object(CHECK.subprocess, 'run', side_effect=signed_results(config, metadata=metadata)), self.assertRaisesRegex(ValueError, 'signature'):
                    CHECK.check_app(app, config)

    def test_signature_failure_and_mismatching_embedded_profile_are_rejected(self):
        config = expected()
        with tempfile.TemporaryDirectory() as root:
            app, _ = make_app(root, config)
            with patch.object(CHECK.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, ['codesign'])), patch.object(CHECK, 'load_profile') as load:
                with self.assertRaises(subprocess.CalledProcessError):
                    CHECK.check_app(app, config)
                load.assert_not_called()
            wrong_profile = dict(profile_for(config), TeamIdentifier=['OTHERTEAM1'])
            with patch.object(CHECK.subprocess, 'run', side_effect=signed_results(config)), patch.object(CHECK, 'load_profile', return_value=wrong_profile), self.assertRaises(ValueError):
                CHECK.check_app(app, config)
            wrong_entitlements = dict(profile_for(config)['Entitlements'], **{'com.apple.developer.icloud-container-environment': 'Development'})
            with patch.object(CHECK.subprocess, 'run', side_effect=signed_results(config, entitlements=wrong_entitlements)), self.assertRaises(ValueError):
                CHECK.check_app(app, config)

    def test_malformed_signed_entitlements_are_rejected_without_profile_read(self):
        config = expected()
        for data in (b'<broken', plistlib.dumps(['not a dictionary'])):
            with self.subTest(data=data), tempfile.TemporaryDirectory() as root:
                app, _ = make_app(root, config)
                results = signed_results(config)
                results[-1] = subprocess.CompletedProcess([], 0, data, b'')
                with patch.object(CHECK.subprocess, 'run', side_effect=results), patch.object(CHECK, 'load_profile') as load:
                    with self.assertRaises(ValueError):
                        CHECK.check_app(app, config)
                    load.assert_not_called()

    def test_scoped_output_excludes_profile_metadata_and_unrelated_entitlements(self):
        for config in (expected(), expected('macos')):
            with self.subTest(platform=config['platform']), tempfile.TemporaryDirectory() as root:
                profile = profile_for(config)
                profile['ProvisionedDevices'] = ['PRIVATE-SYNTHETIC-DEVICE']
                profile['DeveloperCertificates'] = [b'PRIVATE-SYNTHETIC-CERTIFICATE']
                profile['Entitlements'].update({'get-task-allow': True, 'keychain-access-groups': ['unrelated'],
                                               'com.apple.developer.icloud-container-identifiers': [config['container'], 'iCloud.com.other'],
                                               'com.apple.developer.icloud-services': ['CloudKit', 'CloudDocuments']})
                before = deepcopy(profile)
                output = Path(root) / 'scoped.entitlements'
                CHECK.write_scoped_entitlements(output, profile, config)
                scoped = plistlib.loads(output.read_bytes())
                wanted = profile_for(config)['Entitlements']
                if config['platform'] == 'macos':
                    wanted.update({'com.apple.security.device.audio-input': True, 'com.apple.security.device.camera': True})
                self.assertEqual(scoped, wanted)
                self.assertEqual(profile, before)
                self.assertNotIn(b'PRIVATE-SYNTHETIC', output.read_bytes())

    def test_output_never_overwrites_and_invalid_profile_creates_nothing(self):
        with tempfile.TemporaryDirectory() as root:
            output = Path(root) / 'existing.entitlements'
            output.write_bytes(b'previously reviewed file')
            with self.assertRaises(FileExistsError):
                CHECK.write_scoped_entitlements(output, profile_for(), expected())
            self.assertEqual(output.read_bytes(), b'previously reviewed file')
            new_output = Path(root) / 'new.entitlements'
            for profile in (dict(profile_for(), ExpirationDate=datetime(2000, 1, 1)), dict(profile_for(), Entitlements=[])):
                with self.assertRaises(ValueError):
                    CHECK.write_scoped_entitlements(new_output, profile, expected())
                self.assertFalse(new_output.exists())

    def test_partial_output_failure_is_removed_and_retry_can_succeed(self):
        class FailingWriter:
            def __init__(self, stream):
                self.stream = stream

            def __enter__(self):
                return self

            def __exit__(self, *args):
                self.stream.close()

            def write(self, data):
                self.stream.write(data[:10])
                self.stream.flush()
                raise OSError('Synthetic disk write failure')

        original_open = Path.open
        with tempfile.TemporaryDirectory() as root:
            output = Path(root) / 'scoped.entitlements'
            with patch.object(Path, 'open', lambda path, mode: FailingWriter(original_open(path, mode))):
                with self.assertRaisesRegex(OSError, 'Synthetic disk write failure'):
                    CHECK.write_scoped_entitlements(output, profile_for(), expected())
            self.assertFalse(output.exists())
            CHECK.write_scoped_entitlements(output, profile_for(), expected())
            self.assertEqual(plistlib.loads(output.read_bytes()), profile_for()['Entitlements'])

    def invoke_main(self, extra):
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            result = CHECK.main(['--platform', 'ios', '--team', TEAM, '--environment', 'Production', *extra])
        return result, stdout.getvalue(), stderr.getvalue()

    def test_cli_reads_by_default_and_reports_optional_output_accurately(self):
        with tempfile.TemporaryDirectory() as root, patch.object(CHECK, 'load_profile', return_value=profile_for()):
            output = Path(root) / 'scoped.entitlements'
            result, stdout, stderr = self.invoke_main(['--profile', 'synthetic.mobileprovision'])
            self.assertEqual((result, stderr), (0, ''))
            evidence = json.loads(stdout)
            self.assertFalse(evidence['entitlements_written'])
            self.assertEqual(list(Path(root).iterdir()), [])
            self.assertEqual(evidence['bundle'], CHECK.BUNDLES['ios'])
            self.assertIn('two-device transfer', evidence['limit'])
            result, stdout, stderr = self.invoke_main(['--profile', 'synthetic.mobileprovision', '--entitlements-out', str(output)])
            self.assertEqual((result, stderr), (0, ''))
            self.assertTrue(json.loads(stdout)['entitlements_written'])
            self.assertEqual(plistlib.loads(output.read_bytes()), profile_for()['Entitlements'])

    def test_cli_rejects_app_output_without_running_apple_tools(self):
        with tempfile.TemporaryDirectory() as root:
            output = Path(root) / 'should-not-exist.entitlements'
            result, stdout, stderr = self.invoke_main(['--app', 'synthetic.app', '--entitlements-out', str(output)])
            self.assertEqual(result, 1)
            self.assertEqual(stdout, '')
            self.assertIn('requires --profile', stderr)
            self.assertFalse(output.exists())

    def test_explicit_empty_cli_bundle_is_not_silently_replaced_by_default(self):
        result, stdout, stderr = self.invoke_main(['--profile', 'synthetic.mobileprovision', '--bundle', ''])
        self.assertEqual(result, 1)
        self.assertEqual(stdout, '')
        self.assertIn('bundle identifier is malformed', stderr)

    def test_cli_failures_do_not_print_cms_contents_or_success_evidence(self):
        marker = 'PRIVATE-SYNTHETIC-DEVICE'
        errors = [subprocess.CalledProcessError(1, ['security', marker], output=marker.encode(), stderr=marker.encode()),
                  ValueError('Decoded provisioning profile is not a valid property list.')]
        for error in errors:
            with self.subTest(error=type(error).__name__), patch.object(CHECK, 'load_profile', side_effect=error):
                result, stdout, stderr = self.invoke_main(['--profile', 'synthetic.mobileprovision'])
                self.assertEqual(result, 1)
                self.assertEqual(stdout, '')
                self.assertIn('preflight failed', stderr)
                self.assertNotIn(marker, stderr)
        with patch.object(CHECK, 'load_profile', return_value=['malformed']):
            result, stdout, stderr = self.invoke_main(['--profile', 'synthetic.mobileprovision'])
            self.assertEqual(result, 1)
            self.assertEqual(stdout, '')
            self.assertNotIn('Traceback', stderr)


if __name__ == '__main__':
    unittest.main()
