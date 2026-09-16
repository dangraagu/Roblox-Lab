"""Post a clip to TikTok through the Content Posting API.

NOT YET RUNNABLE, and the header says so rather than letting someone find out at 02:00.
It needs an access token that does not exist yet: there is no TikTok developer account for this
project, and creating one plus accepting the developer terms is the owner's to do. See
docs/tiktok-api.md for the exact five steps and for why the API is not obviously worth it.

Everything below is written against the documented request shapes
(https://developers.tiktok.com/docs/en/content-posting-api-get-started, read 2026-09-10) and has
NEVER been executed against the live API. Treat every response-shape assumption as unverified
until the first real run.

    py -3 tools/tiktok_post.py <video.mp4> --title "caption #roblox"
    py -3 tools/tiktok_post.py <video.mp4> --title "..." --privacy SELF_ONLY
    py -3 tools/tiktok_post.py --whoami          just query the creator info

The token is read from a file, never from the command line: an argument lands in the shell history
and in the process list, where the publish_*.bat keys are deliberately not.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
import urllib.error
import urllib.request

API = "https://open.tiktokapis.com/v2"
TOKEN_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                          "tiktok_token.txt")

# The docs give one whole-file example and describe chunking without pinning the bounds in the
# page we read. Our clips are well under a megabyte, so they go up as a single chunk, which is the
# case the documented Content-Range example actually shows. Anything larger should have the real
# limits checked before trusting this constant.
SINGLE_CHUNK_MAX = 5 * 1024 * 1024


def read_token() -> str:
    if not os.path.exists(TOKEN_FILE):
        raise SystemExit(
            "No token at %s.\n"
            "There is no TikTok developer account for this project yet - see docs/tiktok-api.md.\n"
            "Once one exists, put ONLY the access token in that file. It is git-ignored."
            % TOKEN_FILE
        )
    tok = open(TOKEN_FILE, encoding="utf-8").read().strip()
    if not tok:
        raise SystemExit("%s is empty." % TOKEN_FILE)
    return tok


def call(path: str, token: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode("utf-8") if body is not None else b"{}"
    req = urllib.request.Request(
        API + path,
        data=data,
        method="POST",
        headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json; charset=UTF-8",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            payload = json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise SystemExit("%s -> HTTP %d: %s" % (path, e.code, e.read().decode("utf-8")[:400]))
    err = (payload.get("error") or {}).get("code")
    # A 200 is not proof: this API returns its real verdict in error.code, so a caller that only
    # checks the status line reports success on a refusal. The publish scripts in this repo
    # already learned that lesson the expensive way.
    if err and err != "ok":
        raise SystemExit("%s refused: %s" % (path, json.dumps(payload.get("error"))[:400]))
    return payload.get("data") or {}


def creator_info(token: str) -> dict:
    return call("/post/publish/creator_info/query/", token)


def upload(path: str, title: str, privacy: str, token: str) -> str:
    size = os.path.getsize(path)
    if size > SINGLE_CHUNK_MAX:
        raise SystemExit(
            "%s is %.1f MB. This tool only does the single-chunk case; check the documented "
            "chunk bounds before extending it rather than guessing them." % (path, size / 1e6)
        )

    data = call("/post/publish/video/init/", token, {
        "post_info": {
            "title": title,
            "privacy_level": privacy,
            "disable_duet": False,
            "disable_comment": False,
            "disable_stitch": False,
        },
        "source_info": {
            "source": "FILE_UPLOAD",
            "video_size": size,
            "chunk_size": size,
            "total_chunk_count": 1,
        },
    })
    publish_id, upload_url = data.get("publish_id"), data.get("upload_url")
    if not publish_id or not upload_url:
        raise SystemExit("init returned no upload target: %s" % json.dumps(data)[:300])

    body = open(path, "rb").read()
    put = urllib.request.Request(
        upload_url,
        data=body,
        method="PUT",
        headers={
            "Content-Range": "bytes 0-%d/%d" % (size - 1, size),
            "Content-Type": "video/mp4",
            "Content-Length": str(size),
        },
    )
    try:
        with urllib.request.urlopen(put, timeout=300) as r:
            code = r.status
    except urllib.error.HTTPError as e:
        raise SystemExit("upload PUT -> HTTP %d: %s" % (e.code, e.read().decode("utf-8")[:400]))
    print("uploaded %d bytes (HTTP %d)" % (size, code))
    return publish_id


def status(publish_id: str, token: str) -> dict:
    return call("/post/publish/status/fetch/", token, {"publish_id": publish_id})


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("video", nargs="?", help="path to the .mp4")
    ap.add_argument("--title", help="the caption, hashtags included")
    ap.add_argument("--privacy", default="PUBLIC_TO_EVERYONE",
                    help="PUBLIC_TO_EVERYONE | MUTUAL_FOLLOW_FRIENDS | SELF_ONLY. Note that an "
                         "UNAUDITED app posts privately whatever this says.")
    ap.add_argument("--whoami", action="store_true", help="query creator info and stop")
    args = ap.parse_args()

    token = read_token()

    if args.whoami:
        print(json.dumps(creator_info(token), indent=2))
        return 0

    if not args.video or not args.title:
        raise SystemExit("give a video and a --title, or use --whoami")
    if not os.path.exists(args.video):
        raise SystemExit("no such file: %s" % args.video)

    info = creator_info(token)
    allowed = info.get("privacy_level_options") or []
    print("posting as %s" % info.get("creator_username", "?"))
    # Ask the creator what it allows rather than assuming: the options are per-account and the
    # documented UX guidelines require querying them before every post.
    if allowed and args.privacy not in allowed:
        raise SystemExit("this account does not allow %s. It offers: %s"
                         % (args.privacy, ", ".join(allowed)))

    publish_id = upload(args.video, args.title, args.privacy, token)
    print("publish_id %s" % publish_id)
    print(json.dumps(status(publish_id, token), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
