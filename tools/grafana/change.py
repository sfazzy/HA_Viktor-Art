import pathlib
path = pathlib.Path(r'z:/docs/grafana-z2m-ultimate.json')
data = path.read_text(encoding='utf-8')
old = 'SELECT mean( value) FROM Â°C'
new = 'SELECT mean(value) FROM /^(°C|Â°C)$/'
if old not in data:
    raise SystemExit('pattern missing')
data = data.replace(old, new, 1)
path.write_text(data, encoding='utf-8')
