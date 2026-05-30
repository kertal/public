#!/usr/bin/env bash
#
# gh-knowledge-base.sh
#
# Downloads GitHub Issues and Pull Requests (filtered by label) with all
# comments, and saves them as nicely formatted Markdown files organized
# into year/month folders — ideal for searching in Cursor, Copilot, or
# other LLM-powered tools.
#
# Requirements: gh (GitHub CLI), jq
#
# Usage:
#   ./gh-knowledge-base.sh --repo owner/repo --label "bug" [options]
#
# Options:
#   --repo    OWNER/REPO   GitHub repository (required)
#   --label   LABEL        Label to filter by (required)
#   --output  DIR          Output directory (default: ./knowledge-base)
#   --state   STATE        Issue/PR state: open, closed, all (default: all)
#   --limit   N            Max items to fetch (default: 1000)
#   --type    TYPE         What to fetch: issues, prs, all (default: all)
#   --help                 Show this help message
#
set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────

REPO=""
LABEL=""
OUTPUT_DIR="./knowledge-base"
STATE="all"
LIMIT=1000
FETCH_TYPE="all"

# ─── Colors & Formatting ────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header(){ echo -e "\n${BOLD}${CYAN}── $* ──${NC}\n"; }

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
    cat <<'HELP'
gh-knowledge-base.sh — Download GitHub PRs & Issues as a searchable Markdown knowledge base

USAGE
    ./gh-knowledge-base.sh --repo owner/repo --label "my-label" [options]

OPTIONS
    --repo    OWNER/REPO   GitHub repository (required)
    --label   LABEL        Label to filter by (required)
    --output  DIR          Output directory        (default: ./knowledge-base)
    --state   STATE        open | closed | all     (default: all)
    --limit   N            Max items to fetch       (default: 1000)
    --type    TYPE         issues | prs | all       (default: all)
    --help                 Show this help message

AUTHENTICATION
    Set GITHUB_TOKEN environment variable, or authenticate via `gh auth login`.

EXAMPLES
    # All closed bugs from facebook/react
    ./gh-knowledge-base.sh --repo facebook/react --label bug --state closed

    # Only PRs labeled "enhancement", max 50
    ./gh-knowledge-base.sh --repo vercel/next.js --label enhancement --type prs --limit 50

OUTPUT STRUCTURE
    knowledge-base/
    ├── issues/
    │   ├── 2024/
    │   │   ├── 01-january/
    │   │   │   ├── 1234-fix-login-redirect-issue.md
    │   │   │   └── 1240-api-timeout-on-large-payloads.md
    │   │   └── 02-february/
    │   │       └── ...
    │   └── 2025/
    │       └── ...
    ├── pull-requests/
    │   └── (same year/month structure)
    └── index.md   ← summary of all downloaded items
HELP
}

# ─── Argument Parsing ────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)    REPO="$2";       shift 2 ;;
        --label)   LABEL="$2";      shift 2 ;;
        --output)  OUTPUT_DIR="$2"; shift 2 ;;
        --state)   STATE="$2";      shift 2 ;;
        --limit)   LIMIT="$2";      shift 2 ;;
        --type)    FETCH_TYPE="$2"; shift 2 ;;
        --help)    usage; exit 0 ;;
        *)         error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# ─── Validation ──────────────────────────────────────────────────────────────

if [[ -z "$REPO" ]]; then
    error "Missing required option: --repo"
    usage
    exit 1
fi

if [[ -z "$LABEL" ]]; then
    error "Missing required option: --label"
    usage
    exit 1
fi

if ! command -v gh &>/dev/null; then
    error "'gh' (GitHub CLI) is not installed. Install it from https://cli.github.com"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    error "'jq' is not installed. Install it: sudo apt install jq / brew install jq"
    exit 1
fi

# Check gh authentication
if ! gh auth status &>/dev/null; then
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        info "Using GITHUB_TOKEN from environment"
    else
        error "Not authenticated. Run 'gh auth login' or set GITHUB_TOKEN env var."
        exit 1
    fi
fi

# ─── Helpers ─────────────────────────────────────────────────────────────────

MONTH_NAMES=(
    "" "01-january" "02-february" "03-march" "04-april"
    "05-may" "06-june" "07-july" "08-august"
    "09-september" "10-october" "11-november" "12-december"
)

# Convert a title into a filename-safe slug
slugify() {
    echo "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g' \
        | sed -E 's/^-+|-+$//g' \
        | cut -c1-80
}

# Format an ISO date to human-readable
format_date() {
    local iso_date="$1"
    if [[ -n "$iso_date" && "$iso_date" != "null" ]]; then
        date -d "$iso_date" '+%B %d, %Y at %H:%M UTC' 2>/dev/null || echo "$iso_date"
    else
        echo "N/A"
    fi
}

