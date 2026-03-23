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

Then fetch each issue's milestone individually (the search API does not support the `milestone` field):
```
gh api repos/metalama/<repo>/issues/<number> --jq '.milestone.title // "NONE"'
```

**Milestone → branch and TC build config mapping:** The issue's milestone (e.g., `2026.1.4-preview`, `2026.0.18`) determines the major version by extracting the first two segments (`YYYY.N`). This determines:
- **Major version**: first two dot-separated segments of the milestone (e.g., `2026.1.4-preview` → `2026.1`, `2026.0.18` → `2026.0`)
- **Target branch**: `develop/{major_version}` (e.g., `develop/2026.1`)
- **Topic branch prefix**: `topic/{major_version}/` (e.g., `topic/2026.1/1234-fix-something`)
- **TC project prefix**: `Metalama_Metalama{YYYYN}_` where `{YYYYN}` is the major version with the dot removed (e.g., `2026.1` → `Metalama_Metalama20261_`)
- **DebugBuild config**: `{prefix}Metalama_DebugBuild` (consistent across versions)
- **Claude build config**: naming is **inconsistent** across versions — do NOT compute it. Instead, **discover it dynamically** by querying the TC API for each milestone's project:
  ```
  GET /app/rest/projects/id:Metalama_Metalama{YYYYN}?fields=projects(project(buildTypes(buildType(id,name))))
  ```
  Then find the build type where `name` equals `Run Claude on Issue`. Cache the result per milestone.

Collect the set of unique major versions across all issues. For each one, discover the Claude build config ID. Issues without a milestone should be flagged as "Unknown milestone" in the dashboard.

**Important:** `gh search issues` does NOT support the `milestone` field. After fetching issues, fetch each issue's milestone separately:
```
gh api repos/metalama/<repo>/issues/<number> --jq '.milestone.title // "NONE"'
```

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

**Claude builds** (queue + running) — query for each unique milestone's build config. Extract only the `Issue` property value per build:

```powershell
$headers = @{ Authorization = "Bearer $env:TEAMCITY_CLOUD_TOKEN"; Accept = 'application/json' }

# For each unique major version (e.g., '2026.1', '2026.0'), discover the Claude build type ID dynamically.
# The naming is inconsistent across versions, so we query the TC project structure.
$milestones = @( <list of unique major versions from issues> )

foreach ($ms in $milestones) {
    $msKey = $ms -replace '\.', ''
    $projectId = "Metalama_Metalama${msKey}"

    # Discover the Claude build config by searching subprojects for "Run Claude on Issue"
    $btId = $null
    try {
        $proj = Invoke-RestMethod -Uri "https://postsharp.teamcity.com/app/rest/projects/id:$projectId`?fields=projects(project(buildTypes(buildType(id,name))))" -Headers $headers
        foreach ($sub in $proj.projects.project) {
            foreach ($bt in $sub.buildTypes.buildType) {
                if ($bt.name -eq 'Run Claude on Issue') { $btId = $bt.id; break }
            }
            if ($btId) { break }
        }
    } catch {}
    if (-not $btId) { Write-Host "WARNING: No Claude build config found for milestone $ms"; continue }
    Write-Host "=== CLAUDE CONFIG ($ms) === btId=$btId"

    Write-Host "=== QUEUED CLAUDE ($ms) ==="
    try {
        $q = Invoke-RestMethod -Uri "https://postsharp.teamcity.com/app/rest/buildQueue?locator=buildType:$btId&fields=build(id,state,webUrl,properties(property(name,value)))" -Headers $headers
        if ($q.build) {
            foreach ($b in $q.build) {
                $issue = ($b.properties.property | Where-Object { $_.name -eq 'Issue' }).value
                Write-Host "id=$($b.id) state=$($b.state) issue=$issue url=$($b.webUrl) milestone=$ms"
            }
        } else { Write-Host "none" }
    } catch { Write-Host "ERROR: $($_.Exception.Message)" }

    Write-Host "=== RUNNING CLAUDE ($ms) ==="
    try {
        $r = Invoke-RestMethod -Uri "https://postsharp.teamcity.com/app/rest/builds?locator=buildType:$btId,running:true&fields=build(id,state,webUrl,properties(property(name,value)))" -Headers $headers
        if ($r.build) {
            foreach ($b in $r.build) {
                $issue = ($b.properties.property | Where-Object { $_.name -eq 'Issue' }).value
                Write-Host "id=$($b.id) state=$($b.state) issue=$issue url=$($b.webUrl) milestone=$ms"
            }
        } else { Write-Host "none" }
    } catch { Write-Host "none (no running builds)" }
}
```

The `Issue` property value may be a plain number (`"837"`), a URL (`"https://github.com/metalama/Metalama/issues/837"`), or other formats. Extract digits with regex and match against issue numbers.

**DebugBuild** — query for each branch that has a PR.

**Critical syntax:** Use `branch:(name:$branchName)` (with parentheses), NOT `branch:$branchName`. Branch names contain slashes (e.g., `topic/2026.1/...`) that break the locator parser without the parenthesized syntax.

**Critical error handling:** Wrap each individual API call in its own `try/catch`. TeamCity returns HTTP 400 (not an empty list) when `running:true` or a branch filter matches nothing.

**Critical: buildQueue does NOT support branch filtering** — the `buildQueue` API returns HTTP 400 when `branch:(name:...)` is used. Instead, query ALL queued DebugBuilds at once (without branch filter) and match branches client-side.

```powershell
Write-Host "=== DEBUGBUILD ==="
# Each entry: branch name + milestone (to determine the correct build config)
# e.g., @{branch='topic/2026.1/1234-fix'; ms='2026.1'}, @{branch='topic/2026.0/1405-fix'; ms='2026.0'}
$branchEntries = @( <list of @{branch=...; ms=...} from PRs, using milestone from matching issue> )

