#!/usr/bin/env python3
"""QA-only Android scaffold, reusing the same vetted release build preparation.

This does not configure production signing, queue a release job, or publish.
The resulting APK is DEBUG signed and cannot replace the official signed APK.
"""
from pathlib import Path
import subprocess
import textwrap

source = Path('.github/workflows/build-android.yml').read_text(encoding='utf-8')

def source_step(name: str) -> str:
    header = '      - name: ' + name + '\n'
    if source.count(header) != 1:
        raise SystemExit('Expected exactly one release step: ' + name)
    section = source.split(header, 1)[1].split('\n      - name:', 1)[0]
    if section.count('        run: |\n') != 1:
        raise SystemExit('Unexpected release step format: ' + name)
    script = textwrap.dedent(section.split('        run: |\n', 1)[1])
    replacements = {
        '${{ steps.mode.outputs.org }}': 'com.express',
        '${{ steps.mode.outputs.project_name }}': 'usuario1',
        '${{ steps.mode.outputs.label }}': 'Express',
        '${{ steps.mode.outputs.package_name }}': 'com.express.usuario1',
    }
    for key, value in replacements.items():
        script = script.replace(key, value)
    if '${{' in script:
        raise SystemExit('Unresolved release workflow interpolation in ' + name)
    return script

for name in (
    'Patch Android plugin Gradle compatibility',
    'Create Android platform scaffold',
):
    print('Preparing QA Android via release-source step:', name, flush=True)
    subprocess.run(
        ['bash', '-euo', 'pipefail', '-c', source_step(name)],
        check=True,
    )
print('QA scaffold prepared without release signing', flush=True)
