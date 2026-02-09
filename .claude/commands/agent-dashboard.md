---
description: Show status of issues assigned to @PostSharpAgent and required user actions
allowed-tools:
  - Bash
  - Read
  - mcp__host-approval__execute_command
---

# Agent Dashboard

Show the status of all open GitHub issues assigned to @PostSharpAgent across Metalama repos, and highlight which ones need human action vs. agent action.

## Instructions

### Important: Execution Environment

Check `RUNNING_IN_DOCKER` environment variable first. When `true` (the typical case):
- `gh` CLI is NOT available locally — all `gh` and PowerShell commands MUST go through `mcp__host-approval__execute_command`
- Batch related commands into single MCP calls to minimize approval prompts

When `false` (running on host): use Bash directly.

### Critical: Keep MCP Output Small

MCP tool results have a token limit (~25K tokens). **Never dump raw JSON from API responses.** Instead, always process responses in PowerShell and emit only compact `Write-Host` lines with extracted fields. TeamCity build responses in particular contain dozens of environment variables and secrets that bloat the response to 60K+ characters per build.

**Pattern — always do this:**
```powershell
$result = Invoke-RestMethod -Uri '...' -Headers $headers
foreach ($b in $result.build) {
    $issue = ($b.properties.property | Where-Object { $_.name -eq 'Issue' }).value
    Write-Host "id=$($b.id) state=$($b.state) issue=$issue url=$($b.webUrl)"
}
```

**Never do this:**
```powershell
$result = Invoke-RestMethod -Uri '...' -Headers $headers
$result | ConvertTo-Json -Depth 10  # THIS WILL OVERFLOW
```

### 1. Gather Data

Collect data from three sources. Run steps 1a+1b in a single MCP call, and 1c in another, in parallel.

#### 1a. Fetch All Open Issues Assigned to @PostSharpAgent

```
gh search issues --assignee PostSharpAgent --owner metalama --state open --json number,title,repository,url,labels --limit 100
```

Each item has: `number`, `title`, `repository.name`, `url`, `labels`.

If no issues are found, display "No open issues assigned to @PostSharpAgent." and stop.

#### 1b. Fetch PRs by @PostSharpAgent Per Repo

Combine with step 1a in a single MCP call. For each repo (Metalama, Metalama.Premium, Metalama.Community, Metalama.Samples):

**Open PRs:**
```
gh pr list --repo metalama/<repo> --author PostSharpAgent --state open --json number,headRefName,isDraft,reviewRequests,latestReviews,url
```

**Merged PRs** (to detect "merged but issue still open"):
```
gh pr list --repo metalama/<repo> --author PostSharpAgent --state merged --json number,headRefName,url --limit 50
```

Match PRs to issues by extracting the issue number from `headRefName` using regex: `topic/[^/]+/(\d+)-`.

For each issue, track whether it has an open PR, a merged PR, or neither.

Key fields (open PRs):
- `headRefName`: branch name (e.g., `topic/2026.1/1340-fix-something`)
- `isDraft`: boolean
- `reviewRequests[].login`: pending reviewer usernames
- `latestReviews[].author.login`: reviewer who left a review (`copilot-pull-request-reviewer` for Copilot)
- `latestReviews[].state`: `APPROVED`, `COMMENTED`, `CHANGES_REQUESTED`

**Detecting copilot inline comments:** The copilot review `body` in `latestReviews` contains a line like `"generated 2 comments"` or `"generated no comments"`. Use regex `generated (\d+) comments?` to extract the count. If > 0, copilot left inline comments that need human review. If 0 or if the pattern is not found, treat as no inline comments.

#### 1c. Query TeamCity Builds

Run all TeamCity queries in a **single** MCP call using PowerShell. Process all API responses inside the script and emit only compact `Write-Host` lines — never dump raw JSON.

**Claude builds** (queue + running) — query once for all issues. Extract only the `Issue` property value per build:

