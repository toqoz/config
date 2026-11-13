#!/usr/bin/env python3

import argparse
from http.client import HTTPException
import json
import os
from pathlib import Path
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def notify(grok_bot_id):
    if not grok_bot_id.strip():
        raise ValueError("grok_bot_id must not be empty")
    t3_code_thread_id = os.environ.get("T3CODE_THREAD_ID", "").strip()
    if not t3_code_thread_id:
        raise ValueError("T3CODE_THREAD_ID is missing. Run this skill in T3 Code.")

    path = Path.home() / ".config/grokbot-webhook/credentials.json"
    try:
        credentials = json.loads(path.read_text())
    except FileNotFoundError:
        raise ValueError(f"Credentials not found: {path}") from None
    except (OSError, ValueError):
        raise ValueError(f"Cannot read credentials JSON: {path}") from None

    if not isinstance(credentials, dict):
        raise ValueError("Credentials must be a JSON object with url and key fields")
    url = credentials.get("url")
    key = credentials.get("key")
    if not isinstance(url, str) or not url.strip():
        raise ValueError("Credentials must contain a non-empty url string")
    if not isinstance(key, str) or not key.strip():
        raise ValueError("Credentials must contain a non-empty key string")
    if any(c in key for c in "\r\n"):
        raise ValueError("Credential key must not contain newlines")
    try:
        parsed = urlsplit(url)
        valid_url = parsed.scheme in ("http", "https") and bool(parsed.hostname)
    except ValueError:
        valid_url = False
    if not valid_url:
        raise ValueError("Credential url must be an HTTP or HTTPS URL")

    body = json.dumps({"grok_bot_id": grok_bot_id, "t3_code_thread_id": t3_code_thread_id}).encode("utf-8")
    try:
        request = Request(url, data=body, headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        }, method="POST")
        with build_opener(NoRedirect()).open(request, timeout=20) as response:
            if not 200 <= response.status < 300:
                raise ValueError(f"Webhook returned HTTP {response.status}")
    except HTTPError as error:
        raise ValueError(f"Webhook returned HTTP {error.code}") from None
    except (URLError, OSError, HTTPException, ValueError, UnicodeError):
        raise ValueError("Webhook request failed. Check the URL and network connection.") from None


def main():
    parser = argparse.ArgumentParser(description="Notify Grokbot for the current T3 Code thread")
    parser.add_argument("grok_bot_id")
    args = parser.parse_args()
    try:
        notify(args.grok_bot_id)
    except ValueError as error:
        print(f"grokbot-notify: {error}", file=sys.stderr)
        return 1
    print("Grokbot notification sent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
