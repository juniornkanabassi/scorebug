#!/usr/bin/env python3
"""Check snapshot mode refuses unsafe paths before creating any fixture files."""
import os
import pathlib
import subprocess
import sys
import tempfile

scratch = pathlib.Path('/private/tmp/bama/build-scorebug')  # the app's safe root
binary = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(os.environ.get('SCOREBUG_SCRATCH', scratch)) / 'release/Scorebug')
if not binary.is_file():
    sys.exit(f'FAIL: build Scorebug first at {binary}')
scratch.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='snapshot-safety.', dir=scratch) as directory:
    case = pathlib.Path(directory)
    environment = {
        **os.environ,
        'CFFIXED_USER_HOME': str(case / 'home'),
        'SCOREBUG_NATIVE_SNAPSHOTS': str(case / 'images'),
    }
    data = ['--data-directory', str(case / 'data')]
    cases = [
        ('missing explicit data directory', environment, []),
        ('output outside build scratch', {**environment, 'SCOREBUG_NATIVE_SNAPSHOTS': '/private/tmp/disallowed-scorebug-snapshot-output'}, data),
        ('home outside build scratch', {**environment, 'CFFIXED_USER_HOME': '/private/tmp/disallowed-scorebug-home'}, data),
        ('data outside build scratch', environment, ['--data-directory', '/private/tmp/disallowed-scorebug-data']),
    ]
    for name, env, arguments in cases:
        result = subprocess.run([str(binary), "--agent-screen", *arguments], env=env, capture_output=True, text=True, timeout=20)
        assert result.returncode == 1, (name, result.returncode, result.stderr)
        assert 'unsafePaths' in result.stderr, (name, result.stderr)
        print(f'PASS: {name} rejected before rendering')
    assert not (case / 'images').exists()
    assert not (case / 'data').exists()
    print('PASS: no fixture or image files written on rejected paths')

# The snapshot script refuses unsafe SCOREBUG_SNAPSHOTS folders before it launches anything.
script = pathlib.Path(__file__).with_name('native-snapshots.sh')
home = pathlib.Path.home()
with tempfile.TemporaryDirectory(prefix='snapshot-output.', dir=scratch) as directory:
    stray = pathlib.Path(directory) / 'not-snapshots'
    stray.mkdir()
    (stray / 'notes.txt').write_text('keep')
    for destination in ['/', str(home), str(home / 'Library/Application Support/Scorebug'), str(script.parent.parent), str(stray)]:
        result = subprocess.run(['zsh', str(script), str(binary)], env={**os.environ, 'SCOREBUG_SNAPSHOTS': destination}, capture_output=True, text=True, timeout=20)
        assert result.returncode == 1 and 'unsafe snapshot output' in result.stderr, (destination, result.returncode, result.stderr)
        print(f'PASS: snapshot output {destination} refused')
    assert (stray / 'notes.txt').read_text() == 'keep' and len(list(stray.iterdir())) == 1
