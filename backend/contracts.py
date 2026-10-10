MODELS = {
    '/api/v1/chat/completions': 'openai/gpt-6-luna',
    '/api/v1/images': 'bytedance-seed/seedream-5-0-flash',
}


def validate_request(path, body):
    if not isinstance(body, dict) or body.get('model') != MODELS.get(path):
        raise ValueError('Unsupported request or model')
    if path == '/api/v1/chat/completions':
        if set(body) - {'model', 'max_tokens', 'provider', 'messages', 'response_format'}:
            raise ValueError('Unsupported fields')
        if body.get('max_tokens') != 1800 or body.get('provider') != {'require_parameters': True, 'data_collection': 'deny'}:
            raise ValueError('Unsupported analysis settings')
        if body.get('stream') or not isinstance(body.get('messages'), list):
            raise ValueError('Unsupported analysis request')
        # Only embedded images: never let the gateway fetch user-controlled URLs.
        image_urls = [part.get('image_url', {}).get('url', '') for message in body['messages']
                      for part in message.get('content', []) if part.get('type') == 'image_url']
        if not 1 <= len(image_urls) <= 6:
            raise ValueError('Expected one to six photos')
    elif path == '/api/v1/images':
        if set(body) - {'model', 'prompt', 'input_references', 'n', 'resolution', 'aspect_ratio'}:
            raise ValueError('Unsupported fields')
        if not isinstance(body.get('prompt'), str) or len(body['prompt']) > 4000:
            raise ValueError('Invalid prompt')
        if body.get('n') != 1 or body.get('resolution') != '1K' or body.get('aspect_ratio') != '3:4':
            raise ValueError('Unsupported image settings')
        refs = body.get('input_references', [])
        if len(refs) != 1:
            raise ValueError('Expected one reference photo')
        image_urls = [refs[0].get('image_url', {}).get('url', '')]
    else:
        raise ValueError('Unsupported route')
    if any(not isinstance(url, str) or not url.startswith('data:image/jpeg;base64,') for url in image_urls):
        raise ValueError('Only embedded JPEG photos are accepted')
