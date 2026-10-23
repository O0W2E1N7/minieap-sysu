"""Check installer cleanup against LuCI 21.02 ccache's actual filename format."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
installer = (root / 'install.sh').read_text()
command = next(line for line in installer.splitlines() if line.startswith('rm -f /tmp/luci-indexcache'))
with tempfile.TemporaryDirectory(prefix='minieap-cache-test-') as td:
    scratch = pathlib.Path(td).resolve()
    cache = scratch / 'luci-modulecache'
    cache.mkdir()
    stale = []
    for name in ('luci.model.minieap_sysu', 'luci.controller.minieap_sysu'):
        path = cache / name.encode('ascii').hex().upper()
        path.write_bytes(b'stale compiled Lua: numeric mode 384')
        stale.append(path)
    index = scratch / 'luci-indexcache'
    index.write_text('stale index')
    preserved = scratch / 'minieap-sysu.conf'
    preserved.write_text('synthetic config, must remain unchanged')
    # Run the actual installer command, limited to this fresh scratch directory.
    test_command = command.replace('/tmp/', str(scratch) + '/')
    assert str(scratch).startswith('/tmp/minieap-cache-test-')
    subprocess.run(['/bin/sh', '-c', test_command], check=True)
    assert all(not p.exists() for p in stale), 'Hex-named bytecode cache was not cleared'
    assert not index.exists()
    assert preserved.read_text() == 'synthetic config, must remain unchanged'
print('PASS: hex-named controller/model caches and menu index removed; config preserved.')
