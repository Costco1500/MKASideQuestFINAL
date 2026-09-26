import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from server import configure_private_environment

class PrivateConfigTests(unittest.TestCase):
    def test_private_file_configures_server_without_overriding_environment(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {"OPENAI_MODEL": "existing-model"}, clear=True):
            path = Path(folder) / "server.json"
            path.write_text(json.dumps({"OPENAI_API_KEY": "test-only-secret", "OPENAI_MODEL": "file-model"}))
            path.chmod(0o600)
            configure_private_environment(path)
            self.assertEqual(os.environ["OPENAI_API_KEY"], "test-only-secret")
            self.assertEqual(os.environ["OPENAI_MODEL"], "existing-model")

    def test_missing_private_file_keeps_offline_mode_available(self):
        with patch.dict(os.environ, {}, clear=True):
            configure_private_environment(Path("/missing-sidequest-config/server.json"))
            self.assertNotIn("OPENAI_API_KEY", os.environ)

    def test_world_readable_secret_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "server.json"
            path.write_text('{"OPENAI_API_KEY":"test-only-secret"}')
            path.chmod(0o644)
            with self.assertRaises(PermissionError): configure_private_environment(path)
