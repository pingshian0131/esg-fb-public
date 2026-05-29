#!/usr/bin/env python3
"""
FB App .env 一鍵設定工具

流程：
  1. 讀取（或要求輸入）APP_ID / APP_SECRET / PAGE_ID
  2. 要求輸入 Short-Lived User Access Token
  3. 自動換成 Long-Lived User Access Token
  4. 自動計算 appsecret_proof 並取得 Page Access Token
  5. 寫入 ~/.hermes/.env，給 hermes agent / facebook-page-post skill 用

使用：
  python3 scripts/setup.py            # 互動模式
  python3 scripts/setup.py --token X  # 直接帶 short-lived token
  python3 scripts/setup.py --check    # 檢查現有 .env 內 token 的類型與剩餘有效期
"""

import argparse
import hmac
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

HTTP_TIMEOUT = 30  # 秒，避免客戶網路不穩時卡住沒反應

GRAPH_API_VERSION = "v25.0"
GRAPH_BASE = f"https://graph.facebook.com/{GRAPH_API_VERSION}"
# hermes agent 與 facebook-page-post skill 都讀這個位置
ENV_FILE = Path.home() / ".hermes" / ".env"


def http_get_json(url: str) -> dict:
    try:
        with urllib.request.urlopen(url, timeout=HTTP_TIMEOUT) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        raise SystemExit(f"HTTP {e.code} from FB API:\n{body}")
    except urllib.error.URLError as e:
        raise SystemExit(f"無法連線到 Facebook API（請檢查網路 / Proxy）：{e.reason}")
    except TimeoutError:
        raise SystemExit(f"連線 Facebook API 逾時（{HTTP_TIMEOUT}s），請稍後再試或檢查網路")


def calc_appsecret_proof(access_token: str, app_secret: str) -> str:
    return hmac.new(
        app_secret.encode("utf-8"),
        msg=access_token.encode("utf-8"),
        digestmod=hashlib.sha256,
    ).hexdigest()


def exchange_long_lived_token(app_id: str, app_secret: str, short_token: str) -> str:
    params = urllib.parse.urlencode({
        "grant_type": "fb_exchange_token",
        "client_id": app_id,
        "client_secret": app_secret,
        "fb_exchange_token": short_token,
    })
    data = http_get_json(f"{GRAPH_BASE}/oauth/access_token?{params}")
    if "access_token" not in data:
        raise SystemExit(f"換取 long-lived token 失敗: {data}")
    return data["access_token"]


def debug_token(token: str, app_id: str, app_secret: str) -> dict:
    """呼叫 /debug_token 取得 token 的 type / expires_at / scopes 等資訊"""
    params = urllib.parse.urlencode({
        "input_token": token,
        "access_token": f"{app_id}|{app_secret}",
    })
    data = http_get_json(f"{GRAPH_BASE}/debug_token?{params}")
    return data.get("data", {})


def classify_token(ttype: str, expires_at: int, remaining: int) -> str:
    if ttype != "USER":
        return ttype or "UNKNOWN"
    if expires_at == 0:
        return "Long-Lived (永久 user token)"
    days = remaining / 86400
    if remaining <= 0:
        return "EXPIRED"
    if days < 1:
        return "Short-Lived"
    if days < 7:
        return "Short-Lived (即將過期)"
    return "Long-Lived"


def check_tokens() -> None:
    env = load_existing_env()
    app_id = env.get("FB_APP_ID")
    app_secret = env.get("FB_APP_SECRET")
    if not (app_id and app_secret):
        sys.exit(".env 缺少 FB_APP_ID 或 FB_APP_SECRET，無法呼叫 /debug_token")

    print("=" * 60)
    print(" Token 狀態檢查")
    print("=" * 60)
    now = int(time.time())

    targets = [
        ("FB_LONG_LIVED_USER_TOKEN", env.get("FB_LONG_LIVED_USER_TOKEN")),
        ("FB_PAGE_ACCESS_TOKEN",     env.get("FB_PAGE_ACCESS_TOKEN")),
    ]

    for label, token in targets:
        print(f"\n{label}")
        if not token:
            print("  (.env 內無此欄位)")
            continue
        info = debug_token(token, app_id, app_secret)
        ttype       = info.get("type", "UNKNOWN")
        is_valid    = info.get("is_valid")
        expires_at  = int(info.get("expires_at", 0) or 0)
        data_exp    = int(info.get("data_access_expires_at", 0) or 0)
        remaining   = expires_at - now if expires_at else 0

        print(f"  type         : {ttype}")
        print(f"  is_valid     : {is_valid}")
        if expires_at == 0:
            print(f"  expires_at   : 0 (不過期)")
        else:
            iso = datetime.fromtimestamp(expires_at).isoformat(sep=' ', timespec='minutes')
            if remaining <= 0:
                print(f"  expires_at   : {iso}  ❌ 已過期")
            else:
                print(f"  expires_at   : {iso}  (剩 {remaining/86400:.1f} 天)")
        if data_exp:
            d_remaining = data_exp - now
            d_iso = datetime.fromtimestamp(data_exp).isoformat(sep=' ', timespec='minutes')
            print(f"  data_access  : {d_iso}  (剩 {d_remaining/86400:.1f} 天)")

        if ttype == "PAGE":
            kind = "Page Access Token (永久，連動 user token)" if expires_at == 0 else "Page Access Token (會過期)"
        else:
            kind = classify_token(ttype, expires_at, remaining)
        print(f"  判定         : {kind}")


