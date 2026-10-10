#!/usr/bin/env python3
"""Explicit, paid smoke check. Reads OPENROUTER_API_KEY; never prints or saves it.
Usage: python3 scripts/verify-openrouter.py [--studio]
Uses a synthetic fixture, never a user's wardrobe. Outputs are ignored by git.
"""
import base64
import json
import os
from pathlib import Path
import sys
import urllib.request
import urllib.error

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'build' / 'openrouter-smoke'
OUTPUT.mkdir(parents=True, exist_ok=True)
key = os.environ.get('OPENROUTER_API_KEY', '')
if not key:
    sys.exit('OPENROUTER_API_KEY is not set.')
image = (ROOT / 'DrapeTests/Fixtures/cardigan-source.png').read_bytes()
data_url = 'data:image/png;base64,' + base64.b64encode(image).decode()

def post(endpoint, body):
    request = urllib.request.Request('https://openrouter.ai/api/v1/' + endpoint,
        data=json.dumps(body).encode(), headers={'Authorization':'Bearer ' + key,
        'Content-Type':'application/json', 'X-OpenRouter-Title':'Drape verification'})
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        # Do not dump headers or requests; errors may echo input.
        print('HTTP error:', error.code)
        payload = json.loads(error.read())
        print('Provider message:', payload.get('error', {}).get('message', 'No message'))
        raise SystemExit(1)

fields = ['name','category','subcategory','color','brand','size','material','pattern','season','care','notes']
properties = {name:{'type':'string'} for name in fields}
properties['category']['enum'] = ['Tops','Bottoms','Dresses','Outerwear','Shoes','Bags','Accessories','Other']
result = post('chat/completions', {
    'model':'openai/gpt-6-luna',
    'messages':[{'role':'user','content':[
        {'type':'text','text':'Describe this single wardrobe item. Return empty strings for unknown fields. Never guess size, brand, material composition or care unless legible on a label. Give a short useful name. Color, pattern and type can be visually inferred.'},
        {'type':'image_url','image_url':{'url':data_url}}]}],
    'max_tokens':1800,
    'response_format':{'type':'json_schema','json_schema':{'name':'wardrobe_item','strict':True,
        'schema':{'type':'object','properties':properties,'required':fields,'additionalProperties':False}}},
    'provider':{'require_parameters':True,'data_collection':'deny'}})
details = json.loads(result['choices'][0]['message']['content'])
assert set(details) == set(fields)
assert details['category'] in properties['category']['enum']
assert not details['size'] and not details['brand'] and not details['care']
(OUTPUT / 'analysis.json').write_text(json.dumps(result, indent=2))
print('Analysis succeeded:', json.dumps(details))
print('Analysis reported cost:', result.get('usage',{}).get('cost', 'unreported'))
if '--studio' in sys.argv:
    result = post('images', {
        'model':'bytedance-seed/seedream-5-0-flash',
        'prompt':'Edit this into a clean realistic e-commerce catalogue photo of the EXACT same cardigan. Isolate it on pure white, centered fully visible with margins. Give it natural ghost-mannequin volume, straighten it, gently smooth incidental wrinkles. No person, hanger, or text. Preserve exact cream color, cable knit pattern, V-neck, proportions, five brown buttons, ribbing and fabric texture. Do not redesign it.',
        'input_references':[{'type':'image_url','image_url':{'url':data_url}}],
        'n':1, 'resolution':'1K', 'aspect_ratio':'3:4'})
    generated = base64.b64decode(result['data'][0]['b64_json'], validate=True)
    (OUTPUT / 'studio.png').write_bytes(generated)
    print('Studio succeeded:', len(generated), 'bytes; reported cost:', result.get('usage',{}).get('cost','unreported'))
    (OUTPUT / 'studio-summary.json').write_text(json.dumps({'usage':result.get('usage'), 'bytes':len(generated)},indent=2))
