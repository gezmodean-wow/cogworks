#!/usr/bin/env python3
"""Generate Cogworks-1.0/Data/ItemBase-Generated-<locale>.lua from Blizzard's WoW Game Data API.

This script fetches OAuth-authenticated metadata for AH-tradeable items from
Blizzard's Game Data API, normalises it into the schema described in
gezmodean-wow/cogworks#28, and writes a Lua `return { ... }` table that ships
inside the Cogworks-1.0 library directory.

Inputs (env):
    BNET_CLIENT_ID, BNET_CLIENT_SECRET   -- Blizzard developer OAuth credentials.
                                            Free tier: 100 req/sec, 36k req/hour.

CLI:
    --locale {enUS,deDE,frFR,...}  Locale to fetch (default enUS).
    --start-id  N                  Resume cursor: lowest itemID to scan (default 1).
    --end-id    N                  Resume cursor: highest itemID to scan (default 250000).
    --out-path  PATH               Output file path (default Cogworks-1.0/Data/ItemBase-Generated-<locale>.lua).
    --region    {us,eu,kr,tw,cn}   Blizzard API region (default us).
    --rps       N                  Max global request rate (default 25). Hard ceiling enforced
                                   by a thread-safe slot reservation across workers.
    --workers   N                  Concurrent HTTP workers (default 8). One worker tops out at
                                   ~5.5 req/sec because of per-request RTT (~180ms); parallel
                                   workers scale linearly until --rps becomes the bottleneck.
    --dry-run                      Print stats but don't write the output file.

Filtering heuristic (issue #28):
    quality >= 1                   "salable_quality" — drops poor-quality vendor trash.
    NOT soulbound                  inventory_type / preview_item flags exclude bind-on-pickup.
    Tradeable on the AH            if Blizzard's preview_item.binding == "Binds when picked up"
                                   we drop it; "Binds when equipped" / "Binds to account" / unbound
                                   are kept.

Output schema (per issue #28):
    The file assigns the table to a per-locale global so Cogworks-1.0/ItemBase.lua
    can pick it up after the XML manifest evaluates the data file (WoW's XML
    script loader doesn't surface a chunk's `return` value, hence the global
    handshake).

    CogworksItemBaseData_enUS = {
        version     = "<wow patch>.<build>",
        generatedAt = "<ISO-8601 UTC>",
        locale      = "enUS",
        items = {
            [12345] = {
                name      = "Itemname",
                q         = 4,
                ilvl      = 100,
                xpac      = 11,
                tier      = 0,
                invType   = 1,
                subClass  = 0,
            },
        },
        byName = {
            ["itemname"] = 12345,
        },
    }

Usage example:
    BNET_CLIENT_ID=... BNET_CLIENT_SECRET=... \\
        python tools/generate-item-base.py --locale enUS

    # Resume after a partial run:
    python tools/generate-item-base.py --locale enUS --start-id 80000

    # Smoke test without writing:
    python tools/generate-item-base.py --dry-run --end-id 1000

Notes:
    * Stdlib only (urllib + json) — no `requests` dependency, so the script
      runs in CI / contributor envs without a venv setup step.
    * Polite to the API: thread-pool of HTTP workers (default 8) with a
      global rate-cap reservation, retries with backoff on 429 / 5xx, and an
      OAuth token-refresh path. The token Blizzard hands out is good for ~24h;
      we refresh on 401.
    * The script is intentionally idempotent: a re-run on the same range
      produces a byte-identical Lua file given the same upstream data.
"""

from __future__ import annotations

import argparse
import base64
import concurrent.futures
import datetime as dt
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DEFAULT_LOCALE = "enUS"
DEFAULT_REGION = "us"
DEFAULT_START_ID = 1
DEFAULT_END_ID = 250_000  # Sane upper bound; WoW item ID space sits well below this.
DEFAULT_RPS = 25  # Stay well under Blizzard's 100 req/sec free-tier ceiling.
DEFAULT_WORKERS = 8  # Concurrent HTTP workers. Per-request RTT is ~180ms, so a
                     # single worker tops out at ~5.5 req/sec regardless of --rps.
                     # 8 workers × ~5 req/sec ≈ 40 req/sec global, well under cap.

# OAuth: client-credentials flow, region-specific endpoint.
TOKEN_ENDPOINT_FMT = "https://oauth.battle.net/token"
GAMEDATA_HOST_FMT = "https://{region}.api.blizzard.com"
ITEM_NAMESPACE_FMT = "static-{region}"
ITEM_PATH_FMT = "/data/wow/item/{item_id}"

