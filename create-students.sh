#!/bin/bash
# Create student accounts from a CSV file
# Usage: sudo bash create-students.sh students.csv
# CSV format: username,password (no header)
# Example:
#   jsmith,TempPass123
#   mjones,TempPass456

set -e

if [ -z "$1" ]; then
    echo "Usage: sudo bash create-students.sh <csv_file>"
    echo "CSV format: username,password (no header)"
    exit 1
fi

CSV_FILE="$1"
TEMPLATE_DIR="/shared/templates"
DATA_DIR="/shared/data"
SKILLS_DIR="/shared/skills"

echo "=== Creating student accounts ==="

while IFS=, read -r USERNAME PASSWORD; do
    # Skip empty lines
    [ -z "$USERNAME" ] && continue

    if id "$USERNAME" &>/dev/null; then
        echo "  SKIP (exists): $USERNAME"
        continue
    fi

    # Create user with home directory
    useradd -m -s /bin/bash "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd

    # Set up workspace with exercise templates
    WORKSPACE="/home/$USERNAME/workspace"
    mkdir -p "$WORKSPACE"

    # Copy exercise starter files
    if [ -d "$TEMPLATE_DIR" ]; then
        cp -r "$TEMPLATE_DIR"/* "$WORKSPACE/"
    fi

    # Symlink to shared data (read-only for students)
    ln -sf "$DATA_DIR" "$WORKSPACE/data"

    # Claude Code settings: allow common tools + Office skill dependencies
    mkdir -p "/home/$USERNAME/.claude"
    cat > "/home/$USERNAME/.claude/settings.json" << 'SETTINGS'
{
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
      "Bash(zip*)",
      "Read",
      "Write",
      "Edit"
    ]
  }
}
SETTINGS

    # Install Claude Code skills (xlsx, docx, pptx, pdf, skill-creator)
    if [ -d "$SKILLS_DIR" ]; then
        mkdir -p "/home/$USERNAME/.claude/skills"
        cp -r "$SKILLS_DIR"/* "/home/$USERNAME/.claude/skills/"
    fi

    # Project instructions
    cat > "$WORKSPACE/CLAUDE.md" << 'CLAUDEMD'
# AI Data Agent Workshop

You are helping a student build a data agent from scratch.

## Environment
- Data files are in `./data/` (symlink to /shared/data)
- Use DuckDB to query parquet files: `duckdb.sql("SELECT * FROM read_parquet('data/file.parquet')")`
- The Anthropic API key is already set in the environment
- Use `anthropic` Python package for API calls

## Guidelines
- Help the student understand each piece of the agent loop
- Don't write the entire solution at once — build incrementally
- Explain what each part does as you go
- When the student gets stuck, give hints rather than complete solutions
CLAUDEMD

    # Fix ownership
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"

    echo "  CREATED: $USERNAME (workspace at $WORKSPACE)"

done < "$CSV_FILE"

echo ""
echo "=== Done ==="
echo "Students can SSH in and run: cd workspace && claude"
