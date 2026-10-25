import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "tools" / "video_profiles.json"


class VideoManifestTest(unittest.TestCase):
    def test_25_profiles(self):
        data = json.loads(MANIFEST.read_text())
        self.assertEqual(len(data["profiles"]), 25)
        self.assertEqual(len({p["id"] for p in data["profiles"]}), 25)

    def test_does_not_claim_playback(self):
        data = json.loads(MANIFEST.read_text())
        self.assertFalse(data["capability"]["playback"])
        self.assertEqual(data["capability"]["media_error"],
                         "MEDIA_ERR_SRC_NOT_SUPPORTED")

    def test_runner_exists(self):
        data = json.loads(MANIFEST.read_text())
        self.assertTrue((ROOT / data["test_file"]).exists())
        self.assertTrue((ROOT / data["runner"]).exists())


if __name__ == "__main__":
    unittest.main()
