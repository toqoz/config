import json
from http.client import HTTPException, InvalidURL
from pathlib import Path
import socket
import ssl
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


class DeliveryError(Exception):
    def __init__(self, code, retryable):
        super().__init__(code)
        self.code = code
        self.retryable = retryable


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def load_credentials():
    path = Path.home() / '.config/grokbot-webhook/credentials.json'
    try:
        credentials = json.loads(path.read_text())
    except FileNotFoundError:
        raise DeliveryError('credentials_missing', True) from None
    except (OSError, ValueError):
        raise DeliveryError('credentials_invalid', True) from None
    if not isinstance(credentials, dict):
        raise DeliveryError('credentials_invalid', False)
    url, key = credentials.get('url'), credentials.get('key')
    if not isinstance(url, str) or not url.strip():
        raise DeliveryError('url_invalid', False)
    if not isinstance(key, str) or not key.strip() or any(c in key for c in '\r\n'):
        raise DeliveryError('key_invalid', False)
    try:
        parsed = urlsplit(url)
        valid = parsed.scheme in ('http', 'https') and bool(parsed.hostname)
        parsed.port
    except ValueError:
        valid = False
    if not valid or any(c in url for c in '\r\n'):
        raise DeliveryError('url_invalid', False)
    return url, key


def post(payload, *, timeout=10):
    url, key = load_credentials()
    try:
        request = Request(url, data=json.dumps(payload, ensure_ascii=False).encode('utf-8'),
                          headers={'Authorization': f'Bearer {key}',
                                   'Content-Type': 'application/json'}, method='POST')
        with build_opener(NoRedirect()).open(request, timeout=timeout) as response:
            if not 200 <= response.status < 300:
                raise DeliveryError(f'http_{response.status}', response.status >= 500)
    except HTTPError as error:
        code = error.code
        error.close()
        raise DeliveryError(f'http_{code}', code in (408, 429) or code >= 500) from None
    except URLError as error:
        reason = error.reason
        if isinstance(reason, socket.gaierror):
            raise DeliveryError('dns_failure', True) from None
        if isinstance(reason, ssl.SSLError):
            raise DeliveryError('tls_failure', False) from None
        if isinstance(reason, TimeoutError):
            raise DeliveryError('timeout', True) from None
        raise DeliveryError('connection_failure', True) from None
    except InvalidURL:
        raise DeliveryError('url_invalid', False) from None
    except TimeoutError:
        raise DeliveryError('timeout', True) from None
    except ssl.SSLError:
        raise DeliveryError('tls_failure', False) from None
    except (OSError, HTTPException):
        raise DeliveryError('connection_failure', True) from None
    except ValueError:
        raise DeliveryError('request_invalid', False) from None
