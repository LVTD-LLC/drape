import os
import unittest
from unittest.mock import patch

import httpx
from fastapi.testclient import TestClient
from main import app

TOKEN = 'test-development-token-at-least-32-characters'


def analysis():
    return {'model': 'openai/gpt-6-luna', 'max_tokens': 1800,
            'provider': {'require_parameters': True, 'data_collection': 'deny'},
            'messages': [{'role': 'user', 'content': [{'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,dGVzdA=='}}]}]}


class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {'OPENROUTER_API_KEY': 'test-provider-secret', 'DRAPE_DEVELOPMENT_TOKEN': TOKEN})
        self.env.start()
        self.client = TestClient(app).__enter__()
        self.calls = []
        self.status = 200
        def upstream(request):
            self.calls.append(request)
            return httpx.Response(self.status, json={'choices': []} if self.status == 200 else {'private': 'provider-secret'})
        self.mock = httpx.AsyncClient(transport=httpx.MockTransport(upstream))
        self.original = app.state.client
        app.state.client = self.mock

    def tearDown(self):
        self.client.portal.call(self.mock.aclose)
        app.state.client = self.original
        self.client.__exit__(None, None, None)
        self.env.stop()

    def post(self, body=None, token=TOKEN, **kwargs):
        return self.client.post('/api/v1/chat/completions', json=analysis() if body is None else body,
                                headers={'Authorization': 'Bearer ' + token}, **kwargs)

    def test_requires_authentication_before_upstream(self):
        self.assertEqual(self.post(token='wrong').status_code, 401)
        self.assertFalse(self.calls)

    def test_server_adds_provider_key_once(self):
        response = self.post()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers['cache-control'], 'no-store')
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.calls[0].headers['authorization'], 'Bearer test-provider-secret')
        self.assertNotIn(TOKEN, self.calls[0].content.decode())

    def test_rejects_extra_fields_models_and_remote_urls(self):
        for field, value in [('tools', []), ('model', 'expensive/model'), ('max_tokens', 999999), ('provider', {})]:
            body = analysis(); body[field] = value
            self.assertEqual(self.post(body).status_code, 400)
        body = analysis(); body['messages'][0]['content'][0]['image_url']['url'] = 'https://example.com/image'
        self.assertEqual(self.post(body).status_code, 400)
        self.assertEqual(self.post([]).status_code, 400)
        self.assertFalse(self.calls)

    def test_analysis_accepts_six_photos_but_rejects_seven(self):
        body = analysis()
        photo = body['messages'][0]['content'][0]
        for count, status in [(6, 200), (7, 400)]:
            body['messages'][0]['content'] = [photo] * count
            self.assertEqual(self.post(body).status_code, status)
        self.assertEqual(len(self.calls), 1)

    def test_rate_limit_is_enforced(self):
        import time
        app.state.attempts.extend([time.monotonic()] * 30)
        self.assertEqual(self.post().status_code, 429)
        self.assertFalse(self.calls)

    def test_large_body_is_rejected(self):
        with patch('main.MAX_BODY', 10):
            self.assertEqual(self.post().status_code, 413)
        self.assertFalse(self.calls)

    def test_upstream_failure_is_safe_and_not_retried(self):
        self.status = 402
        result = self.post()
        self.assertEqual(result.status_code, 402)
        self.assertEqual(result.json(), {'error': 'ai_unavailable'})
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(app.state.inflight, 0)

    def test_studio_request_is_bounded(self):
        body = {'model': 'bytedance-seed/seedream-5-0-flash', 'n': 1, 'resolution': '1K', 'aspect_ratio': '3:4',
                'prompt': 'Faithfully clean the garment photo',
                'input_references': [{'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,dGVzdA=='}}]}
        for count, status in [(2, 400), (1, 200)]:
            body['n'] = count
            result = self.client.post('/api/v1/images', json=body, headers={'Authorization': 'Bearer ' + TOKEN})
            self.assertEqual(result.status_code, status)
        self.assertEqual(len(self.calls), 1)

    def test_health_discloses_no_secrets(self):
        response = self.client.get('/healthz')
        self.assertEqual(response.status_code, 200)
        self.assertNotIn('secret', response.text)
        self.assertNotIn(TOKEN, response.text)


if __name__ == '__main__':
    unittest.main()
