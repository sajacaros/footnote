import gzip
import zlib

from starlette.types import ASGIApp, Message, Receive, Scope, Send


class GzipRequestMiddleware:
    """`Content-Encoding: gzip` 요청 본문을 풀어서 넘긴다. Starlette에는 이 기능이 없다."""

    def __init__(self, app: ASGIApp, max_bytes: int) -> None:
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        headers = dict(scope["headers"])
        if headers.get(b"content-encoding", b"").lower() != b"gzip":
            await self.app(scope, receive, send)
            return

        chunks = []
        size = 0
        while True:
            message = await receive()
            chunk = message.get("body", b"")
            size += len(chunk)
            if size > self.max_bytes:
                await _reject(send, 413, b"request body too large")
                return
            chunks.append(chunk)
            if not message.get("more_body", False):
                break

        try:
            decompressor = zlib.decompressobj(16 + zlib.MAX_WBITS)
            body = decompressor.decompress(b"".join(chunks), self.max_bytes + 1)
            if len(body) > self.max_bytes or decompressor.unconsumed_tail:
                await _reject(send, 413, b"request body too large")
                return
        except (zlib.error, gzip.BadGzipFile):
            await _reject(send, 400, b"invalid gzip body")
            return

        new_headers = [
            (key, value)
            for key, value in scope["headers"]
            if key not in (b"content-encoding", b"content-length")
        ]
        new_headers.append((b"content-length", str(len(body)).encode()))
        scope = {**scope, "headers": new_headers}

        sent = False

        async def receive_body() -> Message:
            nonlocal sent
            if sent:
                return await receive()
            sent = True
            return {"type": "http.request", "body": body, "more_body": False}

        await self.app(scope, receive_body, send)


async def _reject(send: Send, status: int, detail: bytes) -> None:
    await send(
        {
            "type": "http.response.start",
            "status": status,
            "headers": [(b"content-type", b"text/plain; charset=utf-8")],
        }
    )
    await send({"type": "http.response.body", "body": detail})
