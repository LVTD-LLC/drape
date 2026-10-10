"""Drape private-development AI gateway; no user accounts or photo storage."""
import asyncio
from collections import deque
from contextlib import asynccontextmanager
import hmac
import json
import os
import time

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response

from contracts import validate_request

MAX_BODY = 12_000_000
MAX_RESPONSE = 40_000_000


@asynccontextmanager
async def lifespan(app):
    key = os.environ.get('OPENROUTER_API_KEY', '')
    token = os.environ.get('DRAPE_DEVELOPMENT_TOKEN', '')
    if not key or len(token) < 32:
        raise RuntimeError('Server credentials are missing or invalid')
    app.state.key = key
    app.state.token = token
    app.state.inflight = 0
    app.state.attempts = deque()
    async with httpx.AsyncClient(timeout=150, follow_redirects=False) as client:
        app.state.client = client
        yield


app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)


def failure(status, message):
    return JSONResponse({'error': message}, status_code=status, headers={'Cache-Control': 'no-store'})


@app.get('/healthz')
async def health():
    return {'status': 'ok', 'mode': 'private-development', 'revision': os.environ.get('APP_REVISION', 'local')}


@app.post('/api/v1/{path:path}')
async def proxy(path: str, request: Request):
    if path not in ('chat/completions', 'images'):
        return failure(404, 'not_found')
    authorization = request.headers.get('authorization', '')
    if not hmac.compare_digest(authorization.encode(), ('Bearer ' + app.state.token).encode()):
        return failure(401, 'unauthorized')
    if request.headers.get('origin') or request.headers.get('content-type') != 'application/json':
        return failure(400, 'invalid_request')
    # Single worker / single replica. Each admitted attempt counts, even on failure.
    now = time.monotonic()
    while app.state.attempts and app.state.attempts[0] <= now - 3600:
        app.state.attempts.popleft()
    if app.state.inflight >= 2 or len(app.state.attempts) >= 30:
        return failure(429, 'busy')
    app.state.inflight += 1
    app.state.attempts.append(now)
    try:
        try:
            data = bytearray()
            async with asyncio.timeout(30):
                async for chunk in request.stream():
                    data.extend(chunk)
                    if len(data) > MAX_BODY:
                        return failure(413, 'too_large')
            body = json.loads(data)
            validate_request('/api/v1/' + path, body)
        except (ValueError, TypeError, AttributeError, TimeoutError):
            return failure(400, 'invalid_request')
        try:
            # One upstream call; no redirects, retries, or request/response logging.
            async with app.state.client.stream('POST', 'https://openrouter.ai/api/v1/' + path,
                headers={'Authorization': 'Bearer ' + app.state.key, 'X-OpenRouter-Title': 'Drape'}, json=body) as response:
                if response.status_code != 200:
                    status = response.status_code if response.status_code in (401, 402, 429) else 502
                    return failure(status, 'ai_unavailable')
                result = bytearray()
                async for chunk in response.aiter_bytes():
                    result.extend(chunk)
                    if len(result) > MAX_RESPONSE:
                        return failure(502, 'invalid_response')
            return Response(bytes(result), media_type='application/json', headers={'Cache-Control': 'no-store'})
        except (httpx.HTTPError, TimeoutError):
            return failure(502, 'ai_unavailable')
    finally:
        app.state.inflight -= 1