```powershell
$headers = @{ Authorization = "Bearer $env:TEAMCITY_CLOUD_TOKEN"; Accept = 'application/json' }

Write-Host "=== QUEUED CLAUDE ==="
try {
    $q = Invoke-RestMethod -Uri 'https://postsharp.teamcity.com/app/rest/buildQueue?locator=buildType:Metalama_Metalama20261_MetalamaConsolidated_Claude&fields=build(id,state,webUrl,properties(property(name,value)))' -Headers $headers
    foreach ($b in $q.build) {
        $issue = ($b.properties.property | Where-Object { $_.name -eq 'Issue' }).value
        Write-Host "id=$($b.id) state=$($b.state) issue=$issue url=$($b.webUrl)"
    }
    if ($q.build.Count -eq 0) { Write-Host "none" }
} catch { Write-Host "ERROR: $($_.Exception.Message)" }

Write-Host "=== RUNNING CLAUDE ==="
try {
    $r = Invoke-RestMethod -Uri 'https://postsharp.teamcity.com/app/rest/builds?locator=buildType:Metalama_Metalama20261_MetalamaConsolidated_Claude,running:true&fields=build(id,state,webUrl,properties(property(name,value)))' -Headers $headers
    foreach ($b in $r.build) {
        $issue = ($b.properties.property | Where-Object { $_.name -eq 'Issue' }).value
        Write-Host "id=$($b.id) state=$($b.state) issue=$issue url=$($b.webUrl)"
    }
    if ($r.build.Count -eq 0) { Write-Host "none" }
} catch { Write-Host "ERROR: $($_.Exception.Message)" }
```

The `Issue` property value may be a plain number (`"837"`), a URL (`"https://github.com/metalama/Metalama/issues/837"`), or other formats. Extract digits with regex and match against issue numbers.

**DebugBuild** — query for each branch that has a PR.

**Critical syntax:** Use `branch:(name:$branchName)` (with parentheses), NOT `branch:$branchName`. Branch names contain slashes (e.g., `topic/2026.1/...`) that break the locator parser without the parenthesized syntax.

**Critical error handling:** Wrap each individual API call in its own `try/catch`. TeamCity returns HTTP 400 (not an empty list) when `running:true` or a branch filter matches nothing.

```powershell
Write-Host "=== DEBUGBUILD ==="
$branches = @( <list of branch names from PRs> )
foreach ($branch in $branches) {
    $l = 'none'; $r2 = 'none'; $q2 = 'none'
    try {
        $latest = Invoke-RestMethod -Uri "https://postsharp.teamcity.com/app/rest/builds?locator=buildType:Metalama_Metalama20261_Metalama_DebugBuild,branch:(name:$branch),count:1&fields=build(id,state,status,branchName,webUrl)" -Headers $headers
        if ($latest.build.Count -gt 0) { $l = "$($latest.build[0].status)/$($latest.build[0].state) id=$($latest.build[0].id) url=$($latest.build[0].webUrl)" }
    } catch {}
    try {
        $run = Invoke-RestMethod -Uri "https://postsharp.teamcity.com/app/rest/builds?locator=buildType:Metalama_Metalama20261_Metalama_DebugBuild,branch:(name:$branch),running:true&fields=build(id,state,branchName,webUrl)" -Headers $headers
        if ($run.build.Count -gt 0) { $r2 = "running id=$($run.build[0].id)" }
    } catch {}
    try {
        $que = Invoke-RestMethod -Uri "https://postsharp.teamcity.com/app/rest/buildQueue?locator=buildType:Metalama_Metalama20261_Metalama_DebugBuild,branch:(name:$branch)&fields=build(id,state,branchName,webUrl)" -Headers $headers
        if ($que.build.Count -gt 0) { $q2 = "queued id=$($que.build[0].id)" }
    } catch {}
    Write-Host "$branch | latest=$l | running=$r2 | queued=$q2"
}
```

### 2. Determine Status Per Issue

For each issue, check conditions in this priority order. First match wins:

