import json
from pathlib import Path
path = Path(r'z:/docs/grafana-z2m-ultimate.json')
data = json.loads(path.read_text(encoding='utf-8'))
for panel in data['panels']:
    title = panel.get('title', '').lower()
    if 'temperature' in title:
        measurement = '/^(°C|Â°C)$/'
    elif 'humidity' in title:
        measurement = ' percent'
    elif 'pressure' in title:
        measurement = 'hPa'
    else:
        continue
    for target in panel.get('targets', []):
        query = target.get('query')
        if not query:
            continue
        import re
        target['query'] = re.sub(r'(FROM )(.*?|/.*?/)', r'\1' + measurement, query)
path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding='utf-8')
