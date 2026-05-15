#!/bin/bash
# Set up workspace and services for an existing Linux user
# Usage: sudo bash setup-user.sh <username>
# The user must already exist (created with useradd + passwd)
set -e

if [ -z "$1" ]; then
    echo "Usage: sudo bash setup-user.sh <username>"
    exit 1
fi

USERNAME="$1"

if ! id "$USERNAME" &>/dev/null; then
    echo "Error: user '$USERNAME' does not exist. Create with:"
    echo "  useradd -m -s /bin/bash $USERNAME"
    echo "  passwd $USERNAME"
    exit 1
fi

# Load API key
source /etc/biai.env 2>/dev/null || true

WORKSPACE="/home/$USERNAME/workspace"
mkdir -p "$WORKSPACE"

# Create session-based workspace structure with independent copies of data
for SESSION in session1 session2; do
    mkdir -p "$WORKSPACE/$SESSION/data"
    if [ -d "/shared/data/$SESSION/data" ]; then
        cp -n /shared/data/$SESSION/data/* "$WORKSPACE/$SESSION/data/" 2>/dev/null || true
    fi
done

# Claude Code settings
mkdir -p "/home/$USERNAME/.claude/skills"

# Global preferences + onboarding state — stored in ~/.claude.json
# Only write if missing or lacks onboarding fields (to avoid wiping completed onboarding)
if [ ! -f "/home/$USERNAME/.claude.json" ] || ! grep -q "hasCompletedOnboarding" "/home/$USERNAME/.claude.json" 2>/dev/null; then
    API_KEY_SUFFIX="${ANTHROPIC_API_KEY: -20}"
    CLAUDE_VERSION=$(claude --version 2>/dev/null | head -1 | awk '{print $1}')
    cat > "/home/$USERNAME/.claude.json" << CLAUDEJSON
{
  "theme": "light",
  "hasCompletedOnboarding": true,
  "lastOnboardingVersion": "${CLAUDE_VERSION}",
  "customApiKeyResponses": {
    "approved": ["${API_KEY_SUFFIX}"],
    "rejected": []
  },
  "projects": {
    "/home/$USERNAME/workspace": {
      "hasTrustDialogAccepted": true,
      "hasCompletedProjectOnboarding": true
    }
  }
}
CLAUDEJSON
fi

# Playwright MCP server
cat > "/home/$USERNAME/.claude/.mcp.json" << 'MCPJSON'
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest"]
    }
  }
}
MCPJSON

cat > "/home/$USERNAME/.claude/settings.json" << SETTINGS
{
  "env": {
    "ANTHROPIC_API_KEY": "${ANTHROPIC_API_KEY}"
  },
  "permissions": {
    "allow": [
      "Bash(python*)",
      "Bash(pip*)",
      "Bash(duckdb*)",
      "Bash(ls*)",
      "Bash(cat*)",
      "Bash(head*)",
      "Bash(node*)",
      "Bash(pandoc*)",
      "Bash(libreoffice*)",
      "Bash(soffice*)",
      "Bash(pdftoppm*)",
      "Bash(cp*)",
      "Bash(mv*)",
      "Bash(mkdir*)",
      "Bash(unzip*)",
      "Bash(git*)",
      "Bash(zip*)",
      "Read",
      "Write",
      "Edit"
    ],
    "defaultMode": "bypassPermissions"
  },
  "skipDangerousModePermissionPrompt": true
}
SETTINGS

# Copy skills
cp -r /shared/skills/* "/home/$USERNAME/.claude/skills/" 2>/dev/null || true

# Project instructions
cat > "$WORKSPACE/CLAUDE.md" << 'CLAUDEMD'
# Business Intelligence & AI — Lab Workspace

## Environment
- Python 3, Node.js, and common data libraries are pre-installed
- The Anthropic API key is already set in the environment
- Skills for creating Word (.docx), Excel (.xlsx), and PowerPoint (.pptx) documents are installed
- Exercises are organized by session: `session2/`, `session4/`, `session6/`, `session7/`
- Each session folder has a `data/` directory with the datasets for that session

## Session 2: AI vs Dashboards

**Data** in `session2/data/`:
- `sales.csv` — 837 transactions: transaction_id, date, customer_name, product_line, amount, region, sales_rep
- `customers.csv` — 50 customers: customer_id, customer_name, industry, region, acquisition_date, status, annual_contract_value
- `employees.csv` — 30 employees: employee_id, first_name, last_name, department, division, hire_date, role, salary_band
- `ETF-returns.xlsx` — Monthly returns for SPY, GLD, IEF, EFA (2005-present)
- `loan-risk-analysis/` — 220 loans (loan_tape.xlsx), state regulations (PDF), risk policy (Word doc)

Company: Acme Corp, a mid-size B2B industrial supplier. Product lines: Industrial Products, Technical Services, Safety & Compliance. Regions: South, Northeast, Midwest, West.

## Session 4: Building AI Agents

**Data** in `session4/data/`: XYZ Corp, a $500M B2B industrial distributor (3 divisions: Industrial, Energy, Safety).

**Salesforce CRM** (`data/salesforce/`):
- `sf_accounts.parquet` — 120 accounts: AccountId, AccountName, Industry, BillingState, OwnerId, AnnualRevenue, Type
- `sf_orders.parquet` — 585 orders (2023-2025): OrderId, AccountId, OpportunityId, OrderDate, TotalAmount, Status

**Workday HR** (`data/workday/`):
- `wd_workers.parquet` — 100 employees: worker_id, first_name, last_name, division, department, job_title, status
- `wd_compensation.parquet` — 100 records: comp_id, worker_id, effective_date, base_pay, bonus_target_pct, bonus_actual
- `wd_system_ids.parquet` — 45 mappings: worker_id, system_name, external_id (maps Workday worker_id to Salesforce OwnerId)

Query parquet files with DuckDB: `duckdb.sql("SELECT * FROM read_parquet('data/salesforce/sf_accounts.parquet')")`
Use `anthropic` Python package for API calls.

## Session 6: Decision-Making with AI

**Data** in `session6/data/`:

- `workover_rig_data.md` — 20 oil wells, 3 rigs, travel times, daily production losses
- `portfolio/portfolio_lots.xlsx` — 167 tax lots: Date, Ticker, Sector, Industry, Size, Shares, Price per Share, Cost
- `portfolio/client_info.md` — Margaret and David Chen, ~$500K taxable account, target sector weights, tax preferences, constraints
- `portfolio/stock_data.md` — MotherDuck database connection (stocks, prices, recommendations tables for ~4,300 U.S. equities)

## Session 7: Predictive Modeling

**Data** in `session7/data/`:

- `customer_churn.csv` — 7,043 telecom customers, 21 columns including tenure, MonthlyCharges, TotalCharges, Contract, InternetService, Churn (Yes/No). 26.5% churn rate.

## Business Definitions
- **Revenue** means closed/completed transactions only (not pipeline or lost deals)
- **Active customer** means status = "Active" (exclude churned customers unless explicitly asked)
- **Active employee** means status = "Active" in Workday
- When asked for "this year" use 2025; "last year" means 2024
- Cross-system joins: use `wd_system_ids` to map Workday `worker_id` to Salesforce `OwnerId`

## Running Web Apps
- Your app port is available as `$APP_PORT` in the terminal
- To run a FastAPI app: `uvicorn app:app --host 0.0.0.0 --port $APP_PORT`
- Click the **App** tab in the left pane to view your running app
- FastAPI and uvicorn are pre-installed

## Guidelines
- Write clear, well-structured code
- When generating documents (Word, Excel, PowerPoint), use the installed skills
- For data analysis, use Python with pandas and matplotlib
- Show your work — explain what you are doing and what assumptions you are making
CLAUDEMD

# Initialize git repo in workspace
if [ ! -d "$WORKSPACE/.git" ]; then
    su - "$USERNAME" -c "cd ~/workspace && git init && git config user.name '$USERNAME' && git config user.email '$USERNAME@ai-lab'"
    cat > "$WORKSPACE/.gitignore" << 'GITIGNORE'
data
__pycache__/
*.pyc
.env
GITIGNORE
    chown "$USERNAME" "$WORKSPACE/.gitignore"
fi

# Add API key and auto-launch claude in .bashrc (idempotent)
if ! grep -q "ANTHROPIC_API_KEY" "/home/$USERNAME/.bashrc" 2>/dev/null; then
    cat >> "/home/$USERNAME/.bashrc" << BASHRC

export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"

# Auto-launch Claude Code
if [ -t 1 ] && [ -z "\$CLAUDE_LAUNCHED" ]; then
    export CLAUDE_LAUNCHED=1
    cd ~/workspace
    exec claude
fi
BASHRC
fi

chown -R "$USERNAME" "/home/$USERNAME"

# Onboarding is pre-populated in .claude.json above — no need for interactive first-run

# Assign ports: hash username to a stable port pair
# Use /etc/biai-ports to track assignments
PORTS_FILE="/etc/biai-ports"
touch "$PORTS_FILE"

if grep -q "^$USERNAME:" "$PORTS_FILE"; then
    TTYD_PORT=$(grep "^$USERNAME:" "$PORTS_FILE" | cut -d: -f2)
    FB_PORT=$(grep "^$USERNAME:" "$PORTS_FILE" | cut -d: -f3)
    TERM_PORT=$(grep "^$USERNAME:" "$PORTS_FILE" | cut -d: -f4)
    APP_PORT=$(grep "^$USERNAME:" "$PORTS_FILE" | cut -d: -f5)
    # Backfill term port if missing (3-field legacy format)
    if [ -z "$TERM_PORT" ]; then
        TERM_PORT=$((TTYD_PORT + 2000))
    fi
    # Backfill app port if missing (4-field legacy format)
    if [ -z "$APP_PORT" ]; then
        APP_PORT=$((TTYD_PORT + 3000))
    fi
    # Rewrite line with all 5 fields
    sed -i "s/^$USERNAME:.*/$USERNAME:$TTYD_PORT:$FB_PORT:$TERM_PORT:$APP_PORT/" "$PORTS_FILE"
