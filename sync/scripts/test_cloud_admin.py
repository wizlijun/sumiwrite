"""Credential resolution for cloud-admin.py: environment first, then macOS Keychain, never files."""
import importlib.util, tempfile, unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('cloud_admin', HERE / 'cloud-admin.py')
cloud_admin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cloud_admin)  # must not touch the network, Keychain or disk

TOKEN, ACCOUNT = 'CLOUDFLARE_API_TOKEN', 'CLOUDFLARE_ACCOUNT_ID'
SERVICES = {'sumiwrite.cloudflare.api-token': 'kc-token', 'sumiwrite.cloudflare.account-id': 'kc-account'}


class ResolveCredentials(unittest.TestCase):
    def test_env_wins_over_keychain(self):
        got = cloud_admin.resolve_credentials({TOKEN: 'env-token', ACCOUNT: 'env-account'}, SERVICES.get)
        self.assertEqual(got, {TOKEN: 'env-token', ACCOUNT: 'env-account'})

    def test_falls_back_to_keychain(self):
        got = cloud_admin.resolve_credentials({}, SERVICES.get)
        self.assertEqual(got, {TOKEN: 'kc-token', ACCOUNT: 'kc-account'})
        got = cloud_admin.resolve_credentials({ACCOUNT: 'env-account'}, SERVICES.get)
        self.assertEqual(got, {TOKEN: 'kc-token', ACCOUNT: 'env-account'})

    def test_missing_token_message_has_no_values(self):
        with self.assertRaises(RuntimeError) as caught:
            cloud_admin.resolve_credentials({ACCOUNT: 'secret-account-value'}, lambda service: None)
        message = str(caught.exception)
        self.assertIn(TOKEN, message)
        self.assertNotIn(ACCOUNT, message)
        self.assertNotIn('secret-account-value', message)

    def test_empty_values_count_as_missing(self):
        with self.assertRaises(RuntimeError) as caught:
            cloud_admin.resolve_credentials({TOKEN: '', ACCOUNT: ''}, lambda service: '')
        self.assertIn(TOKEN, str(caught.exception))
        self.assertIn(ACCOUNT, str(caught.exception))

    def test_never_reads_dotenv(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / '.env').write_text(f'{TOKEN}=dotenv-token\n')
            (root / 'worker').mkdir()
            (root / 'worker/wrangler.toml').write_text('account_id = "0123456789abcdef0123456789abcdef"\n')
            saved = cloud_admin.ROOT
            cloud_admin.ROOT = root
            try:
                with self.assertRaises(RuntimeError):
                    cloud_admin.resolve_credentials({}, lambda service: None)
            finally:
                cloud_admin.ROOT = saved


class Layout(unittest.TestCase):
    def test_paths_point_inside_sumiwrite(self):
        self.assertEqual(cloud_admin.WORKER, HERE.parent)
        self.assertEqual(cloud_admin.ROOT, HERE.parent.parent)
        self.assertEqual(cloud_admin.TASK, HERE.parent / '.local')
        self.assertEqual(cloud_admin.WRANGLER, HERE.parent / 'node_modules/.bin/wrangler')


if __name__ == '__main__':
    unittest.main()
