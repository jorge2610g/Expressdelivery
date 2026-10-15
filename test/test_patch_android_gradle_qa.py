"""Regressions for zego_zim and file_picker Gradle failures."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

path = Path(__file__).resolve().parents[1] / '.github/scripts/patch_android_gradle_qa.py'
spec = importlib.util.spec_from_file_location('qa_gradle', path)
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)

class GradlePatchTests(unittest.TestCase):
    def test_zego_jcenter(self):
        result = qa.patch_gradle('repositories { jcenter() }', kotlin_dsl=False)
        self.assertIn('mavenCentral()', result)
        self.assertNotIn('jcenter()', result)
    def test_file_picker_symbolic_sdk(self):
        before = 'compileSdkVersion flutter.compileSdkVersion\n    defaultConfig { minSdk 21 }\n'
        self.assertEqual(qa.patch_gradle(before, kotlin_dsl=False), before)
    def test_numeric_groovy_kotlin(self):
        self.assertEqual(qa.patch_gradle('compileSdkVersion 33', kotlin_dsl=False), 'compileSdkVersion 36')
        self.assertEqual(qa.patch_gradle('compileSdk = 34', kotlin_dsl=True), 'compileSdk = 36')
    def test_idempotence_no_multiline_corruption(self):
        before = 'compileSdkVersion \n    defaultConfig { minSdk 21 }\ncompileSdkVersion 33\n'
        once = qa.patch_gradle(before, kotlin_dsl=False)
        self.assertIn('compileSdkVersion \n    defaultConfig', once)
        self.assertEqual(qa.patch_gradle(once, kotlin_dsl=False), once)
    def test_only_plugin_gradle_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            zego = root / 'zego_zim-2.29.0+1/android/build.gradle'
            zego.parent.mkdir(parents=True)
            zego.write_text('repositories { jcenter() }\ncompileSdkVersion 33\n')
            picker = root / 'file_picker-10.3.8/android/build.gradle'
            picker.parent.mkdir(parents=True)
            picker.write_text('compileSdkVersion flutter.compileSdkVersion\n')
            self.assertEqual(qa.patch_plugin_cache(root), 1)
            self.assertIn('mavenCentral()', zego.read_text())
            self.assertIn('compileSdkVersion 36', zego.read_text())
            self.assertEqual(picker.read_text(), 'compileSdkVersion flutter.compileSdkVersion\n')
if __name__ == '__main__':
    unittest.main()