else
    # Find next available port pair
    LAST_TTYD=$(awk -F: '{print $2}' "$PORTS_FILE" | sort -n | tail -1)
    TTYD_PORT=${LAST_TTYD:-9000}
    TTYD_PORT=$((TTYD_PORT + 1))
    FB_PORT=$((TTYD_PORT + 1000))
    TERM_PORT=$((TTYD_PORT + 2000))
    APP_PORT=$((TTYD_PORT + 3000))
    echo "$USERNAME:$TTYD_PORT:$FB_PORT:$TERM_PORT:$APP_PORT" >> "$PORTS_FILE"
fi

# Skip Claude auto-launch for sudo users (admin account)
TTYD_EXTRA_ENV=""
if groups "$USERNAME" 2>/dev/null | grep -qw sudo; then
    TTYD_EXTRA_ENV="Environment=CLAUDE_LAUNCHED=1"
fi

# ttyd service
cat > "/etc/systemd/system/ttyd-${USERNAME}.service" << SYSTEMD
[Unit]
Description=ttyd terminal for $USERNAME
After=network.target

[Service]
Type=simple
User=$USERNAME
Environment=ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
$TTYD_EXTRA_ENV
WorkingDirectory=/home/$USERNAME/workspace
ExecStart=/usr/local/bin/ttyd --port $TTYD_PORT --writable --base-path /$USERNAME/ -t titleFixed="AI Lab" -t 'theme={"background":"#ffffff","foreground":"#000000","cursor":"#000000","selectionBackground":"#b0c4de"}' bash -l
Restart=on-failure

