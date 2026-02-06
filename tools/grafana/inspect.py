from pathlib import Path
path = Path(r'z:/docs/grafana-z2m-ultimate.json')
text = path.read_text(encoding='utf-8')
start = text.index('SELECT mean( value)')
print(repr(text[start:start+120]))
