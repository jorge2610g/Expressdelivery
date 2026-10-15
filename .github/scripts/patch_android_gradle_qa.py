"""QA-only Gradle patch; preserve symbolic Flutter SDK declarations."""
import argparse
import re
from pathlib import Path

def patch_gradle(source: str, *, kotlin_dsl: bool) -> str:
    patched = source.replace('jcenter()', 'mavenCentral()')
    names = ('compileSdk', 'compileSdkVersion') if kotlin_dsl else ('compileSdkVersion', 'compileSdk')
    for field in names:
        pattern = re.compile(rf'(?m)^([ \t]*{field}[ \t]*(?:=[ \t]*)?)[0-9]+\b')
        patched = pattern.sub(lambda m: m.group(1) + '36', patched)
    return patched

def patch_plugin_cache(root: Path) -> int:
    files = sorted(root.glob('*/android/build.gradle')) + sorted(root.glob('*/android/build.gradle.kts'))
    if not files:
        raise RuntimeError(f'No Android plugin Gradle files found under {root}')
    changed = 0
    for file in files:
        previous = file.read_text(encoding='utf-8')
        updated = patch_gradle(previous, kotlin_dsl=file.suffix == '.kts')
        if updated != previous:
            file.write_text(updated, encoding='utf-8')
            changed += 1
            print(f'Updated Gradle plugin: {file}')
    return changed

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--cache-root', type=Path, default=Path.home() / '.pub-cache/hosted/pub.dev')
    options = parser.parse_args()
    print(f'Patched {patch_plugin_cache(options.cache_root)} plugin files')