[Install]
WantedBy=multi-user.target
SYSTEMD

# filebrowser service
cat > "/etc/systemd/system/filebrowser-${USERNAME}.service" << SYSTEMD
[Unit]
Description=Filebrowser for $USERNAME
After=network.target

[Service]
Type=simple
User=$USERNAME
ExecStart=/usr/local/bin/filebrowser --root /home/$USERNAME/workspace --address 127.0.0.1 --port $FB_PORT --baseURL /$USERNAME/files --database /home/$USERNAME/.filebrowser.db
Restart=on-failure

[Install]
WantedBy=multi-user.target
SYSTEMD

# Plain terminal service (no claude auto-launch)
cat > "/etc/systemd/system/ttyd-term-${USERNAME}.service" << SYSTEMD
[Unit]
Description=Plain terminal for $USERNAME
After=network.target

[Service]
Type=simple
User=$USERNAME
Environment=ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
Environment=CLAUDE_LAUNCHED=1
WorkingDirectory=/home/$USERNAME/workspace
ExecStart=/usr/local/bin/ttyd --port $TERM_PORT --writable --base-path /$USERNAME/term/ -t titleFixed="Terminal" -t 'theme={"background":"#ffffff","foreground":"#000000","cursor":"#000000","selectionBackground":"#b0c4de"}' bash -l
Restart=on-failure

[Install]
WantedBy=multi-user.target
SYSTEMD

# Initialize FileBrowser database with proxy auth (no login required)
FB_DB="/home/$USERNAME/.filebrowser.db"
if [ ! -f "$FB_DB" ]; then
    filebrowser config init --auth.method=proxy --auth.header=X-FB-User --database "$FB_DB"
    filebrowser users add admin adminpassword123 --perm.admin=false --database "$FB_DB"
fi
chown "$USERNAME" "$FB_DB"

systemctl daemon-reload
systemctl enable --now "ttyd-${USERNAME}.service"
systemctl enable --now "filebrowser-${USERNAME}.service"
systemctl enable --now "ttyd-term-${USERNAME}.service"

# Export APP_PORT in .bashrc (idempotent)
if ! grep -q "APP_PORT" "/home/$USERNAME/.bashrc" 2>/dev/null; then
    sed -i "/ANTHROPIC_API_KEY/a export APP_PORT=$APP_PORT" "/home/$USERNAME/.bashrc"
fi
# Update APP_PORT if it changed
sed -i "s/^export APP_PORT=.*/export APP_PORT=$APP_PORT/" "/home/$USERNAME/.bashrc"

# Also set APP_PORT in Claude Code settings env
SETTINGS_FILE="/home/$USERNAME/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ] && ! grep -q "APP_PORT" "$SETTINGS_FILE"; then
    sed -i "s/\"ANTHROPIC_API_KEY\"/\"APP_PORT\": \"$APP_PORT\",\n    \"ANTHROPIC_API_KEY\"/" "$SETTINGS_FILE"
    chown "$USERNAME" "$SETTINGS_FILE"
fi

# Install fastapi and uvicorn for the user
su - "$USERNAME" -c "pip install --quiet fastapi uvicorn 2>/dev/null" || true

# Regenerate nginx config
bash /opt/biai-vm/generate-nginx.sh

echo "Done: $USERNAME (claude=:$TTYD_PORT, files=:$FB_PORT, term=:$TERM_PORT, app=:$APP_PORT)"
echo "URL: https://ai-lab.rice-business.org/$USERNAME/"
