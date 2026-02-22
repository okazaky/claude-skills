# Claude Code Custom Skills

Claude Code で使用するカスタムスキル集。

## Skills

### playwright-isolation

Playwright MCP の並行セッション競合を診断・修復するスキル。

複数の Claude Code セッションが同時に Playwright を使う際のブラウザ競合を、セッション分離で解決する。

**機能:**
- 競合の診断 (`/playwright-isolation status`)
- 自動修復 (`/playwright-isolation fix`)
- セッションデータのクリーンアップ (`/playwright-isolation cleanup`)
- スロット追加 (`/playwright-isolation add`)

**参考:** [microsoft/playwright-mcp#893](https://github.com/microsoft/playwright-mcp/issues/893)

## Setup

```bash
# スキルを ~/.claude/skills/ にシンボリックリンク
ln -s ~/projects/claude-skills/skills/playwright-isolation ~/.claude/skills/playwright-isolation

# スクリプトを ~/.claude/scripts/ にシンボリックリンク
ln -s ~/projects/claude-skills/scripts/playwright-isolated.sh ~/.claude/scripts/playwright-isolated.sh
```