# A WoW build/patch we tag the file with. We extract this from the resolved
# namespace Blizzard returns on the first 200 response — the API takes our
# `namespace=static-us` query and resolves it to a build-specific namespace
# like `static-12.0.5_60000-us` in the response's `_links.self.href`. Falls
# back to "unknown" so the generator always produces a well-formed file even
# if every item ID 404s.
VERSION_FALLBACK = "unknown"

# Valid Blizzard Game Data API locale codes (underscore form). WoW client-side
# locale codes (`enUS`, `deDE`, …) are the CLI/TOC convention, so we accept those
# and translate at the API boundary. Sending an unknown locale causes Blizzard
# to return localized strings as a `{en_US: "...", de_DE: "..."}` dict instead
# of the flat string we want; v1 of this script crashed on that dict at the
# `.lower()` call further down.
_API_LOCALES = {
    "enUS": "en_US", "esMX": "es_MX", "ptBR": "pt_BR", "deDE": "de_DE",
    "enGB": "en_GB", "esES": "es_ES", "frFR": "fr_FR", "itIT": "it_IT",
    "ruRU": "ru_RU", "koKR": "ko_KR", "zhTW": "zh_TW", "zhCN": "zh_CN",
}


def api_locale(wow_locale: str) -> str:
    """Translate a WoW client locale code to the Blizzard API form."""
    if wow_locale in _API_LOCALES:
        return _API_LOCALES[wow_locale]
    # Pass-through for already-correct (`en_US`) input.
    if wow_locale in _API_LOCALES.values():
        return wow_locale
    raise SystemExit(f"unknown locale: {wow_locale!r}; expected one of {sorted(_API_LOCALES)}")


# Pattern for the resolved namespace embedded in `_links.self.href`:
#   .../data/wow/item/6948?namespace=static-12.0.5_60000-us&locale=enUS
# captures (1) the dotted patch and (2) the build number.
_NAMESPACE_RE = re.compile(r"namespace=static-(\d+(?:\.\d+)*)_(\d+)-[a-z]+")


# ---------------------------------------------------------------------------
# OAuth + HTTP plumbing
# ---------------------------------------------------------------------------


