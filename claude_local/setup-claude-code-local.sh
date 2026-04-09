#!/bin/bash
# Setup Claude Code CLI/Extension to use local Qwen 3.5 LLM via k3s cluster
# Prerequisites: ./forward-qwen.sh must be running (localhost:8080 -> qwen service)

set -e

echo "=== Claude Code + Local Qwen 3.5 Setup ==="

# 0. Set env vars immediately for this session
export ANTHROPIC_BASE_URL="http://localhost:8080"
export ANTHROPIC_API_KEY="sk-no-key-required"

# 1. Check port forward is active
echo ""
echo "[1/5] Checking port forward to qwen service..."
if curl -s --max-time 5 http://localhost:8080/v1/models > /dev/null 2>&1; then
    echo "  OK - Qwen service reachable at localhost:8080"
else
    echo "  FAIL - Qwen service not reachable at localhost:8080"
    echo "  Run ./forward-qwen.sh first."
    exit 1
fi

# 2. Configure ~/.claude.json to skip login
echo ""
echo "[2/4] Configuring ~/.claude.json (skip login)..."
CLAUDE_JSON="$HOME/.claude.json"
if [ -f "$CLAUDE_JSON" ]; then
    python3 -c "
import json
with open('$CLAUDE_JSON', 'r') as f:
    data = json.load(f)
data['hasCompletedOnboarding'] = True
data['primaryApiKey'] = 'sk-no-key-required'
with open('$CLAUDE_JSON', 'w') as f:
    json.dump(data, f, indent=2)
print('  Updated existing ~/.claude.json')
"
else
    cat > "$CLAUDE_JSON" << 'EOF'
{
  "hasCompletedOnboarding": true,
  "primaryApiKey": "sk-no-key-required"
}
EOF
    echo "  Created ~/.claude.json"
fi

# 3. Fix KV cache invalidation (90% slowdown fix)
echo ""
echo "[3/5] Configuring ~/.claude/settings.json (KV cache fix)..."
CLAUDE_SETTINGS_DIR="$HOME/.claude"
CLAUDE_SETTINGS="$CLAUDE_SETTINGS_DIR/settings.json"
mkdir -p "$CLAUDE_SETTINGS_DIR"

if [ -f "$CLAUDE_SETTINGS" ]; then
    python3 -c "
import json
with open('$CLAUDE_SETTINGS', 'r') as f:
    data = json.load(f)
if 'env' not in data:
    data['env'] = {}
data['env']['CLAUDE_CODE_ATTRIBUTION_HEADER'] = '0'
with open('$CLAUDE_SETTINGS', 'w') as f:
    json.dump(data, f, indent=2)
print('  Updated existing ~/.claude/settings.json')
"
else
    cat > "$CLAUDE_SETTINGS" << 'EOF'
{
  "env": {
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0"
  }
}
EOF
    echo "  Created ~/.claude/settings.json"
fi

# 4. Disable login prompt in VS Code extension
echo ""
echo "[4/5] Configuring VS Code settings..."
VSCODE_SETTINGS_DIR="$HOME/Library/Application Support/Code/User"
VSCODE_SETTINGS="$VSCODE_SETTINGS_DIR/settings.json"
if [ -f "$VSCODE_SETTINGS" ]; then
    python3 -c "
import json
with open('$VSCODE_SETTINGS', 'r') as f:
    data = json.load(f)
data['claudeCode.disableLoginPrompt'] = True
with open('$VSCODE_SETTINGS', 'w') as f:
    json.dump(data, f, indent=2)
print('  Updated VS Code settings.json')
"
else
    echo "  Skipped (no VS Code settings found)"
fi

# 5. Add env vars to shell profile
echo ""
echo "[5/5] Adding environment variables to ~/.zshrc..."
ZSHRC="$HOME/.zshrc"

# Remove old entries if present
if [ -f "$ZSHRC" ]; then
    sed -i '' '/# Claude Code Local LLM/d' "$ZSHRC" 2>/dev/null
    sed -i '' '/ANTHROPIC_BASE_URL.*localhost:8080/d' "$ZSHRC" 2>/dev/null
    sed -i '' '/ANTHROPIC_API_KEY.*sk-no-key-required/d' "$ZSHRC" 2>/dev/null
fi

cat >> "$ZSHRC" << 'EOF'
# Claude Code Local LLM
export ANTHROPIC_BASE_URL="http://localhost:8080"
export ANTHROPIC_API_KEY="sk-no-key-required"
EOF
echo "  Added ANTHROPIC_BASE_URL and ANTHROPIC_API_KEY to ~/.zshrc"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Usage:"
echo "  1. Run ./forward-qwen.sh (if not already running)"
echo "  2. Open a new terminal (or run: source ~/.zshrc)"
echo "  3. Run: claude"
echo "     Or use the Claude Code VS Code extension"
echo ""
echo "To revert:"
echo "  unset ANTHROPIC_BASE_URL"
echo "  unset ANTHROPIC_API_KEY"
