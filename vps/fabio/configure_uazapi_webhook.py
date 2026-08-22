#!/usr/bin/env python3
from __future__ import annotations
import json, os, sys
from pathlib import Path
import requests

ENV_FILE = Path('/home/fabio/.hermes/.env')

def load_env():
    if not ENV_FILE.exists(): return
    for line in ENV_FILE.read_text(errors='ignore').splitlines():
        line=line.strip()
        if not line or line.startswith('#') or '=' not in line: continue
        if line.startswith('export '): line=line[len('export '):]
        k,v=line.split('=',1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

load_env()
base=(os.getenv('FABIO_UAZAPI_URL') or os.getenv('UAZAPI_URL') or 'https://lamusic.uazapi.com').rstrip('/')
token=os.getenv('FABIO_UAZAPI_TOKEN') or os.getenv('UAZAPI_TOKEN') or ''
secret=os.getenv('FABIO_CHAT_BRIDGE_SECRET') or ''
port=os.getenv('FABIO_CHAT_BRIDGE_PORT') or '8645'
public_host=os.getenv('FABIO_CHAT_PUBLIC_HOST') or '89.116.73.186'
if not token:
    print('blocked: FABIO_UAZAPI_TOKEN missing')
    sys.exit(2)
if not secret:
    print('blocked: FABIO_CHAT_BRIDGE_SECRET missing')
    sys.exit(2)
url=f'http://{public_host}:{port}/webhook/uazapi/{secret}'
body={
    'enabled': True,
    'url': url,
    'events': ['messages'],
    'excludeMessages': ['wasSentByApi'],
    'addUrlEvents': False,
    'addUrlTypesMessages': False,
}
r=requests.post(base + '/webhook', headers={'Content-Type':'application/json','token':token}, json=body, timeout=30)

def scrub(obj):
    if isinstance(obj, dict):
        return {k: ('<redacted>' if k.lower() in {'token','authorization','secret'} else scrub(v)) for k, v in obj.items()}
    if isinstance(obj, list):
        return [scrub(x) for x in obj]
    if isinstance(obj, str):
        return obj.replace(secret, '<secret>').replace(token, '<token>')
    return obj
resp = (r.json() if r.headers.get('content-type','').startswith('application/json') else r.text[:1000])
print(json.dumps({'status_code': r.status_code, 'ok': r.ok, 'url_configured': url.replace(secret, '<secret>'), 'response': scrub(resp)}, ensure_ascii=False, indent=2))
sys.exit(0 if r.ok else 1)