| # | Condition | Status | Agent Action | Human Action |
|---|-----------|--------|--------------|--------------|
| 0 | No open PR, but a merged PR exists for this issue | `Merged, not closed` | Close issue | — |
| 1 | Claude build queued or running with matching Issue parameter | `Claude build queued/running` | — | — (wait) |
| 2 | DebugBuild queued or running for the topic branch | `Debug build in progress` | — | — (wait) |
| 3 | Copilot review pending (`copilot-pull-request-reviewer` in PR's `reviewRequests`) | `Copilot review pending` | — | — (wait) |
| 4 | No open PR, no merged PR, and no Claude build queued/running | `No work started` | Trigger Claude build | — |
| 5 | PR is draft (`isDraft == true`), no builds running | `Agent work incomplete` | Trigger Claude build | — |
| 6 | PR has `CHANGES_REQUESTED` from a human reviewer (not copilot) in `latestReviews` | `Changes requested` | Trigger Claude build | — |
| 7 | Latest DebugBuild for branch has `status:FAILURE` | `Debug build failed` | Trigger Claude build | — |
| 8 | PR exists, not draft, no human review yet (no entries in `latestReviews` from humans) | `Needs review` | — | Review PR |
| 9a | PR has human `APPROVED` + copilot `COMMENTED` with inline comments, no DebugBuild | `Copilot has comments` | — | Review copilot comments, trigger DebugBuild |
| 9b | PR has human `APPROVED` + copilot `COMMENTED` with no inline comments, no DebugBuild | `Ready for DebugBuild` | — | Trigger DebugBuild |
| 10 | PR has human `APPROVED` but no copilot review at all | `Approved, no copilot` | Request copilot review | — |
| 11 | Latest DebugBuild for branch has `status:SUCCESS` | `Build green` | — | Merge PR |
| 12 | (fallback) | `Unknown` | — | Investigate |

### 3. Display Results

Output a markdown table:

```
| # | Title | Status | Agent Action | Human Action | Link |
|---|-------|--------|--------------|--------------|------|
```

For each issue, show:
- **#**: Issue number as a link, e.g., `[#1340](url)`
- **Title**: Issue title (truncate to 50 chars if needed)
- **Status**: From the status determination above
- **Agent Action**: What the agent/Claude should do (or `—`)
- **Human Action**: What the human should do (or `—`)
- **Link**: Most relevant link — PR URL if PR exists, TC build URL if build is running, otherwise issue URL

Sort the table by status priority: items needing human action first, then agent action items, then waiting items.

After the table, display a summary line:
```
N issues total: X need agent action (auto-triggered), Y need human action, Z waiting
```

### 4. Auto-Actions

After displaying the table, execute agent actions automatically.

#### 4a. Trigger Claude Builds

For issues needing "Trigger Claude build" (statuses #4, #5, #6, #7), batch all triggers into a **single** MCP call:

```powershell
$headers = @{ Authorization = "Bearer $env:TEAMCITY_CLOUD_TOKEN"; Accept = 'application/json' }
$issues = @(<list of issue numbers>)
foreach ($issue in $issues) {
    $body = @{
        buildType = @{id = "Metalama_Metalama20261_MetalamaConsolidated_Claude"}
        properties = @{ property = @( @{name = "Issue"; value = "$issue"} ) }
    } | ConvertTo-Json -Depth 5 -Compress
    try {
        $result = Invoke-RestMethod -Uri 'https://postsharp.teamcity.com/app/rest/buildQueue' -Method Post -Headers $headers -ContentType 'application/json' -Body $body
        Write-Host "Triggered Claude build for #$issue`: Build #$($result.id) - $($result.webUrl)"
    } catch {
        Write-Host "FAILED to trigger for #$issue`: $($_.Exception.Message)"
    }
}
```

#### 4b. Request Copilot Reviews

For issues with status #10 ("Approved, no copilot"), request a copilot review using the GitHub API:

```
gh api repos/metalama/<repo>/pulls/<pr_number>/requested_reviewers --method POST -f 'reviewers[]=copilot-pull-request-reviewer'
```

**Known issue:** This may fail with HTTP 422 ("not a collaborator") if the Copilot reviewer isn't enabled for the repo. If it fails, report the failure and note in the human action column that a manual copilot review request is needed via the GitHub UI (PR page > Reviewers > search "copilot").

#### 4c. Close Merged Issues

For issues with status #0 ("Merged, not closed"), close the issue with a comment:

```
gh issue close <issue_number> --repo metalama/<repo> --comment "Closing: PR #<pr_number> has been merged."
```

After all actions, report what was triggered:
```
Triggered Claude build for #<number>: Build #<id> — <url>
Requested copilot review for #<number>: PR #<pr_number>
Closed issue #<number> (PR #<pr_number> was merged)
```

If there are no agent actions needed, skip this step.

## Error Handling

- **No TEAMCITY_CLOUD_TOKEN**: Display warning that TeamCity data is unavailable, but still show GitHub data
- **GitHub API errors**: Display error and continue with available data
- **TeamCity API errors**: Display warning per-branch and continue; show TC columns as "unknown"
- **No issues found**: Display friendly "No open issues assigned to @PostSharpAgent" message
- **MCP output overflow**: If an MCP call result is truncated, the PowerShell script is dumping raw JSON. Fix by processing in-script and emitting only `Write-Host` lines with extracted fields.
