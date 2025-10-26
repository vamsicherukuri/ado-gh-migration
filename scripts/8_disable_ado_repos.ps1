# Copyright (c) 2025 Vamsi Cherukuri, Microsoft
# 
# MIT License
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# ADO2GH Step 8: Disable ADO Repositories
# 
# This script disables ADO repositories after successful migration and validation.
# It prevents further changes to the source repositories.
#
# Prerequisites:
# - Repositories must be successfully migrated (Step 2)
# - Repositories must be validated (Step 3)
# - Migration state file must exist
#
# Output Files:
# - disable-report-YYYYMMDD-HHmmss.md (repository disable report)
#
# Usage: .\8_disable_ado_repos.ps1 [-StateFile "migration-state-XXX.json"]

param(
    [string]$ConfigPath = "migration-config.json",
    [string]$StateFile = ""  # Optional override
)

# Dynamically find the script directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$scriptPath\MigrationHelpers.psm1" -Force -ErrorAction Stop

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Step 8: Disable ADO Repositories" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# 1. VALIDATE PAT TOKENS
Write-Host "[1/4] Validating PAT tokens..." -ForegroundColor Yellow
if (!(Test-RequiredPATs)) { exit 1 }

# 2. LOAD CONFIGURATION
Write-Host "`n[2/4] Loading configuration..." -ForegroundColor Yellow
$config = Get-MigrationConfig -ConfigPath $ConfigPath
if (!$config) { exit 1 }

# Use parameter override if provided, otherwise use config
if ([string]::IsNullOrEmpty($StateFile)) {
    $StateFile = $config.scripts.disableAdoRepos.stateFile
}

# 3. LOAD REPOSITORIES (from state file only)
Write-Host "`n[3/4] Loading repository information..." -ForegroundColor Yellow

# Try to find most recent state file if set to "auto"
if ($StateFile -eq "auto" -or [string]::IsNullOrEmpty($StateFile)) {
    $StateFile = Get-LatestStateFile
    if (!$StateFile) { exit 1 }
    Write-Host "📄 Found recent migration state: $StateFile" -ForegroundColor Cyan
}

# Load from state file
if (Test-Path $StateFile) {
    try {
        Write-Host "📂 Loading from migration state file: $StateFile" -ForegroundColor Cyan
        $migrationState = Get-Content -Path $StateFile -Raw | ConvertFrom-Json
        
        # Extract organization info from the migrated repositories (since not stored at top level)
        $REPOSITORIES = $migrationState.MigratedRepositories
        
        if ($REPOSITORIES.Count -eq 0) {
            Write-Host "❌ ERROR: No repositories found in state file" -ForegroundColor Red
            exit 1
        }
        
        # Get organization details from first successful migration
        $ADO_ORG = $REPOSITORIES[0].AdoOrganization
        
        Write-Host "✅ Loaded $($REPOSITORIES.Count) repository(ies) from migration state" -ForegroundColor Green
        Write-Host "   Migration timestamp: $($migrationState.MigrationTimestamp)" -ForegroundColor Gray
        Write-Host "   Successful migrations: $($migrationState.SuccessfulMigrations)/$($migrationState.TotalRepositories)" -ForegroundColor Gray
    } catch {
        Write-Host "❌ ERROR: Failed to load state file: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "❌ ERROR: State file not found: $StateFile" -ForegroundColor Red
    exit 1
}

Write-Host "`n   ADO Organization: $ADO_ORG" -ForegroundColor White
Write-Host "   Repositories to disable: $($REPOSITORIES.Count)" -ForegroundColor White

# 3. DISABLE ADO REPOSITORIES
Write-Host "`n[4/4] Disabling ADO repositories..." -ForegroundColor Yellow

Write-Host "`n⚠️  WARNING: This will prevent further changes to the ADO repositories!" -ForegroundColor Yellow
Write-Host "   Make sure all validations have passed before proceeding." -ForegroundColor Yellow
Write-Host "`n   Would you like to continue? (y/n):" -ForegroundColor Yellow
$confirmChoice = Read-Host

if ($confirmChoice.ToLower() -ne 'y' -and $confirmChoice.ToLower() -ne 'yes') {
    Write-Host "`n❌ Operation cancelled by user." -ForegroundColor Red
    Write-Host "   No repositories were disabled." -ForegroundColor Gray
    exit 0
}

Write-Host "`nProceeding with repository disabling..." -ForegroundColor Cyan

$disabledCount = 0
$failedCount = 0
$disableResults = @()

foreach ($repository in $REPOSITORIES) {
    $ADO_REPO = $repository.AdoRepository
    $ADO_TEAM_PROJECT = $repository.AdoTeamProject
    
    Write-Host "`n----------------------------------------" -ForegroundColor Gray
    Write-Host "Disabling: $ADO_REPO" -ForegroundColor Cyan
    Write-Host "   Team Project: $ADO_TEAM_PROJECT" -ForegroundColor Gray
    Write-Host "----------------------------------------" -ForegroundColor Gray
    
    # Disable the ADO repository
    gh ado2gh disable-ado-repo --ado-org $ADO_ORG --ado-team-project $ADO_TEAM_PROJECT --ado-repo $ADO_REPO
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ Successfully disabled: $ADO_REPO" -ForegroundColor Green
        $disabledCount++
        
        $disableResults += @{
            TeamProject = $ADO_TEAM_PROJECT
            Repository = $ADO_REPO
            Status = "Success"
            DisabledAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }
    } else {
        Write-Host "   ❌ Failed to disable: $ADO_REPO" -ForegroundColor Red
        $failedCount++
        
        $disableResults += @{
            TeamProject = $ADO_TEAM_PROJECT
            Repository = $ADO_REPO
            Status = "Failed"
            DisabledAt = ""
        }
    }
}