# Query ALL queued DebugBuilds per milestone (buildQueue does NOT support branch filtering)
$allQueued = @{}
$queriedMilestones = @{}
foreach ($entry in $branchEntries) {
    $ms = $entry.ms
    if (-not $queriedMilestones.ContainsKey($ms)) {
        $queriedMilestones[$ms] = $true
        $msKey = $ms -replace '\.', ''
        $dbBtId = "Metalama_Metalama${msKey}_Metalama_DebugBuild"
        try {
            $que = Invoke-RestMethod -Uri "https://postsharp.teamcity.com/app/rest/buildQueue?locator=buildType:$dbBtId&fields=build(id,state,branchName,webUrl)" -Headers $headers
            if ($que.build) { foreach ($b in $que.build) { $allQueued[$b.branchName] = "queued id=$($b.id) url=$($b.webUrl)" } }
        } catch {}
    }
}

foreach ($entry in $branchEntries) {
    $branch = $entry.branch; $ms = $entry.ms
    $msKey = $ms -replace '\.', ''
    $dbBtId = "Metalama_Metalama${msKey}_Metalama_DebugBuild"
    $l = 'none'; $r2 = 'none'
    $q2 = if ($allQueued.ContainsKey($branch)) { $allQueued[$branch] } else { 'none' }
    try {
        $latest = Invoke-RestMethod -Uri "https://postsharp.teamcity.com/app/rest/builds?locator=buildType:$dbBtId,branch:(name:$branch),count:1&fields=build(id,state,status,branchName,webUrl)" -Headers $headers
        if ($latest.build.Count -gt 0) { $l = "$($latest.build[0].status)/$($latest.build[0].state) id=$($latest.build[0].id) url=$($latest.build[0].webUrl)" }
    } catch {}
    try {
        $run = Invoke-RestMethod -Uri "https://postsharp.teamcity.com/app/rest/builds?locator=buildType:$dbBtId,branch:(name:$branch),running:true&fields=build(id,state,branchName,webUrl)" -Headers $headers
        if ($run.build.Count -gt 0) { $r2 = "running id=$($run.build[0].id)" }
    } catch {}
    Write-Host "$branch ($ms) | latest=$l | running=$r2 | queued=$q2"
}
```

#### 1d. Check Whether CHANGES_REQUESTED Feedback Was Already Addressed

For PRs with `CHANGES_REQUESTED` from a human reviewer, determine whether the agent already addressed the feedback by comparing timestamps. This requires two pieces of data:

1. **Claude build history:** Query the last 30 Claude builds (include in the 1c MCP call) and extract `issue`, `status`, `finishDate` for successful builds:

```powershell
# Query Claude build history for each milestone (reuse the $btId discovered above)
foreach ($ms in $milestones) {
    # $btId should already be discovered from the queued/running section above
    Write-Host "=== CLAUDE BUILD HISTORY ($ms) ==="
    try {
        $builds = Invoke-RestMethod -Uri "https://postsharp.teamcity.com/app/rest/builds?locator=buildType:$btId,count:30,defaultFilter:false&fields=build(id,status,finishDate,properties(property(name,value)))" -Headers $headers
        if ($builds.build) {
            foreach ($b in $builds.build) {
                if ($b.status -eq 'SUCCESS') {
                    $issueProp = ($b.properties.property | Where-Object { $_.name -eq 'Issue' }).value
                    Write-Host "issue=$issueProp finished=$($b.finishDate) id=$($b.id) milestone=$ms"
                }
            }
        }
    } catch { Write-Host "ERROR: $($_.Exception.Message)" }
}
```

2. **Review timestamps:** For each PR with `CHANGES_REQUESTED`, fetch review timestamps (include in the 1a+1b MCP call):

```
gh api repos/metalama/<repo>/pulls/<pr>/reviews --jq '.[] | select(.user.login=="gfraiteur") | "\(.submitted_at) \(.state)"'
```

Compare the latest `CHANGES_REQUESTED` timestamp against the latest successful Claude build `finishDate` for the same issue. If the Claude build finished **after** the review, the agent already addressed the feedback.

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
| 6a | PR has `CHANGES_REQUESTED` from a human reviewer, and NO successful Claude build after the review timestamp | `Changes requested` | Trigger Claude build | — |
| 6b | PR has `CHANGES_REQUESTED` from a human reviewer, but a successful Claude build ran AFTER the review timestamp (agent already addressed feedback) | `Needs re-review` | Request @gfraiteur review | Re-review PR |
| 7 | Latest DebugBuild for branch has `status:FAILURE` | `Debug build failed` | — | Analyze DebugBuild failure |
| 8 | PR exists, not draft, no human review yet (no entries in `latestReviews` from humans) | `Needs review` | Request @gfraiteur review | Review PR |
| 9a | PR has human `APPROVED` + copilot `COMMENTED` with inline comments, no DebugBuild | `Copilot has comments` | — | Review copilot comments, trigger DebugBuild |
| 9b | PR has human `APPROVED` + copilot `COMMENTED` with no inline comments, no DebugBuild | `Ready for DebugBuild` | — | Trigger DebugBuild |
| 10 | PR has human `APPROVED` but no copilot review at all | `Approved, no copilot` | — | Request copilot review (GitHub UI), trigger DebugBuild |
| 11 | Latest DebugBuild for branch has `status:SUCCESS` | `Build green` | — | Merge PR |
| 12 | (fallback) | `Unknown` | — | Investigate |

### 3. Display Results

Output a markdown table:

```
| # | Milestone | Title | Status | Agent Action | Human Action | Link |
|---|-----------|-------|--------|--------------|--------------|------|
```

For each issue, show:
- **#**: Issue number as a link, e.g., `[#1340](url)`
- **Milestone**: The issue's milestone (e.g., `2026.1`), or `—` if none
- **Title**: Issue title (truncate to 50 chars if needed)
- **Status**: From the status determination above
- **Agent Action**: What the agent/Claude should do (or `—`)
- **Human Action**: What the human should do (or `—`)
- **Link**: Most relevant link — PR URL if PR exists, TC build URL if build is running, otherwise issue URL

Sort the table by status priority: items needing human action first, then agent action items, then waiting items.

After the table, display a summary line. An issue can count in both agent and human categories if it has both actions (e.g., status #6b and #8 have both agent and human actions):
```
N issues total: X need agent action (auto-triggered), Y need human action, Z waiting
```

### 4. Auto-Actions

After displaying the table, execute agent actions automatically.

#### 4a. Trigger Claude Builds

For issues needing "Trigger Claude build" (statuses #4, #5, #6a), batch all triggers into a **single** MCP call. Use the issue's milestone to determine the correct build config:

```powershell
$headers = @{ Authorization = "Bearer $env:TEAMCITY_CLOUD_TOKEN"; Accept = 'application/json' }
# Each entry: issue number + major version + the discovered Claude build type ID
# The Claude btId was discovered in step 1c — reuse the same values here.
# e.g., @{num='1414'; val='1414'; ms='2026.0'; btId='Metalama_Metalama20260_Consolidated_Claude'}
$issues = @( <list of @{num=...; val=...; ms=...; btId=...}> )
foreach ($issue in $issues) {
    $body = @{
        buildType = @{id = $issue.btId}
        properties = @{ property = @( @{name = "Issue"; value = $issue.val} ) }
    } | ConvertTo-Json -Depth 5 -Compress
    try {
        $result = Invoke-RestMethod -Uri 'https://postsharp.teamcity.com/app/rest/buildQueue' -Method Post -Headers $headers -ContentType 'application/json' -Body $body
        Write-Host "Triggered Claude build for #$($issue.num) (milestone $($issue.ms))`: Build #$($result.id) - $($result.webUrl)"
    } catch {
        Write-Host "FAILED to trigger for #$($issue.num)`: $($_.Exception.Message)"
    }
}
```

#### 4b. Close Merged Issues

For issues with status #0 ("Merged, not closed"), close the issue with a comment:

```
gh issue close <issue_number> --repo metalama/<repo> --comment "Closing: PR #<pr_number> has been merged."
```

#### 4d. Request @gfraiteur Review

For issues with status #6b ("Needs re-review") or #8 ("Needs review"), request a review from @gfraiteur:

```
gh api repos/metalama/<repo>/pulls/<pr_number>/requested_reviewers --method POST -f 'reviewers[]=gfraiteur'
```

After all actions, report what was triggered:
```
Triggered Claude build for #<number>: Build #<id> — <url>
Requested @gfraiteur review for #<number>: PR #<pr_number>
Closed issue #<number> (PR #<pr_number> was merged)
```

If there are no agent actions needed, skip this step.

### 5. Final Summary Table

**IMPORTANT:** After all auto-actions are complete, always end your response with a clean, final markdown summary table. This must be the very last thing displayed, so the user sees an easy-to-parse overview. Use the same table format as section 3, but ensure the **Link** column contains the single most actionable URL for each issue:

- If a human action is needed on a PR → link to the PR
- If a DebugBuild failed → link to the TC build
- If a Claude build is running/queued → link to the TC build
- Otherwise → link to the issue

This table is a repeat of the section 3 table, updated to reflect any auto-actions taken (e.g., if a Claude build was just triggered, the status should now say "Claude build queued" with a link to the build).

## Error Handling

- **No TEAMCITY_CLOUD_TOKEN**: Display warning that TeamCity data is unavailable, but still show GitHub data
- **GitHub API errors**: Display error and continue with available data
- **TeamCity API errors**: Display warning per-branch and continue; show TC columns as "unknown"
- **No issues found**: Display friendly "No open issues assigned to @PostSharpAgent" message
- **MCP output overflow**: If an MCP call result is truncated, the PowerShell script is dumping raw JSON. Fix by processing in-script and emitting only `Write-Host` lines with extracted fields.