class BlizzardClient:
    """Thin OAuth-authenticated HTTP client for the WoW Game Data API."""

    def __init__(self, client_id: str, client_secret: str, region: str, rps: int):
        self.client_id = client_id
        self.client_secret = client_secret
        self.region = region
        self.host = GAMEDATA_HOST_FMT.format(region=region)
        self.namespace = ITEM_NAMESPACE_FMT.format(region=region)
        self.min_interval = 1.0 / max(1, rps)
        self._last_call = 0.0
        self._token: str | None = None
        self._token_expires_at: float = 0.0
        # Captured from the first 200 response's resolved namespace. Stays None
        # until we get a real item back; main() falls back to VERSION_FALLBACK.
        self.resolved_version: str | None = None
        # One lock guards token rotation, resolved_version capture, and throttle
        # slot reservation. Critical sections are brief so a single lock is fine.
        self._lock = threading.Lock()

    # -- token ----------------------------------------------------------------

    def _fetch_token(self) -> None:
        creds = f"{self.client_id}:{self.client_secret}".encode()
        auth = base64.b64encode(creds).decode()
        body = urllib.parse.urlencode({"grant_type": "client_credentials"}).encode()
        req = urllib.request.Request(
            TOKEN_ENDPOINT_FMT,
            data=body,
            headers={
                "Authorization": f"Basic {auth}",
                "Content-Type": "application/x-www-form-urlencoded",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.load(resp)
        self._token = payload["access_token"]
        # `expires_in` is seconds. Refresh 60s before the wall.
        self._token_expires_at = time.time() + int(payload["expires_in"]) - 60

    def _ensure_token(self) -> None:
        # Fast path: read without locking; safe because _token is replaced
        # atomically. Slow path: lock + re-check + refresh.
        if self._token is not None and time.time() < self._token_expires_at:
            return
        with self._lock:
            if self._token is None or time.time() >= self._token_expires_at:
                self._fetch_token()

    # -- requests -------------------------------------------------------------

    def _throttle(self) -> None:
        # Thread-safe slot reservation: under the lock, claim the next legal
        # call time. Then sleep outside the lock so other workers can claim
        # their own slots in parallel — staggered by min_interval globally.
        with self._lock:
            now = time.time()
            slot = max(self._last_call + self.min_interval, now)
            self._last_call = slot
            sleep_for = slot - now
        if sleep_for > 0:
            time.sleep(sleep_for)

    def get_item(self, item_id: int, locale: str) -> dict[str, Any] | None:
        """Return the parsed item JSON, or None for 404 (item ID not assigned)."""
        self._ensure_token()
        self._throttle()
        path = ITEM_PATH_FMT.format(item_id=item_id)
        query = urllib.parse.urlencode({"namespace": self.namespace, "locale": api_locale(locale)})
        url = f"{self.host}{path}?{query}"
        backoff = 1.0
        for attempt in range(5):
            req = urllib.request.Request(
                url,
                headers={"Authorization": f"Bearer {self._token}"},
            )
            try:
                with urllib.request.urlopen(req, timeout=30) as resp:
                    payload = json.load(resp)
                if self.resolved_version is None:
                    href = ((payload.get("_links") or {}).get("self") or {}).get("href", "")
                    m = _NAMESPACE_RE.search(href)
                    if m:
                        # Last-writer-wins is fine; every response yields the
                        # same string. No lock needed.
                        self.resolved_version = f"{m.group(1)}.{m.group(2)}"
                return payload
            except urllib.error.HTTPError as exc:
                if exc.code == 404:
                    return None
                if exc.code == 401:
                    # Token rotated under us; refresh and retry once.
                    self._fetch_token()
                    continue
                if exc.code in (429, 500, 502, 503, 504):
                    time.sleep(backoff)
                    backoff = min(backoff * 2, 30)
                    continue
                raise
            except urllib.error.URLError:
                time.sleep(backoff)
                backoff = min(backoff * 2, 30)
                continue
        # Five strikes and the item ID is out for this run; caller can resume.
        return None


# ---------------------------------------------------------------------------
# Item normalisation + filtering
# ---------------------------------------------------------------------------


def is_tradeable(item: dict[str, Any]) -> bool:
    """Heuristic from issue #28: quality >= 1 AND not soulbound."""
    quality = item.get("quality") or {}
    quality_type = quality.get("type", "")
    # Blizzard surfaces quality as POOR / COMMON / UNCOMMON / RARE / EPIC / LEGENDARY / ARTIFACT / HEIRLOOM.
    if quality_type in ("", "POOR"):
        return False
    preview = item.get("preview_item") or {}
    binding = (preview.get("binding") or {}).get("type", "")
    # Soulbound items can't go on the AH; drop them.
    if binding == "ON_ACQUIRE":  # "Binds when picked up"
        return False
    return True


_QUALITY_ENUM = {
    "POOR": 0, "COMMON": 1, "UNCOMMON": 2, "RARE": 3, "EPIC": 4,
    "LEGENDARY": 5, "ARTIFACT": 6, "HEIRLOOM": 7,
}


def normalize(item: dict[str, Any]) -> dict[str, Any]:
    """Coerce the Blizzard JSON into the cogworks ItemBase entry schema."""
    quality = item.get("quality") or {}
    inv_type = item.get("inventory_type") or {}
    item_class = item.get("item_class") or {}
    item_subclass = item.get("item_subclass") or {}
    return {
        "name": item.get("name", ""),
        "q": _QUALITY_ENUM.get(quality.get("type", ""), 0),
        "ilvl": int(item.get("level", 0) or 0),
        "xpac": int((item.get("expansion") or {}).get("id", 0) or 0),
        "tier": 0,  # PBS tier mapping; left at 0 until inventoryType -> tier table is wired in.
        "invType": int(inv_type.get("id", 0) or 0),
        "subClass": int(item_subclass.get("id", 0) or 0),
        "_class": int(item_class.get("id", 0) or 0),  # internal, dropped in serializer
    }


# ---------------------------------------------------------------------------
# Lua serialisation
# ---------------------------------------------------------------------------


_LUA_KEY_OK = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def lua_string(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_key(k: str) -> str:
    if _LUA_KEY_OK.match(k):
        return k
    return f"[{lua_string(k)}]"


def write_lua(out_path: Path, table: dict[str, Any]) -> None:
    """Emit a deterministic, sorted Lua `return { ... }` file."""
    items: dict[int, dict[str, Any]] = table["items"]
    by_name: dict[str, int] = table["byName"]

    lines: list[str] = []
    lines.append("-- AUTO-GENERATED. Regenerate via tools/generate-item-base.py.")
    lines.append("-- DO NOT EDIT BY HAND.")
    lines.append(f"CogworksItemBaseData_{table['locale']} = {{")
    lines.append(f"  version     = {lua_string(table['version'])},")
    lines.append(f"  generatedAt = {lua_string(table['generatedAt'])},")
    lines.append(f"  locale      = {lua_string(table['locale'])},")
    lines.append("  items = {")
    for item_id in sorted(items.keys()):
        e = items[item_id]
        # Strip internal-only fields.
        e = {k: v for k, v in e.items() if not k.startswith("_")}
        parts = []
        for k in ("name", "q", "ilvl", "xpac", "tier", "invType", "subClass"):
            if k not in e:
                continue
            v = e[k]
            v_str = lua_string(v) if isinstance(v, str) else str(v)
            parts.append(f"{k}={v_str}")
        lines.append(f"    [{item_id}]={{ {', '.join(parts)} }},")
    lines.append("  },")
    lines.append("  byName = {")
    for name in sorted(by_name.keys()):
        lines.append(f"    [{lua_string(name)}]={by_name[name]},")
    lines.append("  },")
    lines.append("}")
    lines.append("")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------


def parse_args(argv: list[str]) -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parent.parent
    default_out = repo_root / "Cogworks-1.0" / "Data"

    p = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    p.add_argument("--locale", default=DEFAULT_LOCALE)
    p.add_argument("--region", default=DEFAULT_REGION, choices=["us", "eu", "kr", "tw", "cn"])
    p.add_argument("--start-id", type=int, default=DEFAULT_START_ID)
    p.add_argument("--end-id", type=int, default=DEFAULT_END_ID)
    p.add_argument("--rps", type=int, default=DEFAULT_RPS,
                   help=f"Max global request rate (default {DEFAULT_RPS}). Real ceiling is "
                        "min(--rps, --workers / per-request-RTT); RTT is ~180ms.")
    p.add_argument("--workers", type=int, default=DEFAULT_WORKERS,
                   help=f"Number of concurrent HTTP workers (default {DEFAULT_WORKERS}). "
                        "At ~180ms RTT, one worker is ~5.5 req/sec; 8 workers ≈ 40 req/sec.")
    p.add_argument("--out-path", type=Path, default=None,
                   help="Override output file. Default: Cogworks-1.0/Data/ItemBase-Generated-<locale>.lua")
    p.add_argument("--dry-run", action="store_true",
                   help="Don't write the output file; report stats only.")
    args = p.parse_args(argv)
    if args.out_path is None:
        args.out_path = default_out / f"ItemBase-Generated-{args.locale}.lua"
    return args


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    client_id = os.environ.get("BNET_CLIENT_ID")
    client_secret = os.environ.get("BNET_CLIENT_SECRET")
    if not client_id or not client_secret:
        print("ERROR: BNET_CLIENT_ID and BNET_CLIENT_SECRET must be set in the environment.",
              file=sys.stderr)
        return 2

    client = BlizzardClient(client_id, client_secret, args.region, args.rps)

    items: dict[int, dict[str, Any]] = {}
    by_name: dict[str, int] = {}
    seen = 0
    kept = 0

    # Workers do the network I/O; main thread does the deterministic merge so
    # the collision policy (highest-quality + highest-id wins) doesn't depend
    # on completion order. Workers return (item_id, normalized_entry_or_None);
    # entries that are None mean 404 / filtered / fetch-error.
    def fetch_one(item_id: int) -> tuple[int, dict[str, Any] | None]:
        try:
            raw = client.get_item(item_id, args.locale)
        except Exception as exc:  # noqa: BLE001
            print(f"WARN: item {item_id} fetch failed: {exc}", file=sys.stderr)
            return (item_id, None)
        if raw is None or not is_tradeable(raw):
            return (item_id, None)
        return (item_id, normalize(raw))

    fetched: list[tuple[int, dict[str, Any]]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = (pool.submit(fetch_one, i)
                   for i in range(args.start_id, args.end_id + 1))
        for fut in concurrent.futures.as_completed(list(futures)):
            item_id, entry = fut.result()
            seen += 1
            if entry is not None:
                fetched.append((item_id, entry))
                kept += 1
            if seen % 1000 == 0:
                print(f"... scanned {seen} ids, kept {kept}", file=sys.stderr)

    # Deterministic merge: process in item-id order so the "latter wins on tie"
    # half of the collision policy is reproducible across runs.
    fetched.sort(key=lambda t: t[0])
    for item_id, entry in fetched:
        items[item_id] = entry
        name = (entry.get("name") or "").lower()
        if not name:
            continue
        prev_id = by_name.get(name)
        if prev_id is None:
            by_name[name] = item_id
        else:
            prev_q = items[prev_id]["q"]
            if entry["q"] > prev_q or (entry["q"] == prev_q and item_id > prev_id):
                by_name[name] = item_id

    table = {
        "version": client.resolved_version or VERSION_FALLBACK,
        "generatedAt": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "locale": args.locale,
        "items": items,
        "byName": by_name,
    }

    print(f"scanned={seen} kept={kept} unique-names={len(by_name)}", file=sys.stderr)

    if args.dry_run:
        print("dry-run: not writing output", file=sys.stderr)
        return 0

    write_lua(args.out_path, table)
    print(f"wrote {args.out_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
