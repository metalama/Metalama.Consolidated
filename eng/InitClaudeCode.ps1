# Configures Claude Code settings for autonomous operation.
# Run this script once before starting Claude Code in a container.

param(
    [string]$ClaudeHome = "$env:USERPROFILE\.claude"
)

$ErrorActionPreference = "Stop"

# Ensure .claude directory exists
if (-not (Test-Path $ClaudeHome)) {
    New-Item -ItemType Directory -Path $ClaudeHome -Force | Out-Null
}

$settingsPath = Join-Path $ClaudeHome "settings.json"

# Load existing settings or start fresh
if (Test-Path $settingsPath) {
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
} else {
    $settings = [PSCustomObject]@{}
}

# Ensure base settings
if (-not $settings.PSObject.Properties['hasCompletedOnboarding']) {
    # This goes in .claude.json, not settings.json - skip
}
if (-not $settings.PSObject.Properties['alwaysThinkingEnabled']) {
    $settings | Add-Member -NotePropertyName 'alwaysThinkingEnabled' -NotePropertyValue $true -Force
}
if (-not $settings.PSObject.Properties['spinnerTipsEnabled']) {
    $settings | Add-Member -NotePropertyName 'spinnerTipsEnabled' -NotePropertyValue $false -Force
}

# Configure PostToolUse hook for progress reminders
$hookCommand = @'
bash -c 'if [ -f /tmp/claude-last-progress ]; then ELAPSED=$(( $(date +%s) - $(cat /tmp/claude-last-progress) )); if [ $ELAPSED -gt 1800 ]; then echo "REMINDER: More than 30 minutes have elapsed since your last progress update. Post a progress comment to the GitHub issue NOW summarizing what you have done and what you are about to do. Then run: date +%s > /tmp/claude-last-progress"; fi; fi'
'@

$hooks = @{
    PostToolUse = @(
        @{
            matcher = "*"
            hooks = @(
                @{
                    type = "command"
                    command = $hookCommand.Trim()
                }
            )
        }
    )
}

$settings | Add-Member -NotePropertyName 'hooks' -NotePropertyValue $hooks -Force

# Write settings
$settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8

Write-Host "Claude Code settings written to $settingsPath" -ForegroundColor Green

# Ensure .claude.json exists with onboarding flag
$claudeJsonPath = Join-Path (Split-Path $ClaudeHome) ".claude.json"
if (-not (Test-Path $claudeJsonPath)) {
    @{ hasCompletedOnboarding = $true } | ConvertTo-Json | Set-Content $claudeJsonPath -Encoding UTF8
    Write-Host "Created $claudeJsonPath" -ForegroundColor Green
}


# Configure GitHub authentication
# gh CLI automatically uses the GITHUB_TOKEN env var, no login needed.
# For git push, configure git to use the token via URL rewriting.
if ($env:GITHUB_TOKEN) {
    git config --global url."https://x-access-token:$($env:GITHUB_TOKEN)@github.com/".insteadOf "https://github.com/"
    Write-Host "Git credential helper configured for github.com." -ForegroundColor Green
} else {
    Write-Warning "GITHUB_TOKEN environment variable is not set. git push and gh commands will not be authenticated."
}
