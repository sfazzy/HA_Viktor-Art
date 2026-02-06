from pathlib import Path
path = Path(r'z:/docs/grafana-z2m-ultimate.json')
text = path.read_text(encoding='utf-8')
text = text.replace('FROM  Â°C', 'FROM /^(°C|Â°C)$/')
text = text.replace('FROM percent', 'FROM percent')
text = text.replace('FROM hPa', 'FROM hPa')
path.write_text(text, encoding='utf-8')
