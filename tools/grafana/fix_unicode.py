from pathlib import Path
path = Path(r'z:/docs/grafana-z2m-ultimate.json')
text = path.read_text(encoding='utf-8')
text = text.replace('\u00c2\u00b0C', '°C')
path.write_text(text, encoding='utf-8')