# Get year and month number from ISO date
get_year()  { echo "$1" | cut -c1-4; }
get_month() { echo "$1" | cut -c6-7 | sed 's/^0//'; }

# Render a list of labels as badges
render_labels() {
    local labels_json="$1"
    if [[ "$labels_json" == "null" || "$labels_json" == "[]" ]]; then
        echo "None"
        return
    fi
    echo "$labels_json" | jq -r '.[] | "`" + .name + "`"' | paste -sd ', ' -
}

# Render assignees
render_assignees() {
    local assignees_json="$1"
    if [[ "$assignees_json" == "null" || "$assignees_json" == "[]" ]]; then
        echo "Unassigned"
        return
    fi
    echo "$assignees_json" | jq -r '.[] | "@" + .login' | paste -sd ', ' -
}

# Render a single comment as markdown
render_comment() {
    local index="$1"
    local author="$2"
    local created="$3"
    local association="$4"
    local body="$5"
    local reaction_count="$6"

    local badge=""
    case "$association" in
        OWNER)        badge=" (Owner)" ;;
        MEMBER)       badge=" (Member)" ;;
        COLLABORATOR) badge=" (Collaborator)" ;;
        CONTRIBUTOR)  badge=" (Contributor)" ;;
        *)            badge="" ;;
    esac

    local reactions_note=""
    if [[ "$reaction_count" -gt 0 ]] 2>/dev/null; then
        reactions_note=" | $reaction_count reaction(s)"
    fi

    cat <<MD

---

### Comment #${index} by @${author}${badge}

*$(format_date "$created")*${reactions_note}

${body}
MD
}

# ─── Fetch & Process ─────────────────────────────────────────────────────────

