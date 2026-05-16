#!/bin/bash
# Meridian Corp AI Course — Server Setup
# Run as root on a fresh Ubuntu 24.04 VM
# Usage: sudo bash setup-server.sh

set -e

echo "=== Meridian Corp AI Course Server Setup ==="

# 1. System packages
echo "[1/7] Installing system packages..."
apt-get update -qq
apt-get install -y -qq python3 python3-pip python3-venv nodejs npm git curl \
    libreoffice-calc libreoffice-impress libreoffice-writer \
    pandoc poppler-utils

# 2. Install Claude Code globally
echo "[2/7] Installing Claude Code..."
npm install -g @anthropic-ai/claude-code

# 3. npm packages for Office skills and Playwright MCP
echo "[3/7] Installing npm packages..."
npm install -g pptxgenjs @playwright/mcp
npx playwright install --with-deps chromium

# 4. Python packages (system-wide for all students)
echo "[4/7] Installing Python packages..."
pip3 install --break-system-packages anthropic duckdb pandas numpy matplotlib fastapi uvicorn httpx \
    openpyxl defusedxml lxml markitdown Pillow

# 5. Create shared data directory
echo "[5/7] Setting up shared data..."
mkdir -p /shared/data/dashboard /shared/data/portfolio /shared/data/salesforce
# Copy data files (assumes they've been uploaded to /tmp/biai-data/)
if [ -d /tmp/biai-data ]; then
    cp -r /tmp/biai-data/* /shared/data/
    echo "  Copied data files from /tmp/biai-data/"
else
    echo "  WARNING: /tmp/biai-data/ not found. Upload data there first."
    echo "  Expected structure:"
    echo "    /tmp/biai-data/dashboard/  (sales.csv, customers.csv, employees.csv)"
    echo "    /tmp/biai-data/portfolio/  (portfolio_lots.xlsx, client_info.md, stock_data.md)"
    echo "    /tmp/biai-data/salesforce/ (parquet files for agent exercises)"
fi
chmod -R 755 /shared/data

# 6. Set up shared API key
echo "[6/7] Configuring API key..."
if [ -z "$ANTHROPIC_API_KEY" ]; then
    read -p "Enter Anthropic API key: " API_KEY
else
    API_KEY="$ANTHROPIC_API_KEY"
fi
cat > /etc/profile.d/anthropic.sh << EOF
export ANTHROPIC_API_KEY="$API_KEY"
EOF
chmod 644 /etc/profile.d/anthropic.sh

# 7. Create exercise templates and skills directories
echo "[7/7] Installing exercise templates and Claude Code skills..."
mkdir -p /shared/templates
cp -r /tmp/templates/* /shared/templates/ 2>/dev/null || echo "  Upload templates to /tmp/templates/ and re-run"
chmod -R 755 /shared/templates

# Claude Code skills (xlsx, docx, pptx, pdf, skill-creator) — shared source for all students
mkdir -p /shared/skills
if [ -d /tmp/skills ]; then
    cp -r /tmp/skills/* /shared/skills/
    echo "  Copied skills from /tmp/skills/"
else
    echo "  WARNING: /tmp/skills/ not found. Upload skill directories there first."
    echo "  Expected structure: /tmp/skills/{xlsx,docx,pptx,pdf,skill-creator}/SKILL.md"
fi
chmod -R 755 /shared/skills

echo ""
echo "=== Setup complete ==="
echo "Next steps:"
echo "  1. Upload data to /tmp/biai-data/ if not done:"
echo "       dashboard/  (sales.csv, customers.csv, employees.csv)"
echo "       portfolio/  (portfolio_lots.xlsx, client_info.md, stock_data.md)"
echo "       salesforce/ (parquet files for agent exercises)"
echo "  2. Upload exercise templates to /tmp/templates/ if not done"
echo "  3. Upload Claude Code skills to /tmp/skills/ if not done"
echo "     (xlsx/, docx/, pptx/ directories each containing SKILL.md)"
echo "  4. Run create-students.sh to create student accounts"
echo ""
