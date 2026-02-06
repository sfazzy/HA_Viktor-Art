from pathlib import Path
path = Path(r'z:/docs/grafana-z2m-ultimate.json')
text = path.read_text(encoding='utf-8')
text = text.replace(' Â°C', '°C')
text = text.replace('percentpercent', 'percent')
text = text.replace('hPahPa', 'hPa')
path.write_text(text, encoding='utf-8')