fetch_and_save() {
    local item_type="$1"   # "issue" or "pr"
    local gh_type="$2"     # for gh search: "issue" or "pr"
    local folder_name="$3" # "issues" or "pull-requests"

    header "Fetching ${folder_name} with label '${LABEL}' from ${REPO}"

    # Fetch items using gh search
    local items_json
    items_json=$(gh search "${gh_type}s" \
        --repo "$REPO" \
        --label "$LABEL" \
        --state "$STATE" \
        --limit "$LIMIT" \
        --json number,title,state,createdAt,updatedAt,author,labels,assignees,body,url \
        2>/dev/null) || {
        error "Failed to fetch ${folder_name}. Check repo name and permissions."
        return 1
    }

    local count
    count=$(echo "$items_json" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        warn "No ${folder_name} found with label '${LABEL}' (state: ${STATE})"
        return 0
    fi

    info "Found ${count} ${folder_name}"

    local i=0
    local saved=0

    while [[ $i -lt $count ]]; do
        local item
        item=$(echo "$items_json" | jq ".[$i]")

        local number title state created_at updated_at author body url
        number=$(echo "$item" | jq -r '.number')
        title=$(echo "$item" | jq -r '.title')
        state=$(echo "$item" | jq -r '.state')
        created_at=$(echo "$item" | jq -r '.createdAt')
        updated_at=$(echo "$item" | jq -r '.updatedAt')
        author=$(echo "$item" | jq -r '.author.login // "ghost"')
        body=$(echo "$item" | jq -r '.body // ""')
        url=$(echo "$item" | jq -r '.url // ""')

        local labels_json assignees_json
        labels_json=$(echo "$item" | jq '.labels // []')
        assignees_json=$(echo "$item" | jq '.assignees // []')

        # Determine output path: folder_name/YYYY/MM-month/
        local year month month_dir
        year=$(get_year "$created_at")
        month=$(get_month "$created_at")
        month_dir="${MONTH_NAMES[$month]}"

        local out_dir="${OUTPUT_DIR}/${folder_name}/${year}/${month_dir}"
        mkdir -p "$out_dir"

        # Build filename: NUMBER-slugified-title.md
        local slug filename filepath
        slug=$(slugify "$title")
        filename="${number}-${slug}.md"
        filepath="${out_dir}/${filename}"

        # Fetch comments for this item
        local comments_json=""
        local comment_count=0

        if [[ "$item_type" == "issue" ]]; then
            comments_json=$(gh api "repos/${REPO}/issues/${number}/comments" \
                --paginate \
                --jq '.' \
                2>/dev/null) || comments_json="[]"
        else
            # For PRs, fetch both issue comments and review comments
            local issue_comments review_comments
            issue_comments=$(gh api "repos/${REPO}/issues/${number}/comments" \
                --paginate \
                --jq '.' \
                2>/dev/null) || issue_comments="[]"
            review_comments=$(gh api "repos/${REPO}/pulls/${number}/comments" \
                --paginate \
                --jq '.' \
                2>/dev/null) || review_comments="[]"

            # Merge and sort by created_at
            comments_json=$(echo "$issue_comments $review_comments" \
                | jq -s 'add // [] | sort_by(.created_at)')
        fi

        comment_count=$(echo "$comments_json" | jq 'length' 2>/dev/null || echo "0")

        # Also fetch PR-specific metadata if it's a PR
        local pr_meta=""
        if [[ "$item_type" == "pr" ]]; then
            local pr_detail
            pr_detail=$(gh api "repos/${REPO}/pulls/${number}" \
                --jq '{
                    merged: .merged,
                    merged_at: .merged_at,
                    merged_by: .merged_by.login,
                    base: .base.ref,
                    head: .head.ref,
                    additions: .additions,
                    deletions: .deletions,
                    changed_files: .changed_files,
                    review_comments: .review_comments,
                    commits: .commits
                }' 2>/dev/null) || pr_detail="{}"

            local merged merged_at merged_by base_branch head_branch additions deletions changed_files commits
            merged=$(echo "$pr_detail" | jq -r '.merged // false')
            merged_at=$(echo "$pr_detail" | jq -r '.merged_at // "N/A"')
            merged_by=$(echo "$pr_detail" | jq -r '.merged_by // "N/A"')
            base_branch=$(echo "$pr_detail" | jq -r '.base // "N/A"')
            head_branch=$(echo "$pr_detail" | jq -r '.head // "N/A"')
            additions=$(echo "$pr_detail" | jq -r '.additions // 0')
            deletions=$(echo "$pr_detail" | jq -r '.deletions // 0')
            changed_files=$(echo "$pr_detail" | jq -r '.changed_files // 0')
            commits=$(echo "$pr_detail" | jq -r '.commits // 0')

            local merge_status="Not merged"
            if [[ "$merged" == "true" ]]; then
                merge_status="Merged by @${merged_by} on $(format_date "$merged_at")"
            fi

            pr_meta=$(cat <<META

## Pull Request Details

| Detail | Value |
|--------|-------|
| **Branch** | \`${head_branch}\` → \`${base_branch}\` |
| **Merge Status** | ${merge_status} |
| **Commits** | ${commits} |
| **Changed Files** | ${changed_files} |
| **Additions** | +${additions} |
| **Deletions** | -${deletions} |
META
            )
        fi

        # Determine type label and icon for the header
        local type_label state_upper
        if [[ "$item_type" == "pr" ]]; then
            type_label="Pull Request"
        else
            type_label="Issue"
        fi
        state_upper=$(echo "$state" | tr '[:lower:]' '[:upper:]')

        # ─── Write Markdown File ─────────────────────────────────────

        cat > "$filepath" <<MD
# #${number}: ${title}

> **${type_label}** | **Status:** ${state_upper} | **Repository:** ${REPO}

| Field | Value |
|-------|-------|
| **Author** | @${author} |
| **Created** | $(format_date "$created_at") |
| **Updated** | $(format_date "$updated_at") |
| **Labels** | $(render_labels "$labels_json") |
| **Assignees** | $(render_assignees "$assignees_json") |
| **Link** | [${REPO}#${number}](${url}) |
${pr_meta}

## Description

${body:-*No description provided.*}
MD

        # Append comments
        if [[ "$comment_count" -gt 0 ]]; then
            echo "" >> "$filepath"
            echo "## Comments (${comment_count})" >> "$filepath"

            local c=0
            while [[ $c -lt $comment_count ]]; do
                local comment
                comment=$(echo "$comments_json" | jq ".[$c]")

                local c_author c_created c_body c_association c_reactions
                c_author=$(echo "$comment" | jq -r '.user.login // "ghost"')
                c_created=$(echo "$comment" | jq -r '.created_at // ""')
                c_body=$(echo "$comment" | jq -r '.body // ""')
                c_association=$(echo "$comment" | jq -r '.author_association // ""')
                c_reactions=$(echo "$comment" | jq -r '(.reactions.total_count // 0)')

                # Handle review comments (they have a `path` and `diff_hunk`)
                local diff_context=""
                local path
                path=$(echo "$comment" | jq -r '.path // empty')
                if [[ -n "$path" ]]; then
                    local diff_hunk
                    diff_hunk=$(echo "$comment" | jq -r '.diff_hunk // ""')
                    diff_context=$(cat <<DIFF

**File:** \`${path}\`

<details>
<summary>Diff context</summary>

\`\`\`diff
${diff_hunk}
\`\`\`

</details>

DIFF
                    )
                    c_body="${diff_context}${c_body}"
                fi

                render_comment "$((c + 1))" "$c_author" "$c_created" "$c_association" "$c_body" "$c_reactions" >> "$filepath"

                c=$((c + 1))
            done
        fi

        # Add footer
        cat >> "$filepath" <<MD

---

*Downloaded from [${url}](${url}) on $(date '+%Y-%m-%d') for knowledge base indexing.*
MD

        saved=$((saved + 1))
        printf "  ${GREEN}✓${NC} [%d/%d] #%-6d %s\n" "$saved" "$count" "$number" "$title"

        i=$((i + 1))

        # Rate limiting: brief pause every 10 items to avoid hitting API limits
        if (( i % 10 == 0 && i < count )); then
            info "Pausing briefly for rate limiting..."
            sleep 2
        fi
    done

    ok "Saved ${saved} ${folder_name} to ${OUTPUT_DIR}/${folder_name}/"
}

# ─── Build Index ─────────────────────────────────────────────────────────────

build_index() {
    header "Building index"

    local index_file="${OUTPUT_DIR}/index.md"

    cat > "$index_file" <<MD
# Knowledge Base Index

> Auto-generated from GitHub repository **${REPO}**
> Filtered by label: \`${LABEL}\` | State: \`${STATE}\`
> Downloaded on: $(date '+%Y-%m-%d %H:%M UTC')

## How to Search

This knowledge base is optimized for LLM-powered search in tools like **Cursor**, **GitHub Copilot**, and others.

- **In Cursor:** Add this folder to your workspace, then use \`@Codebase\` to search across all issues and PRs.
- **General:** Each file includes structured metadata (author, labels, dates, status) to help with retrieval.

## Contents

MD

    # List all markdown files grouped by type
    for type_dir in "issues" "pull-requests"; do
        local full_path="${OUTPUT_DIR}/${type_dir}"
        if [[ -d "$full_path" ]]; then
            local type_label
            if [[ "$type_dir" == "issues" ]]; then
                type_label="Issues"
            else
                type_label="Pull Requests"
            fi

            echo "### ${type_label}" >> "$index_file"
            echo "" >> "$index_file"

            # Find all .md files, extract info, and list them
            while IFS= read -r -d '' mdfile; do
                local rel_path="${mdfile#"${OUTPUT_DIR}/"}"
                local basename
                basename=$(basename "$mdfile" .md)
                # Extract the number and title from the filename
                local num="${basename%%-*}"
                local title_slug="${basename#*-}"
                local title_readable
                title_readable=$(echo "$title_slug" | tr '-' ' ')
                echo "- [#${num} — ${title_readable}](${rel_path})" >> "$index_file"
            done < <(find "$full_path" -name '*.md' -print0 | sort -z)

            echo "" >> "$index_file"
        fi
    done

    # Summary stats
    local total_issues=0 total_prs=0
    if [[ -d "${OUTPUT_DIR}/issues" ]]; then
        total_issues=$(find "${OUTPUT_DIR}/issues" -name '*.md' | wc -l)
    fi
    if [[ -d "${OUTPUT_DIR}/pull-requests" ]]; then
        total_prs=$(find "${OUTPUT_DIR}/pull-requests" -name '*.md' | wc -l)
    fi

    cat >> "$index_file" <<MD

## Statistics

| Metric | Count |
|--------|-------|
| Issues | ${total_issues} |
| Pull Requests | ${total_prs} |
| **Total** | **$((total_issues + total_prs))** |

---

*Generated by [gh-knowledge-base.sh](https://github.com) — $(date '+%Y-%m-%d %H:%M UTC')*
MD

    ok "Index written to ${index_file}"
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    header "GitHub Knowledge Base Downloader"

    info "Repository:  ${REPO}"
    info "Label:       ${LABEL}"
    info "State:       ${STATE}"
    info "Fetch type:  ${FETCH_TYPE}"
    info "Max items:   ${LIMIT}"
    info "Output dir:  ${OUTPUT_DIR}"

    mkdir -p "$OUTPUT_DIR"

    if [[ "$FETCH_TYPE" == "all" || "$FETCH_TYPE" == "issues" ]]; then
        fetch_and_save "issue" "issue" "issues"
    fi

    if [[ "$FETCH_TYPE" == "all" || "$FETCH_TYPE" == "prs" ]]; then
        fetch_and_save "pr" "pr" "pull-requests"
    fi

    build_index

    echo ""
    header "Done!"
    info "Knowledge base saved to: ${OUTPUT_DIR}/"
    info "Total files: $(find "$OUTPUT_DIR" -name '*.md' | wc -l) markdown files"
    echo ""
    info "Next steps:"
    info "  1. Open the folder in Cursor or your preferred editor"
    info "  2. Use @Codebase or similar LLM search to query your issues & PRs"
    info "  3. Re-run this script anytime to fetch the latest updates"
}

main
