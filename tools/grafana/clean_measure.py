from pathlib import Path
path = Path(r'z:/docs/grafana-z2m-ultimate.json')
text = path.read_text(encoding='utf-8')
old = 'FROM /^(°C|Â°C)$/ °C WHERE'
new = 'FROM /^(°C|Â°C)$/ WHERE'
if old not in text:
    raise SystemExit('pattern missing')
text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