def get_page_access_token(user_token: str, app_secret: str, page_id: str) -> str:
    proof = calc_appsecret_proof(user_token, app_secret)
    params = urllib.parse.urlencode({
        "access_token": user_token,
        "appsecret_proof": proof,
    })
    data = http_get_json(f"{GRAPH_BASE}/me/accounts?{params}")
    pages = data.get("data", [])
    for page in pages:
        if page.get("id") == page_id:
            return page["access_token"]
    available = [(p.get("id"), p.get("name")) for p in pages]
    raise SystemExit(
        f"找不到 Page ID {page_id}\n可用的 pages: {available}"
    )


def load_existing_env() -> dict:
    if not ENV_FILE.exists():
        return {}
    out = {}
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        out[k.strip()] = v.strip()
    return out


def write_env(values: dict) -> None:
    """把 values 合併進現有 ~/.hermes/.env，保留未涉及的其他設定，不整檔覆寫。"""
    merged = load_existing_env()      # 先讀回客戶既有的所有 key
    merged.update(values)             # 只更新這次產生的欄位
    merged.setdefault("FB_GRAPH_VERSION", GRAPH_API_VERSION)  # 與 .env.example 對齊

    try:
        ENV_FILE.parent.mkdir(parents=True, exist_ok=True)
        lines = [f"{k}={v}" for k, v in merged.items()]
        ENV_FILE.write_text("\n".join(lines) + "\n")
        os.chmod(ENV_FILE, 0o600)     # 僅本人可讀寫，保護 App Secret / token
    except PermissionError:
        raise SystemExit(f"無權限寫入 {ENV_FILE}，請檢查檔案/目錄權限後再試")
    except OSError as e:
        raise SystemExit(f"寫入 {ENV_FILE} 失敗：{e}")


def prompt(label: str, default: str = "", secret: bool = False) -> str:
    if not sys.stdin.isatty():
        if default:
            return default
        sys.exit(f"非互動環境，且無 {label} 可用（請用對應 --flag 傳入或先寫進 .env）")
    suffix = f" [{mask(default) if secret else default}]" if default else ""
    val = input(f"{label}{suffix}: ").strip()
    return val or default


def mask(s: str) -> str:
    if len(s) <= 8:
        return "***"
    return f"{s[:4]}...{s[-4:]}"


def main():
    parser = argparse.ArgumentParser(description="產出 hermes agent 用的 FB .env")
    parser.add_argument("--token", help="Short-Lived User Access Token（略過互動輸入）")
    parser.add_argument("--app-id", help="FB App ID")
    parser.add_argument("--app-secret", help="FB App Secret")
    parser.add_argument("--page-id", help="FB Page ID")
    parser.add_argument("--check", action="store_true",
                        help="檢查現有 .env 內 token 的類型與剩餘有效期")
    args = parser.parse_args()

    if args.check:
        check_tokens()
        return

    print("=" * 50)
    print(" FB App .env 設定工具")
    print("=" * 50)

    existing = load_existing_env()

    app_id = args.app_id or prompt("FB_APP_ID", existing.get("FB_APP_ID", ""))
    app_secret = args.app_secret or prompt(
        "FB_APP_SECRET", existing.get("FB_APP_SECRET", ""), secret=True
    )
    page_id = args.page_id or prompt("FB_PAGE_ID", existing.get("FB_PAGE_ID", ""))

    if not (app_id and app_secret and page_id):
        sys.exit("必須提供 APP_ID、APP_SECRET、PAGE_ID")

    if args.token:
        short_token = args.token
    else:
        print("\n請從 Graph API Explorer 取得 Short-Lived User Access Token")
        print("  https://developers.facebook.com/tools/explorer/")
        print(f"  選擇 App ID = {app_id}")
        print("  權限: pages_show_list, pages_read_engagement, pages_manage_posts\n")
        short_token = prompt("Short-Lived User Token", "")

    if not short_token:
        sys.exit("必須提供 short-lived user token")

    print("\n[1/2] 換取 Long-Lived User Access Token ...")
    long_token = exchange_long_lived_token(app_id, app_secret, short_token)
    print(f"      OK  ({mask(long_token)})")

    print("[2/2] 取得 Page Access Token ...")
    page_token = get_page_access_token(long_token, app_secret, page_id)
    print(f"      OK  ({mask(page_token)})")

    # 提早驗證權限齊全，避免等到實際發文才爆
    required = {"pages_show_list", "pages_read_engagement", "pages_manage_posts"}
    info = debug_token(long_token, app_id, app_secret)
    scopes = set(info.get("scopes", []))
    missing = required - scopes
    if missing:
        print(f"\n⚠️  注意：long-lived token 缺少權限 {sorted(missing)}")
        print("    發文可能會失敗，建議回 Graph API Explorer 勾齊權限後重新產生 short token。")

    write_env({
        "FB_APP_ID": app_id,
        "FB_APP_SECRET": app_secret,
        "FB_PAGE_ID": page_id,
        "FB_LONG_LIVED_USER_TOKEN": long_token,
        "FB_PAGE_ACCESS_TOKEN": page_token,
    })

    print(f"\n.env 已寫入：{ENV_FILE}（權限 600，僅本人可讀）")
    print("可執行 `python3 scripts/setup.py --check` 確認 token 狀態。")


if __name__ == "__main__":
    main()
