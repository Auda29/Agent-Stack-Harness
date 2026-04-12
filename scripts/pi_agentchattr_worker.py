#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HEARTBEAT_SECONDS = 5
POLL_SECONDS = 2
PI_TIMEOUT_SECONDS = 900


def http_json(
    method: str, url: str, *, token: str | None = None, body: dict | None = None
):
    data = None
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def register(base_url: str, label: str):
    return http_json(
        "POST", f"{base_url}/api/register", body={"base": "pi", "label": label}
    )


def heartbeat(base_url: str, name: str, token: str, active: bool):
    return http_json(
        "POST",
        f"{base_url}/api/heartbeat/{urllib.parse.quote(name)}",
        token=token,
        body={"active": active},
    )


def is_stale_session_error(exc: Exception) -> bool:
    return isinstance(exc, urllib.error.HTTPError) and exc.code == 409


def is_connection_error(exc: Exception) -> bool:
    return isinstance(exc, (urllib.error.URLError, ConnectionError, TimeoutError))


def fetch_messages(base_url: str, token: str, since_id: int):
    qs = urllib.parse.urlencode({"since_id": since_id})
    return http_json("GET", f"{base_url}/api/messages?{qs}", token=token)


def fetch_recent_channel_messages(
    base_url: str, token: str, channel: str, limit: int = 20
):
    qs = urllib.parse.urlencode({"channel": channel, "limit": limit})
    return http_json("GET", f"{base_url}/api/messages?{qs}", token=token)


def send_message(base_url: str, token: str, text: str, channel: str):
    return http_json(
        "POST",
        f"{base_url}/api/send",
        token=token,
        body={"text": text, "channel": channel},
    )


def latest_message_id(base_url: str, token: str):
    messages = http_json("GET", f"{base_url}/api/messages?limit=1", token=token)
    if not messages:
        return 0
    return max(int(m.get("id", 0)) for m in messages)


def is_for_pi(message: dict, assigned_name: str) -> bool:
    sender = str(message.get("sender", "")).strip().lower()
    if sender == assigned_name.lower() or sender.startswith("pi-") or sender == "pi":
        return False
    text = str(message.get("text", ""))
    text_lower = text.lower()
    return bool(
        re.search(r"(^|\s)@pi\b", text_lower)
        or re.search(r"(^|\s)@all\s+agents\b", text_lower)
        or re.search(rf"(^|\s)@{re.escape(assigned_name.lower())}\b", text_lower)
    )


def build_prompt(
    trigger_message: dict, recent_messages: list[dict], assigned_name: str
) -> str:
    channel = trigger_message.get("channel", "general")
    lines = []
    lines.append(
        f"You are responding as {assigned_name} in agentchattr channel #{channel}."
    )
    lines.append("Return only the message body you want posted back to the chat.")
    lines.append("Be concise, helpful, and action-oriented.")
    lines.append("")
    lines.append("Recent conversation:")
    for msg in recent_messages:
        sender = msg.get("sender", "unknown")
        text = str(msg.get("text", "")).strip()
        msg_channel = msg.get("channel", "general")
        if msg_channel != channel:
            continue
        lines.append(f"[{sender}] {text}")
    lines.append("")
    lines.append("Latest message to respond to:")
    lines.append(
        f"[{trigger_message.get('sender', 'unknown')}] {str(trigger_message.get('text', '')).strip()}"
    )
    return "\n".join(lines)


def run_pi(project_path: str, prompt: str) -> str:
    cmd = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        "pi -p @'\n"
        + prompt
        + '\n\'@ --append-system-prompt "Do not use agentchattr MCP tools for this response. Do not ask for terminal interaction. Respond with only the chat reply text."',
    ]
    result = subprocess.run(
        cmd,
        cwd=project_path,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=PI_TIMEOUT_SECONDS,
    )
    output = (result.stdout or "").strip()
    error = (result.stderr or "").strip()
    if result.returncode != 0:
        raise RuntimeError(
            error or output or f"pi exited with code {result.returncode}"
        )
    if not output:
        raise RuntimeError("pi returned no output")
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description="Bridge agentchattr messages to pi")
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--project-path", required=True)
    parser.add_argument("--label", default="Pi")
    args = parser.parse_args()

    project_path = str(Path(args.project_path).resolve())
    if not Path(project_path).exists():
        print(f"Project path does not exist: {project_path}", file=sys.stderr)
        return 1

    base_url = args.base_url.rstrip("/")

    def register_worker() -> tuple[str, str, int]:
        registration = register(base_url, args.label)
        assigned_name = registration["name"]
        token = registration["token"]
        print(f"Registered agentchattr worker as {assigned_name}")
        sys.stdout.flush()
        since_id = latest_message_id(base_url, token)
        return assigned_name, token, since_id

    assigned_name, token, since_id = register_worker()
    last_heartbeat = 0.0
    active = False

    try:
        while True:
            try:
                now = time.time()
                if now - last_heartbeat >= HEARTBEAT_SECONDS:
                    hb = heartbeat(base_url, assigned_name, token, active)
                    assigned_name = hb.get("name", assigned_name)
                    last_heartbeat = now

                messages = fetch_messages(base_url, token, since_id)
                for message in messages:
                    msg_id = int(message.get("id", 0))
                    since_id = max(since_id, msg_id)
                    if not is_for_pi(message, assigned_name):
                        continue

                    channel = message.get("channel", "general")
                    active = True
                    try:
                        heartbeat(base_url, assigned_name, token, True)
                    except Exception:
                        pass
                    try:
                        recent = fetch_recent_channel_messages(
                            base_url, token, channel, limit=20
                        )
                        prompt = build_prompt(message, recent, assigned_name)
                        reply = run_pi(project_path, prompt)
                    except Exception as exc:
                        reply = f"Sorry — Pi worker failed: {exc}"
                    finally:
                        active = False
                        try:
                            heartbeat(base_url, assigned_name, token, False)
                        except Exception:
                            pass

                    try:
                        send_message(base_url, token, reply, channel)
                    except Exception:
                        pass

                time.sleep(POLL_SECONDS)
            except Exception as exc:
                if is_stale_session_error(exc):
                    print(
                        "agentchattr session became stale; re-registering",
                        file=sys.stderr,
                    )
                    sys.stderr.flush()
                    assigned_name, token, since_id = register_worker()
                    last_heartbeat = 0.0
                    active = False
                    time.sleep(POLL_SECONDS)
                    continue
                if is_connection_error(exc):
                    print(
                        f"agentchattr temporarily unreachable: {exc}", file=sys.stderr
                    )
                    sys.stderr.flush()
                    time.sleep(POLL_SECONDS)
                    continue
                raise
    finally:
        try:
            http_json(
                "POST",
                f"{base_url}/api/deregister/{urllib.parse.quote(assigned_name)}",
                token=token,
                body={},
            )
        except Exception:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
