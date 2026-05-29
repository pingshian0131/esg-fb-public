#!/usr/bin/env python3
"""Publish text, photo, or video posts to a Facebook Page via Meta Graph API.

Reads credentials from environment or ~/.hermes/.env (override with --dotenv):
  FB_APP_SECRET, FB_PAGE_ID, FB_PAGE_ACCESS_TOKEN, FB_LONG_LIVED_USER_TOKEN

Large videos (>= RESUMABLE_THRESHOLD bytes, default 100 MB) automatically use
Meta's Resumable Upload protocol (start/transfer/finish) so they stream from
disk instead of being read fully into memory.

Never prints tokens/secrets/proofs.
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import mimetypes
import os
import re
import sys
from pathlib import Path
from typing import Any, Dict, Optional, Union
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

GRAPH_VERSION = os.getenv("FB_GRAPH_VERSION", "v25.0")
GRAPH_BASE = f"https://graph.facebook.com/{GRAPH_VERSION}"
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".tif", ".tiff"}
VIDEO_EXTS = {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm"}

RESUMABLE_THRESHOLD = int(os.getenv("FB_RESUMABLE_THRESHOLD", str(100 * 1024 * 1024)))
DEFAULT_CHUNK_SIZE = int(os.getenv("FB_RESUMABLE_CHUNK", str(8 * 1024 * 1024)))


def load_dotenv(path: Optional[Path] = None) -> None:
    path = path or (Path.home() / ".hermes" / ".env")
    if not path.exists():
        return
    for raw in path.read_text(errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


def appsecret_proof(token: str, app_secret: str) -> str:
    return hmac.new(app_secret.encode("utf-8"), token.encode("utf-8"), hashlib.sha256).hexdigest()


_FB_TOKEN_RE = re.compile(r'EA[A-Za-z0-9_\-]{20,}')
_ACCESS_TOKEN_QS_RE = re.compile(r'(access_token=)[^&"\s]+')
_APPSECRET_PROOF_QS_RE = re.compile(r'(appsecret_proof=)[0-9a-f]{64}')
_APPSECRET_PROOF_JSON_RE = re.compile(r'("appsecret_proof"\s*:\s*")[0-9a-f]{64}')


def safe_json(data: Any) -> str:
    text = json.dumps(data, ensure_ascii=False, indent=2)
    text = _FB_TOKEN_RE.sub('***TOKEN_REDACTED***', text)
    text = _ACCESS_TOKEN_QS_RE.sub(r'\1***REDACTED***', text)
    text = _APPSECRET_PROOF_QS_RE.sub(r'\1***REDACTED***', text)
    text = _APPSECRET_PROOF_JSON_RE.sub(r'\1***REDACTED***', text)
    return text


FileSource = Union[Path, bytes]


def request_json(
    url: str,
    data: Optional[Dict[str, Any]] = None,
    files: Optional[Dict[str, FileSource]] = None,
    timeout: int = 300,
    method: Optional[str] = None,
) -> Dict[str, Any]:
    if files:
        return multipart_post(url, data or {}, files, timeout=timeout)
    body = urlencode(data or {}).encode("utf-8") if data is not None else None
    chosen_method = method or ("POST" if data is not None else "GET")
    req = Request(url, data=body, method=chosen_method)
    if body is not None:
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except HTTPError as e:
        body_text = e.read().decode("utf-8", errors="replace")
        try:
            body_json = json.loads(body_text)
        except Exception:
            body_json = {"raw": body_text[:1000]}
        raise RuntimeError(f"HTTP {e.code}: {safe_json(body_json)}") from e
    except URLError as e:
        raise RuntimeError(f"Network error: {e}") from e


def multipart_post(
    url: str,
    fields: Dict[str, Any],
    files: Dict[str, FileSource],
    timeout: int = 300,
) -> Dict[str, Any]:
    boundary = "----HermesFacebookBoundary7MA4YWxkTrZu0gW"
    chunks: list[bytes] = []
    for key, value in fields.items():
        chunks.append(f"--{boundary}\r\n".encode())
        chunks.append(f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode())
        chunks.append(str(value).encode("utf-8"))
        chunks.append(b"\r\n")
    for key, source in files.items():
        if isinstance(source, Path):
            filename = source.name
            mime = mimetypes.guess_type(str(source))[0] or "application/octet-stream"
            payload = source.read_bytes()
        else:
            filename = f"{key}.bin"
            mime = "application/octet-stream"
            payload = source
        chunks.append(f"--{boundary}\r\n".encode())
        chunks.append(f'Content-Disposition: form-data; name="{key}"; filename="{filename}"\r\n'.encode())
        chunks.append(f"Content-Type: {mime}\r\n\r\n".encode())
        chunks.append(payload)
        chunks.append(b"\r\n")
    chunks.append(f"--{boundary}--\r\n".encode())
    body = b"".join(chunks)
    req = Request(url, data=body, method="POST")
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    req.add_header("Content-Length", str(len(body)))
    try:
        with urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except HTTPError as e:
        body_text = e.read().decode("utf-8", errors="replace")
        try:
            body_json = json.loads(body_text)
        except Exception:
            body_json = {"raw": body_text[:1000]}
        raise RuntimeError(f"HTTP {e.code}: {safe_json(body_json)}") from e


def media_kind(path: Path) -> str:
    ext = path.suffix.lower()
    if ext in IMAGE_EXTS:
        return "image"
    if ext in VIDEO_EXTS:
        return "video"
    mime = mimetypes.guess_type(str(path))[0] or ""
    if mime.startswith("image/"):
        return "image"
    if mime.startswith("video/"):
        return "video"
    raise ValueError(f"Unsupported media type for {path}. Supported: images {sorted(IMAGE_EXTS)}, videos {sorted(VIDEO_EXTS)}")


def refresh_page_token(page_id: str, user_token: str, app_secret: str, dotenv_path: Path) -> Dict[str, Any]:
    proof = appsecret_proof(user_token, app_secret)
    url = f"{GRAPH_BASE}/me/accounts?" + urlencode({"access_token": user_token, "appsecret_proof": proof})
    data = request_json(url)
    page = next((p for p in data.get("data", []) if p.get("id") == page_id), None)
    if not page or not page.get("access_token"):
        raise RuntimeError(f"Page {page_id} not found in /me/accounts or no access_token returned")
    token = page["access_token"]
    if dotenv_path.exists():
        text = dotenv_path.read_text(errors="ignore")
        if re.search(r"^FB_PAGE_ACCESS_TOKEN=.*$", text, flags=re.M):
            text = re.sub(r"^FB_PAGE_ACCESS_TOKEN=.*$", "FB_PAGE_ACCESS_TOKEN=" + token, text, flags=re.M)
        else:
            text = text.rstrip() + "\nFB_PAGE_ACCESS_TOKEN=" + token + "\n"
        dotenv_path.write_text(text)
    os.environ["FB_PAGE_ACCESS_TOKEN"] = token
    return {"page_id": page.get("id"), "page_name": page.get("name"), "tasks": page.get("tasks", [])}


def publish_video_resumable(
    page_id: str,
    page_token: str,
    app_secret: str,
    media_path: Path,
    caption: str,
    chunk_size: int = DEFAULT_CHUNK_SIZE,
) -> Dict[str, Any]:
    """Upload a Page video using Meta's Resumable Upload protocol.

    See https://developers.facebook.com/docs/video-api/guides/publishing/
    """
    file_size = media_path.stat().st_size
    proof = appsecret_proof(page_token, app_secret)
    url = f"{GRAPH_BASE}/{page_id}/videos"

    start = request_json(url, {
        "upload_phase": "start",
        "file_size": str(file_size),
        "access_token": page_token,
        "appsecret_proof": proof,
    })
    upload_session_id = start.get("upload_session_id")
    video_id = start.get("video_id")
    start_offset = int(start.get("start_offset", 0))
    end_offset = int(start.get("end_offset", 0))
    if not upload_session_id:
        raise RuntimeError(f"Resumable start did not return upload_session_id: {safe_json(start)}")

    with media_path.open("rb") as fh:
        while start_offset < end_offset:
            fh.seek(start_offset)
            chunk = fh.read(min(chunk_size, end_offset - start_offset))
            transfer = request_json(url, {
                "upload_phase": "transfer",
                "upload_session_id": upload_session_id,
                "start_offset": str(start_offset),
                "access_token": page_token,
                "appsecret_proof": proof,
            }, files={"video_file_chunk": chunk})
            start_offset = int(transfer.get("start_offset", start_offset))
            end_offset = int(transfer.get("end_offset", end_offset))

    finish = request_json(url, {
        "upload_phase": "finish",
        "upload_session_id": upload_session_id,
        "description": caption,
        "access_token": page_token,
        "appsecret_proof": proof,
    })
    return {"video_id": video_id, "finish": finish}


def main() -> int:
    parser = argparse.ArgumentParser(description="Publish content to a Facebook Page")
    parser.add_argument("--media", help="Optional local media path: image or video")
    parser.add_argument("--caption", default="", help="Post message/caption/description")
    parser.add_argument("--page-id", default=None, help="Override FB_PAGE_ID")
    parser.add_argument("--dry-run", action="store_true", help="Validate and show planned action without publishing")
    parser.add_argument("--refresh-page-token", action="store_true", help="Refresh FB_PAGE_ACCESS_TOKEN from FB_LONG_LIVED_USER_TOKEN before publishing")
    parser.add_argument("--dotenv", default=str(Path.home() / ".hermes" / ".env"), help="Path to .env file")
    parser.add_argument("--force-resumable", action="store_true", help="Force resumable upload for videos regardless of size")
    parser.add_argument("--chunk-size", type=int, default=DEFAULT_CHUNK_SIZE, help="Chunk size (bytes) for resumable upload")
    args = parser.parse_args()

    dotenv_path = Path(args.dotenv)
    load_dotenv(dotenv_path)

    app_secret = os.getenv("FB_APP_SECRET")
    page_id = args.page_id or os.getenv("FB_PAGE_ID")
    page_token = os.getenv("FB_PAGE_ACCESS_TOKEN")
    user_token = os.getenv("FB_LONG_LIVED_USER_TOKEN") or os.getenv("FB_USER_ACCESS_TOKEN")

    if not app_secret or not page_id:
        raise SystemExit("Missing FB_APP_SECRET or FB_PAGE_ID")
    if args.refresh_page_token:
        if not user_token:
            raise SystemExit("Missing FB_LONG_LIVED_USER_TOKEN required for --refresh-page-token")
        refresh_page_token(page_id, user_token, app_secret, dotenv_path)
        page_token = os.getenv("FB_PAGE_ACCESS_TOKEN")
    if not page_token:
        raise SystemExit("Missing FB_PAGE_ACCESS_TOKEN")

    media_path = Path(args.media).expanduser() if args.media else None
    kind = "text"
    media_size = None
    if media_path:
        if not media_path.exists():
            raise SystemExit(f"Media file not found: {media_path}")
        kind = media_kind(media_path)
        media_size = media_path.stat().st_size

    use_resumable = (
        kind == "video"
        and media_size is not None
        and (args.force_resumable or media_size >= RESUMABLE_THRESHOLD)
    )

    if args.dry_run:
        print(safe_json({
            "ok": True,
            "dry_run": True,
            "page_id": page_id,
            "kind": kind,
            "media": str(media_path) if media_path else None,
            "media_size": media_size,
            "caption": args.caption,
            "resumable": use_resumable,
        }))
        return 0

    proof = appsecret_proof(page_token, app_secret)
    if kind == "text":
        url = f"{GRAPH_BASE}/{page_id}/feed"
        resp = request_json(url, {"message": args.caption, "access_token": page_token, "appsecret_proof": proof})
        out = {"ok": True, "kind": kind, "post_id": resp.get("id"), "caption": args.caption}
    elif kind == "image":
        url = f"{GRAPH_BASE}/{page_id}/photos"
        resp = request_json(url, {"caption": args.caption, "access_token": page_token, "appsecret_proof": proof}, {"source": media_path})
        out = {"ok": True, "kind": kind, "photo_id": resp.get("id"), "post_id": resp.get("post_id"), "caption": args.caption}
    elif use_resumable:
        assert media_path is not None
        resp = publish_video_resumable(page_id, page_token, app_secret, media_path, args.caption, chunk_size=args.chunk_size)
        out = {"ok": True, "kind": kind, "video_id": resp.get("video_id"), "caption": args.caption, "resumable": True}
    else:
        url = f"{GRAPH_BASE}/{page_id}/videos"
        resp = request_json(url, {"description": args.caption, "access_token": page_token, "appsecret_proof": proof}, {"source": media_path}, timeout=600)
        out = {"ok": True, "kind": kind, "video_id": resp.get("id"), "caption": args.caption}
    print(safe_json(out))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(safe_json({"ok": False, "error": str(exc)}), file=sys.stderr)
        raise SystemExit(1)