# 4. SUMMARY
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Disable Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Repositories: $($REPOSITORIES.Count)" -ForegroundColor White
Write-Host "Successfully Disabled: $disabledCount" -ForegroundColor $(if ($disabledCount -eq $REPOSITORIES.Count) { "Green" } else { "Yellow" })
Write-Host "Failed: $failedCount" -ForegroundColor $(if ($failedCount -gt 0) { "Red" } else { "Green" })

Write-Host "`n📋 Detailed Results:" -ForegroundColor White
foreach ($result in $disableResults) {
    $statusIcon = if ($result.Status -eq "Success") { "✅" } else { "❌" }
    $statusColor = if ($result.Status -eq "Success") { "Green" } else { "Red" }
    Write-Host "   $statusIcon $($result.Repository) | Status: $($result.Status)" -ForegroundColor $statusColor
}

# Save disable report
$currentTime = Get-Date
$timestamp = $currentTime.ToString("yyyy-MM-dd HH:mm:ss")
$reportFile = "disable-report-$($currentTime.ToString('yyyyMMdd-HHmmss')).md"

$reportContent = @"
# ADO Repository Disable Report - $timestamp

**ADO Organization:** $ADO_ORG  
**Disable Result:** $disabledCount/$($REPOSITORIES.Count) successful

## Repository Disable Results
| Team Project | Repository | Status | Disabled At |
|---|---|---|---|
$(foreach ($result in $disableResults) {
    $statusIcon = if ($result.Status -eq "Success") { "✓" } else { "✗" }
    "| $($result.TeamProject) | $($result.Repository) | $statusIcon $($result.Status) | $($result.DisabledAt) |"
})

## Summary
- **Total Repositories:** $($REPOSITORIES.Count)
- **Successfully Disabled:** $disabledCount/$($REPOSITORIES.Count)
- **Failed:** $failedCount
- **Overall Status:** $(if ($disabledCount -eq $REPOSITORIES.Count) { "✓ ALL REPOSITORIES DISABLED" } else { "⚠ SOME REPOSITORIES FAILED" })

---
*Generated by ADO2GH Disable Script at $timestamp*
"@

$reportContent | Out-File -FilePath $reportFile -Encoding UTF8
Write-Host "`n📄 Report saved: $reportFile" -ForegroundColor Gray

# Final status
if ($disabledCount -eq $REPOSITORIES.Count) {
    Write-Host "`n✅ All ADO repositories have been successfully disabled!" -ForegroundColor Green
    Write-Host "`n📋 Next Steps: Review the disable report: $reportFile" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "`n⚠️  Some repositories failed to disable. Please review the results above." -ForegroundColor Yellow
    Write-Host "   Report saved to: $reportFile" -ForegroundColor Gray
    exit 1
}
