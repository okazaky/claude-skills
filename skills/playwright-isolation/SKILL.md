---
name: playwright-isolation
description: Playwright MCP の並行セッション競合を診断・修復する。「Playwright競合」「ブラウザが取り合い」「並行セッション問題」と言われた時に使用。
---

# Playwright MCP 並行セッション分離

複数の Claude Code セッションで Playwright MCP が競合する問題を診断・修復するスキル。

## 使い方

```
/playwright-isolation            # 現在の状態を診断
/playwright-isolation fix        # 競合を修復
/playwright-isolation status     # アクティブなセッションを確認
/playwright-isolation cleanup    # 古いセッションデータを削除
/playwright-isolation add        # スロットを追加
```

## 背景

複数セッションが同時に Playwright MCP を呼び出すと、全セッションが同一ブラウザの同一タブを奪い合う。
参考: [microsoft/playwright-mcp#893](https://github.com/microsoft/playwright-mcp/issues/893)

## アーキテクチャ

```
~/.claude/scripts/playwright-isolated.sh
  ├── PLAYWRIGHT_SLOT=1   → /tmp/playwright-mcp-sessions/pw-slot-1  (playwright)
  ├── PLAYWRIGHT_SLOT=2   → /tmp/playwright-mcp-sessions/pw-slot-2  (playwright-2)
  ├── PLAYWRIGHT_SLOT=3   → /tmp/playwright-mcp-sessions/pw-slot-3  (playwright-3)
  └── PLAYWRIGHT_SLOT=auto → /tmp/playwright-mcp-sessions/pw-{PID}-{timestamp} (plugin fallback)
```

各スロットは独立したブラウザインスタンスを起動し、`--isolated` + `--user-data-dir` で完全分離する。

## 実行手順

### 診断（デフォルト / `status`）

```bash
# アクティブなセッションディレクトリを確認
ls -la /tmp/playwright-mcp-sessions/

# Playwright プロセスを確認
ps aux | grep -i playwright | grep -v grep

# 現在の MCP 設定を確認
python3 -c "
import json
with open('$HOME/.claude.json') as f:
    data = json.load(f)
for proj_path, proj in data.get('projects', {}).items():
    servers = proj.get('mcpServers', {})
    pw = {k:v for k,v in servers.items() if 'playwright' in k.lower()}
    if pw:
        print(f'\n{proj_path}:')
        for name, cfg in pw.items():
            slot = cfg.get('env', {}).get('PLAYWRIGHT_SLOT', '?')
            print(f'  {name} (slot {slot})')
"
```

結果をユーザーに報告する。

### 修復（`fix`）

以下の手順で修復:

1. ラッパースクリプトの存在確認

```bash
test -x ~/.claude/scripts/playwright-isolated.sh && echo "OK" || echo "MISSING"
```

2. スクリプトが無い場合は作成

```bash
cat > ~/.claude/scripts/playwright-isolated.sh << 'SCRIPT'
#!/bin/bash
SLOT="${PLAYWRIGHT_SLOT:-auto}"
BASE_DIR="/tmp/playwright-mcp-sessions"
mkdir -p "$BASE_DIR"
find "$BASE_DIR" -maxdepth 1 -type d -name "pw-*" -mmin +1440 -exec rm -rf {} + 2>/dev/null
if [ "$SLOT" = "auto" ]; then
  SESSION_DIR="$BASE_DIR/pw-$$-$(date +%s)"
else
  SESSION_DIR="$BASE_DIR/pw-slot-$SLOT"
fi
mkdir -p "$SESSION_DIR"
exec npx @playwright/mcp@latest --isolated --user-data-dir "$SESSION_DIR" "$@"
SCRIPT
chmod +x ~/.claude/scripts/playwright-isolated.sh
```

3. `.claude.json` のプロジェクト設定を更新（Python で安全に編集）

```bash
python3 << 'PYEOF'
import json, os

config_path = os.path.expanduser("~/.claude.json")
script_path = os.path.expanduser("~/.claude/scripts/playwright-isolated.sh")

with open(config_path) as f:
    data = json.load(f)

# Find current project or home directory
cwd = os.getcwd()
project = data.get("projects", {}).get(cwd) or data.get("projects", {}).get(os.path.expanduser("~"))
if not project:
    print("ERROR: No matching project found")
    exit(1)

mcp = project.setdefault("mcpServers", {})

# Remove old playwright config
for key in list(mcp.keys()):
    if "playwright" in key.lower():
        del mcp[key]

# Add 3 isolated slots
for i in range(1, 4):
    name = "playwright" if i == 1 else f"playwright-{i}"
    mcp[name] = {
        "type": "stdio",
        "command": script_path,
        "args": [],
        "env": {"PLAYWRIGHT_SLOT": str(i)}
    }

with open(config_path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f"OK: 3 isolated Playwright slots configured for {cwd}")
PYEOF
```

4. プラグインの `.mcp.json` も更新

```bash
PLUGIN_MCP="$HOME/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/playwright/.mcp.json"
if [ -f "$PLUGIN_MCP" ]; then
  cat > "$PLUGIN_MCP" << 'EOF'
{
  "playwright": {
    "command": "~/.claude/scripts/playwright-isolated.sh",
    "args": [],
    "env": {
      "PLAYWRIGHT_SLOT": "auto"
    }
  }
}
EOF
  echo "Plugin .mcp.json updated"
fi
```

5. ユーザーに「次回セッション再起動で反映」と伝える

### クリーンアップ（`cleanup`）

```bash
# 全セッションデータを削除
rm -rf /tmp/playwright-mcp-sessions/pw-*
echo "All Playwright session data cleaned up"

# 残存プロセスを確認
ps aux | grep -i "playwright.*mcp" | grep -v grep
```

残存プロセスがあれば報告し、ユーザー確認後に kill する。

### スロット追加（`add`）

現在の最大スロット番号を検出し、次のスロットを追加:

```bash
python3 << 'PYEOF'
import json, os

config_path = os.path.expanduser("~/.claude.json")
script_path = os.path.expanduser("~/.claude/scripts/playwright-isolated.sh")

with open(config_path) as f:
    data = json.load(f)

home = os.path.expanduser("~")
project = data.get("projects", {}).get(home, {})
mcp = project.get("mcpServers", {})

# Find max slot number
max_slot = 0
for key in mcp:
    if key == "playwright":
        max_slot = max(max_slot, 1)
    elif key.startswith("playwright-"):
        try:
            n = int(key.split("-")[1])
            max_slot = max(max_slot, n)
        except ValueError:
            pass

new_slot = max_slot + 1
name = f"playwright-{new_slot}"
mcp[name] = {
    "type": "stdio",
    "command": script_path,
    "args": [],
    "env": {"PLAYWRIGHT_SLOT": str(new_slot)}
}

with open(config_path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f"OK: Added {name} (slot {new_slot}). Total slots: {new_slot}")
PYEOF
```

## 運用ルール

- セッション A → `playwright` (slot 1)
- セッション B → `playwright-2` (slot 2)
- セッション C → `playwright-3` (slot 3)
- 4つ以上必要なら `/playwright-isolation add` でスロット追加
- 各スロットのログイン状態は独立（共有されない）
- `--isolated` により終了時にブラウザデータはメモリから破棄される
- `/tmp/playwright-mcp-sessions/` の古いディレクトリは起動時に自動削除（24h経過分）
