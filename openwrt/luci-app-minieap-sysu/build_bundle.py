"""Build the source-only LuCI installation archive using Python 3."""
import gzip
import hashlib
import pathlib
import tarfile

root = pathlib.Path(__file__).resolve().parent
paths = [root / name for name in ('install.sh', 'README.md', 'LICENSE')]
paths += sorted(p for p in (root / 'root').rglob('*') if p.is_file())
paths += sorted(p for p in (root / 'runtime').rglob('*') if p.is_file())
payload = {p.relative_to(root).as_posix(): p.read_bytes().replace(b'\r\n', b'\n') for p in paths}
payload['SHA256SUMS'] = ''.join(
    hashlib.sha256(data).hexdigest() + '  ' + name + '\n'
    for name, data in sorted(payload.items())
).encode('ascii')
out = root / 'dist'
out.mkdir(exist_ok=True)
bundle = out / 'minieap-sysu-luci.tar.gz'
import io
with bundle.open('wb') as dest:
    with gzip.GzipFile(fileobj=dest, mode='wb', filename='', mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode='w') as tar:
            for name, data in sorted(payload.items()):
                info = tarfile.TarInfo(name)
                info.size = len(data)
                info.mode = 0o755 if name == 'install.sh' else 0o644
                tar.addfile(info, io.BytesIO(data))
with tarfile.open(bundle) as tar:
    for name, data in payload.items():
        assert tar.extractfile(name).read() == data
digest = hashlib.sha256(bundle.read_bytes()).hexdigest()
(out / 'minieap-sysu-luci.tar.gz.sha256').write_text(digest + '  ' + bundle.name + '\n', encoding='ascii')
print(bundle)
print('SHA256:', digest)
