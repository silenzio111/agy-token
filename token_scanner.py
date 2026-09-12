#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
token_scanner.py - 多工具统一 Token 扫描器
支持:
1. Google Antigravity (agy GUI & CLI)
2. OpenAI Codex (Codex CLI / Sessions)
3. Anthropic Claude Code (Claude Code CLI Projects)
"""

import os
import glob
import sqlite3
import re
import json
from datetime import datetime, date


# 跨进程扫描缓存。原生 macOS 应用每次刷新都会启动一个新的 Python
# 进程，因此仅使用模块级缓存无法避免重复读取历史 JSONL 文件。
SCAN_CACHE_VERSION = 1
SCAN_CACHE_FILE = os.path.expanduser("~/Library/Application Support/AgyToken/scan_cache.json")


def _file_signature(filepath):
    """返回文件的轻量签名；文件未找到时返回 None。"""
    try:
        st = os.stat(filepath)
        mtime_ns = getattr(st, "st_mtime_ns", int(st.st_mtime * 1_000_000_000))
        return [int(st.st_size), int(mtime_ns)]
    except OSError:
        return None


def _load_scan_cache():
    """读取跨进程扫描缓存，损坏或版本不匹配时从空缓存开始。"""
    empty = {
        "version": SCAN_CACHE_VERSION,
        "price_signature": None,
        "files": {}
    }
    try:
        with open(SCAN_CACHE_FILE, "r", encoding="utf-8") as f:
            cache = json.load(f)
        if not isinstance(cache, dict) or cache.get("version") != SCAN_CACHE_VERSION:
            return empty
        if not isinstance(cache.get("files"), dict):
            cache["files"] = {}
        return cache
    except Exception:
        return empty


def _save_scan_cache(cache):
    """原子写入扫描缓存，避免应用中途退出留下半个 JSON。"""
    try:
        os.makedirs(os.path.dirname(SCAN_CACHE_FILE), exist_ok=True)
        tmp_file = SCAN_CACHE_FILE + ".tmp"
        with open(tmp_file, "w", encoding="utf-8") as f:
            json.dump(cache, f, ensure_ascii=False, separators=(",", ":"))
        os.replace(tmp_file, SCAN_CACHE_FILE)
    except Exception:
        pass


def _get_cached_conversation(cache, cache_key, signature, today_date):
    """命中缓存时返回副本，并按当前日期更新 is_today。"""
    entry = cache.get("files", {}).get(cache_key)
    if not isinstance(entry, dict) or entry.get("signature") != signature:
        return None

    conversation = entry.get("conversation")
    if not isinstance(conversation, dict) or conversation.get("total", 0) <= 0:
        return None

    result = dict(conversation)
    try:
        result["is_today"] = datetime.fromtimestamp(float(result.get("mtime", 0))).date() == today_date
    except Exception:
        result["is_today"] = False
    return result


def _put_cached_conversation(cache, cache_key, signature, conversation):
    cache.setdefault("files", {})[cache_key] = {
        "signature": signature,
        "conversation": conversation
    }


def _drop_cached_conversation(cache, cache_key):
    cache.get("files", {}).pop(cache_key, None)

def parse_proto(data):
    """解析 protobuf 紧凑字节流"""
    fields = []
    idx = 0
    length_data = len(data)
    while idx < length_data:
        b = data[idx]
        idx += 1
        tag = b >> 3
        wire_type = b & 7
        if wire_type == 0:  # Varint
            val = 0
            shift = 0
            while idx < length_data:
                byte = data[idx]
                idx += 1
                val |= (byte & 0x7f) << shift
                shift += 7
                if not (byte & 0x80):
                    break
            fields.append((tag, "varint", val))
        elif wire_type == 2:  # Length-delimited
            length = 0
            shift = 0
            while idx < length_data:
                byte = data[idx]
                idx += 1
                length |= (byte & 0x7f) << shift
                shift += 7
                if not (byte & 0x80):
                    break
            val = data[idx:idx+length]
            idx += length
            fields.append((tag, "bytes", val))
        elif wire_type == 1:  # 64-bit
            val = data[idx:idx+8]
            idx += 8
            fields.append((tag, "64bit", val))
        elif wire_type == 5:  # 32-bit
            val = data[idx:idx+4]
            idx += 4
            fields.append((tag, "32bit", val))
        else:
            break
    return fields

def clean_title(raw_text):
    """清理并缩减提问文本"""
    if not raw_text:
        return "未命名会话"
    cleaned = re.sub(r"<[^>]+>", " ", str(raw_text))
    cleaned = " ".join(cleaned.split())
    if len(cleaned) > 50:
        return cleaned[:47] + "..."
    return cleaned if cleaned else "未命名会话"

# =====================================================================
# 官方/行业标准全量模型价格引擎 (支持在线同步与离线兜底)
def _get_model_prices_path():
    app_support = os.path.expanduser("~/Library/Application Support/AgyToken")
    user_file = os.path.join(app_support, "model_prices.json")
    if os.path.exists(user_file):
        return user_file
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "model_prices.json")

MODEL_PRICES_FILE = _get_model_prices_path()

PRICES_LOOKUP_CACHE = None
PRICES_DB_CACHE = None

# 内置核心官方模型标准价格兜底表 (单位: 每 100 万 Tokens 美元，输入 / 输出 / 缓存命中)
BUILTIN_OFFICIAL_PRICES = {
    # OpenAI Codex / GPT 系列
    "gpt-5.6-luna": (0.20, 1.20, 0.02),
    "gpt-5.6-terra": (2.00, 12.00, 0.20),
    "gpt-5.6-sol": (4.00, 20.00, 0.40),
    "gpt-5.5": (5.00, 30.00, 0.50),
    "gpt-5.4": (2.50, 15.00, 0.25),
    "gpt-5.3-codex": (1.75, 14.00, 0.175),
    "gpt-5.2-codex": (1.75, 14.00, 0.175),
    "gpt-5.1-codex": (1.25, 10.00, 0.125),
    "gpt-5.1-codex-max": (1.25, 10.00, 0.125),
    "gpt-5.1-codex-mini": (0.25, 2.00, 0.025),
    "gpt-5-codex": (1.25, 10.00, 0.125),
    "gpt-5": (1.25, 10.00, 0.125),
    "gpt-5-pro": (15.00, 120.00, 1.50),
    "gpt-4.1": (2.00, 8.00, 0.50),
    "gpt-4o": (2.50, 10.00, 1.25),
    "gpt-4o-mini": (0.15, 0.60, 0.075),
    "o1": (15.00, 60.00, 7.50),
    "o1-mini": (1.10, 4.40, 0.55),
    "o3": (2.00, 8.00, 0.50),
    "o3-mini": (1.10, 4.40, 0.55),
    
    # Anthropic Claude 系列
    "claude-3-7-sonnet": (3.00, 15.00, 0.30),
    "claude-sonnet-4-6": (3.00, 15.00, 0.30),
    "claude-3-5-sonnet": (3.00, 15.00, 0.30),
    "claude-3-opus": (15.00, 75.00, 1.50),
    "claude-3-5-haiku": (0.80, 4.00, 0.08),

    # Google Gemini (Antigravity) 系列
    "gemini-3.8-flash": (0.75, 3.75, 0.075),
    "gemini-3.7-flash": (0.75, 3.75, 0.075),
    "gemini-2.5-flash": (0.30, 2.50, 0.03),
    "gemini-2.0-flash": (0.10, 0.40, 0.025),
    "gemini-2.0-flash-lite": (0.075, 0.30, 0.0187),
    "gemini-2.5-pro": (1.25, 10.00, 0.125),

    # DeepSeek 系列
    "deepseek-v4-flash": (0.44, 1.32, 0.014),
    "deepseek-v4-pro": (1.32, 3.96, 0.044),
    "deepseek-chat": (0.28, 0.42, 0.028),
    "deepseek-reasoner": (0.28, 0.42, 0.028),
}

def sync_official_prices_online():
    """从官方持续维护的开源标准库 (LiteLLM) 异步拉取并更新最新全量官方模型价格表"""
    import urllib.request
    url = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    try:
        app_support = os.path.expanduser("~/Library/Application Support/AgyToken")
        os.makedirs(app_support, exist_ok=True)
        target_file = os.path.join(app_support, "model_prices.json")

        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=6) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if isinstance(data, dict) and len(data) > 100:
                tmp_file = target_file + ".tmp"
                with open(tmp_file, "w", encoding="utf-8") as f:
                    json.dump(data, f, ensure_ascii=False, indent=2)
                os.replace(tmp_file, target_file)
                global PRICES_LOOKUP_CACHE, PRICES_DB_CACHE, MODEL_PRICES_FILE
                MODEL_PRICES_FILE = target_file
                PRICES_DB_CACHE = data
                PRICES_LOOKUP_CACHE = None
                return True
    except Exception:
        pass
    return False


def get_official_lookup():
    """构建快速官方模型检索映射字典"""
    global PRICES_LOOKUP_CACHE, PRICES_DB_CACHE
    if PRICES_LOOKUP_CACHE is not None:
        return PRICES_LOOKUP_CACHE

    lookup = {}
    if os.path.exists(MODEL_PRICES_FILE):
        try:
            if PRICES_DB_CACHE is None:
                with open(MODEL_PRICES_FILE, "r", encoding="utf-8") as f:
                    PRICES_DB_CACHE = json.load(f)
            if isinstance(PRICES_DB_CACHE, dict):
                for k, v in PRICES_DB_CACHE.items():
                    if not isinstance(v, dict):
                        continue
                    inp = (v.get("input_cost_per_token") or 0) * 1e6
                    out = (v.get("output_cost_per_token") or 0) * 1e6
                    cache = (v.get("cache_read_input_token_cost") or 0) * 1e6
                    if inp == 0 and out == 0:
                        continue
                    lookup[k.lower()] = (inp, out, cache, k)
                    for prefix in [
                        "openai/", "anthropic/", "google/", "deepseek/",
                        "openrouter/openai/", "openrouter/google/",
                        "openrouter/anthropic/", "openrouter/deepseek/"
                    ]:
                        if k.lower().startswith(prefix):
                            nk = k.lower()[len(prefix):]
                            if nk not in lookup or "openrouter" not in k:
                                lookup[nk] = (inp, out, cache, k)
        except Exception as e:
            print("读取 model_prices.json 异常:", e)

    # 用内置官方核心字典补充兜底
    for k, (inp, out, c) in BUILTIN_OFFICIAL_PRICES.items():
        if k.lower() not in lookup:
            lookup[k.lower()] = (inp, out, c, f"official/{k}")

    PRICES_LOOKUP_CACHE = lookup
    return lookup

def get_model_pricing(model_str):
    """
    根据模型名在官方标准价格库中智能匹配单价 ($ / 1M Tokens)
    返回: (r_in, r_out, r_cache, matched_model_name)
    """
    lookup = get_official_lookup()
    m = str(model_str).lower().strip()
    if not m:
        return 0.50, 2.00, 0.05, "default"

    if "/" in m:
        m = m.split("/")[-1].strip()
    if "," in m:
        m = m.split(",")[0].strip()

    # 1. 精确匹配
    if m in lookup:
        inp, out, c, name = lookup[m]
        return inp, out, (c if c > 0 else inp * 0.1), name

    # 2. 尾缀匹配 (如 openai/gpt-5.6-luna 匹配 gpt-5.6-luna)
    for k, v in lookup.items():
        if k == m or k.endswith("/" + m):
            inp, out, c, name = v
            return inp, out, (c if c > 0 else inp * 0.1), name

    # 3. 子串匹配
    for k, v in lookup.items():
        if m in k:
            inp, out, c, name = v
            return inp, out, (c if c > 0 else inp * 0.1), name

    # 4. 族系通用兜底
    if "flash" in m:
        return 0.75, 3.75, 0.075, "gemini-flash"
    elif "pro" in m:
        return 1.25, 10.00, 0.125, "gemini-pro"
    elif "codex" in m or "gpt-5" in m:
        return 1.25, 10.00, 0.125, "gpt-5-standard"

    return 0.50, 2.00, 0.05, "fallback"

def calc_cost_usd(prompt, output, cached, model_str="", return_details=False):
    """
    根据官方实时标准价格表计算会话成本与省流
    """
    r_in, r_out, r_c, matched_name = get_model_pricing(model_str)
    cost = (prompt * r_in + output * r_out + cached * r_c) / 1_000_000.0
    saved = (cached * max(0.0, r_in - r_c)) / 1_000_000.0
    if return_details:
        return cost, saved, {"in": r_in, "out": r_out, "cache": r_c, "matched": matched_name}
    return cost, saved

# =====================================================================
# 1. Antigravity 扫描引擎
# =====================================================================
def scan_agy_conversations(cache=None):
    """扫描 Google Antigravity GUI 与 CLI 本地 SQLite 对话数据"""
    if cache is None:
        cache = _load_scan_cache()
    sources = [
        ("AGY-GUI", os.path.expanduser("~/.gemini/antigravity")),
        ("AGY-CLI", os.path.expanduser("~/.gemini/antigravity-cli"))
    ]
    today_date = date.today()
    conversations = []
    seen_cids = set()

    for src_name, base_dir in sources:
        conv_dir = os.path.join(base_dir, "conversations")
        if not os.path.exists(conv_dir):
            continue

        for db_file in glob.glob(os.path.join(conv_dir, "*.db")):
            cid = os.path.basename(db_file).replace(".db", "")
            if cid in seen_cids:
                continue
            seen_cids.add(cid)

            tfile = os.path.join(base_dir, "brain", cid, ".system_generated", "logs", "transcript.jsonl")
            cache_key = "agy:" + os.path.abspath(db_file)
            signature = {
                "db": _file_signature(db_file),
                "transcript": _file_signature(tfile)
            }
            cached = _get_cached_conversation(cache, cache_key, signature, today_date)
            if cached is not None:
                conversations.append(cached)
                continue

            try:
                mtime = os.path.getmtime(db_file)
            except OSError:
                continue

            dt = datetime.fromtimestamp(mtime)
            is_today = (dt.date() == today_date)
            time_str = dt.strftime("%Y-%m-%d %H:%M")

            title = cid[:8] + "..."
            if os.path.exists(tfile):
                try:
                    with open(tfile, "r", encoding="utf-8", errors="ignore") as tf:
                        for line in tf:
                            obj = json.loads(line)
                            if obj.get("type") == "USER_INPUT" and obj.get("content"):
                                title = clean_title(obj["content"])
                                break
                except Exception:
                    pass

            try:
                conn = sqlite3.connect(f"file:{db_file}?mode=ro", uri=True)
                cur = conn.cursor()
                cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='gen_metadata';")
                if not cur.fetchone():
                    conn.close()
                    continue
                cur.execute("SELECT idx, data FROM gen_metadata;")
                rows = cur.fetchall()
                conn.close()
            except Exception:
                continue

            if not rows:
                _drop_cached_conversation(cache, cache_key)
                continue

            prompt_tokens = 0
            output_tokens = 0
            cached_tokens = 0
            thought_tokens = 0
            models = set()

            for _, data in rows:
                m = re.search(rb"(gemini-[a-zA-Z0-9\.\-]+|claude-[a-zA-Z0-9\.\-]+)", data)
                if m:
                    models.add(m.group(1).decode("utf-8", errors="ignore").replace("-high", ""))

                f1 = parse_proto(data)
                for t1, w1, v1 in f1:
                    if t1 == 1 and w1 == "bytes":
                        f2 = parse_proto(v1)
                        for t2, w2, v2 in f2:
                            if t2 == 4 and w2 == "bytes":
                                f4 = parse_proto(v2)
                                for t4, w4, v4 in f4:
                                    if w4 == "varint":
                                        if t4 == 2:
                                            prompt_tokens += v4
                                        elif t4 == 3:
                                            output_tokens += v4
                                        elif t4 == 5:
                                            cached_tokens += v4
                                        elif t4 == 9:
                                            thought_tokens += v4

            total_tokens = prompt_tokens + output_tokens + cached_tokens
            if total_tokens == 0:
                _drop_cached_conversation(cache, cache_key)
                continue

            model_name = "/".join(models) if models else "gemini"
            cost_usd, saved_usd, rates = calc_cost_usd(prompt_tokens, output_tokens, cached_tokens, model_name, return_details=True)

            conversation = {
                "tool": "Antigravity",
                "source": src_name,
                "cid": cid,
                "title": title,
                "time": time_str,
                "mtime": mtime,
                "is_today": is_today,
                "turns": len(rows),
                "prompt": prompt_tokens,
                "output": output_tokens,
                "cached": cached_tokens,
                "thoughts": thought_tokens,
                "total": total_tokens,
                "cost_usd": cost_usd,
                "saved_usd": saved_usd,
                "models": model_name,
                "rates": rates
            }
            conversations.append(conversation)
            _put_cached_conversation(cache, cache_key, signature, conversation)

    return conversations

# =====================================================================
# 2. Codex 扫描引擎 (仅使用 sessions 物理目录，纯本地无侵入)
# =====================================================================
def extract_codex_meta_from_head(filepath):
    """从 session rollout jsonl 前部提取用户提问与模型名称"""
    title = None
    model = None
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for _ in range(40):
                line = f.readline()
                if not line:
                    break
                try:
                    obj = json.loads(line)
                    t = obj.get('type')
                    p = obj.get('payload', {})
                    if not model and (t == 'turn_context' or t == 'session_meta'):
                        model = p.get('model')
                    elif not title:
                        if t == 'event_msg' and p.get('type') == 'user_message':
                            msg = p.get('message')
                            if msg and isinstance(msg, str) and not msg.startswith('<environment_context>'):
                                title = msg
                        elif t == 'response_item' and p.get('role') == 'user':
                            content = p.get('content', [])
                            if isinstance(content, list):
                                for item in content:
                                    if item.get('type') == 'input_text':
                                        txt = item.get('text', '')
                                        if txt and not txt.startswith('<environment_context>'):
                                            title = txt
                                            break
                except Exception:
                    pass
                if title and model:
                    break
    except Exception:
        pass
    return title, model

def extract_codex_tokens_from_file(filepath):
    """从 Codex session rollout jsonl 提取准确的 token 消耗细项与最新时间戳"""
    size = os.path.getsize(filepath)
    if size == 0:
        return None, None

    # 优先倒序搜索尾部 256KB
    read_size = min(size, 262144)
    token_info = None
    last_time_str = None

    try:
        with open(filepath, 'rb') as f:
            f.seek(size - read_size)
            tail_chunk = f.read().decode('utf-8', errors='ignore')

        lines = tail_chunk.splitlines()
        for line in reversed(lines):
            if not last_time_str and '"timestamp"' in line:
                try:
                    obj = json.loads(line)
                    if 'timestamp' in obj:
                        last_time_str = obj['timestamp']
                except Exception:
                    pass

            if not token_info and ('total_token_usage' in line or 'thread_token_usage' in line):
                try:
                    d = json.loads(line)
                    p = d.get('payload', {})
                    u = p.get('thread_token_usage') or p.get('info', {}).get('total_token_usage')
                    if u and u.get('total_tokens', 0) > 0:
                        inp = u.get('input_tokens', 0)
                        cached = u.get('cached_input_tokens', 0)
                        out = u.get('output_tokens', 0)
                        thoughts = u.get('reasoning_output_tokens', 0)
                        tot = u.get('total_tokens', 0)
                        token_info = {
                            'total': tot,
                            'prompt': max(0, inp - cached),
                            'cached': cached,
                            'output': out,
                            'thoughts': thoughts
                        }
                except Exception:
                    pass

            if token_info and last_time_str:
                break
    except Exception:
        pass

    # 若尾部 256KB 未匹配到（例如会话末尾有超长 Tool 终端输出），则快速全文件字节流扫描
    if not token_info and size > read_size:
        try:
            with open(filepath, 'rb') as f:
                for bline in f:
                    if b'total_token_usage' in bline or b'thread_token_usage' in bline:
                        try:
                            d = json.loads(bline.decode('utf-8', errors='ignore'))
                            p = d.get('payload', {})
                            u = p.get('thread_token_usage') or p.get('info', {}).get('total_token_usage')
                            if u and u.get('total_tokens', 0) > 0:
                                inp = u.get('input_tokens', 0)
                                cached = u.get('cached_input_tokens', 0)
                                out = u.get('output_tokens', 0)
                                thoughts = u.get('reasoning_output_tokens', 0)
                                tot = u.get('total_tokens', 0)
                                token_info = {
                                    'total': tot,
                                    'prompt': max(0, inp - cached),
                                    'cached': cached,
                                    'output': out,
                                    'thoughts': thoughts
                                }
                        except Exception:
                            pass
        except Exception:
            pass

    return token_info, last_time_str

def scan_codex_tokens(cache=None):
    """
    仅使用 sessions 目录进行统计：
    物理遍历 ~/.codex/sessions/（以及 ~/.codex/archived_sessions/）下的全部 rollout-*.jsonl 会话文件，
    所有 Token、模型、提问、时间完全直接由 session 本地文件计算，完全不依赖任何 SQLite 数据库。
    """
    if cache is None:
        cache = _load_scan_cache()
    session_dirs = [
        os.path.expanduser('~/.codex/sessions'),
        os.path.expanduser('~/.codex/archived_sessions')
    ]
    session_files = []
    for sdir in session_dirs:
        if os.path.exists(sdir):
            session_files.extend(glob.glob(os.path.join(sdir, '**/*.jsonl'), recursive=True))

    today_date = date.today()
    conversations = []
    seen_cids = set()

    for fpath in session_files:
        fname = os.path.basename(fpath)
        m = re.search(r'([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})', fname)
        cid = m.group(1) if m else fname.replace('.jsonl', '')
        if cid in seen_cids:
            continue
        seen_cids.add(cid)

        cache_key = "codex:" + os.path.abspath(fpath)
        signature = _file_signature(fpath)
        cached = _get_cached_conversation(cache, cache_key, signature, today_date)
        if cached is not None:
            conversations.append(cached)
            continue

        token_info, last_time_str = extract_codex_tokens_from_file(fpath)
        if not token_info or token_info['total'] <= 0:
            _drop_cached_conversation(cache, cache_key)
            continue

        title, model = extract_codex_meta_from_head(fpath)
        model_name = model or 'gpt-5.6-terra'
        title_str = clean_title(title) if title else 'Codex 编程任务'

        mtime = os.path.getmtime(fpath)
        if last_time_str:
            try:
                dt = datetime.fromisoformat(last_time_str.replace('Z', '+00:00')).astimezone()
                time_str = dt.strftime('%Y-%m-%d %H:%M')
                mtime = dt.timestamp()
            except Exception:
                time_str = datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M')
        else:
            time_str = datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M')

        is_today = (datetime.fromtimestamp(mtime).date() == today_date)

        cost_usd, saved_usd, rates = calc_cost_usd(
            token_info['prompt'], token_info['output'], token_info['cached'], model_name, return_details=True
        )

        conversation = {
            'tool': 'Codex',
            'source': 'Codex',
            'cid': cid,
            'title': title_str,
            'time': time_str,
            'mtime': mtime,
            'is_today': is_today,
            'turns': 1,
            'prompt': token_info['prompt'],
            'output': token_info['output'],
            'cached': token_info['cached'],
            'thoughts': token_info['thoughts'],
            'total': token_info['total'],
            'cost_usd': cost_usd,
            'saved_usd': saved_usd,
            'models': model_name,
            'rates': rates
        }
        conversations.append(conversation)
        _put_cached_conversation(cache, cache_key, signature, conversation)

    conversations.sort(key=lambda x: x['mtime'], reverse=True)
    return conversations

# =====================================================================
# 3. Claude Code 扫描引擎
# =====================================================================
def scan_claude_tokens(cache=None):
    """扫描 Anthropic Claude Code 本地会话数据 (~/.claude/projects/*/*.jsonl)"""
    if cache is None:
        cache = _load_scan_cache()
    claude_base = os.path.expanduser('~/.claude/projects')
    if not os.path.exists(claude_base):
        return []

    today_date = date.today()
    conversations = []

    pattern = os.path.join(claude_base, '*', '*.jsonl')
    session_files = glob.glob(pattern)

    for filepath in session_files:
        try:
            cache_key = "claude:" + os.path.abspath(filepath)
            signature = _file_signature(filepath)
            cached = _get_cached_conversation(cache, cache_key, signature, today_date)
            if cached is not None:
                conversations.append(cached)
                continue

            mtime = os.path.getmtime(filepath)
            session_id = os.path.basename(filepath).replace('.jsonl', '')

            total_in = 0
            total_out = 0
            total_cached = 0
            total_thoughts = 0
            first_user_msg = ''
            model_set = set()
            turns = 0
            last_time = None

            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    if not line.strip():
                        continue
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue

                    # 提取第一句用户提问作为会话标题
                    if not first_user_msg and obj.get('type') == 'user':
                        msg = obj.get('message', {})
                        content = msg.get('content', '')
                        if isinstance(content, str):
                            first_user_msg = content
                        elif isinstance(content, list):
                            for part in content:
                                if isinstance(part, dict) and part.get('type') == 'text':
                                    first_user_msg = part.get('text', '')
                                    break

                    # 提取 assistant 轮次的 token 消耗
                    if obj.get('type') == 'assistant':
                        turns += 1
                        msg = obj.get('message', {})
                        model = msg.get('model', '')
                        if model:
                            model_set.add(model)

                        usage = msg.get('usage', {})
                        total_in += usage.get('input_tokens', 0)
                        total_out += usage.get('output_tokens', 0)
                        total_cached += usage.get('cache_read_input_tokens', 0)

                        out_details = usage.get('output_tokens_details', {})
                        total_thoughts += out_details.get('thinking_tokens', 0)

                        ts = obj.get('timestamp')
                        if ts:
                            last_time = ts

            total_tokens = total_in + total_out + total_cached
            if total_tokens == 0:
                _drop_cached_conversation(cache, cache_key)
                continue

            dt = None
            if last_time:
                try:
                    dt = datetime.fromisoformat(last_time.replace('Z', '+00:00')).astimezone()
                    time_str = dt.strftime('%Y-%m-%d %H:%M')
                    mtime = dt.timestamp()
                except Exception:
                    time_str = datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M')
            else:
                time_str = datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M')

            is_today = (dt.date() == today_date) if dt else (datetime.fromtimestamp(mtime).date() == today_date)
            model_name = ', '.join(model_set) if model_set else 'claude-3-7-sonnet'
            cost_usd, saved_usd, rates = calc_cost_usd(total_in, total_out, total_cached, model_name, return_details=True)

            conversation = {
                'tool': 'Claude',
                'source': 'Claude',
                'cid': session_id,
                'title': clean_title(first_user_msg) if first_user_msg else 'Claude Code 任务',
                'time': time_str,
                'mtime': mtime,
                'is_today': is_today,
                'turns': turns,
                'prompt': total_in,
                'output': total_out,
                'cached': total_cached,
                'thoughts': total_thoughts,
                'total': total_tokens,
                'cost_usd': cost_usd,
                'saved_usd': saved_usd,
                'models': model_name,
                'rates': rates
            }
            conversations.append(conversation)
            _put_cached_conversation(cache, cache_key, signature, conversation)
        except Exception:
            continue
    return conversations

# =====================================================================
# 4. 统一聚合总扫描器
# =====================================================================
def scan_all_tokens():
    """扫描全部支持的 AI 工具（Antigravity、Codex、Claude Code）"""
    # 价格库变化会影响所有会话费用，因此价格库变更时整体失效；
    # 日志文件本身则按各自的 size + mtime_ns 增量复用。
    cache = _load_scan_cache()
    price_signature = _file_signature(MODEL_PRICES_FILE)
    if cache.get("price_signature") != price_signature:
        cache = {
            "version": SCAN_CACHE_VERSION,
            "price_signature": price_signature,
            "files": {}
        }
    else:
        cache["price_signature"] = price_signature

    agy_convs = scan_agy_conversations(cache)
    codex_convs = scan_codex_tokens(cache)
    claude_convs = scan_claude_tokens(cache)

    all_convs = agy_convs + codex_convs + claude_convs
    all_convs.sort(key=lambda x: x["mtime"], reverse=True)

    today_date = date.today()

    grand_total = sum(c["total"] for c in all_convs)
    grand_prompt = sum(c["prompt"] for c in all_convs)
    grand_output = sum(c["output"] for c in all_convs)
    grand_cached = sum(c["cached"] for c in all_convs)
    grand_thoughts = sum(c["thoughts"] for c in all_convs)
    grand_cost = sum(c["cost_usd"] for c in all_convs)
    grand_saved = sum(c["saved_usd"] for c in all_convs)

    today_convs = [c for c in all_convs if c["is_today"]]
    today_total = sum(c["total"] for c in today_convs)
    today_prompt = sum(c["prompt"] for c in today_convs)
    today_output = sum(c["output"] for c in today_convs)
    today_cached = sum(c["cached"] for c in today_convs)
    today_thoughts = sum(c["thoughts"] for c in today_convs)
    today_cost = sum(c["cost_usd"] for c in today_convs)

    # 工具细分汇总
    tools_summary = {}
    for tool_name in ["Antigravity", "Codex", "Claude"]:
        t_convs = [c for c in all_convs if c["tool"] == tool_name]
        t_today = [c for c in t_convs if c["is_today"]]
        tools_summary[tool_name] = {
            "total": sum(c["total"] for c in t_convs),
            "cost_usd": sum(c["cost_usd"] for c in t_convs),
            "count": len(t_convs),
            "today_total": sum(c["total"] for c in t_today),
            "today_cost_usd": sum(c["cost_usd"] for c in t_today),
            "today_count": len(t_today)
        }

    result = {
        "summary": {
            "grand_total": grand_total,
            "grand_prompt": grand_prompt,
            "grand_output": grand_output,
            "grand_cached": grand_cached,
            "grand_thoughts": grand_thoughts,
            "grand_cost_usd": grand_cost,
            "grand_saved_usd": grand_saved,
            "today_total": today_total,
            "today_prompt": today_prompt,
            "today_output": today_output,
            "today_cached": today_cached,
            "today_thoughts": today_thoughts,
            "today_cost_usd": today_cost,
            "today_conv_count": len(today_convs),
            "total_conv_count": len(all_convs),
            "usd_to_cny_rate": 7.2
        },
        "tools_summary": tools_summary,
        "conversations": all_convs
    }
    _save_scan_cache(cache)
    return result

# 向后兼容别名
def scan_agy_tokens():
    return scan_all_tokens()

if __name__ == "__main__":
    import sys
    if "--sync-prices" in sys.argv:
        try:
            sync_official_prices_online()
        except Exception as e:
            pass

    if "--json" in sys.argv:
        data = scan_all_tokens()
        try:
            sys.stdout.write(json.dumps(data, ensure_ascii=False))
            sys.stdout.flush()
        except (BrokenPipeError, IOError):
            pass
        sys.exit(0)

    data = scan_all_tokens()
    s = data['summary']
    print(f"=== 多工具统一扫描报告 ===")
    print(f"总计会话: {s['total_conv_count']} 条")
    print(f"总消耗 Token: {s['grand_total']:,} | 预估总费用: ${s['grand_cost_usd']:.2f} (≈ ¥{s['grand_cost_usd']*7.2:.2f})")
    print(f"今日最新: {s['today_total']:,} tokens | 今日费用: ${s['today_cost_usd']:.2f} (≈ ¥{s['today_cost_usd']*7.2:.2f})")
    for tname, tinfo in data["tools_summary"].items():
        print(f"  [{tname}]: 总计 {tinfo['count']} 个会话, 消耗 {tinfo['total']:,} Tokens, 今日: {tinfo['today_total']:,}")
