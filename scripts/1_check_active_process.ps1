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

# Pre-Migration: Check for active pipelines and PRs on ADO repos
#
# Description: 
# This script checks for active processes (pipelines and PRs) on ADO repositories
# before migration. It should be run BEFORE starting the migration to ensure
# repositories are ready for migration.
#
# Order of operations:
# [1/5] Validate PAT tokens (ADO_PAT and GH_PAT)
# [2/5] Load configuration from migration-config.json with parameter overrides
# [3/5] Normalize repository input from parameters or CSV file
# [4/5] Check active processes (pipelines and PRs) for each repository
# [5/5] Summarize results and provide next steps
#
# Usage: 
# Check all repos reading from repo.csv generated from inventory report.
#   .\1_check_active_process.ps1 
# Check specific projects
#   .\1_check_active_process.ps1 -TeamProject "project"
# Check specific repositories within a project
#   .\1_check_active_process.ps1 -Repository "repo1" -TeamProject "project"
# Check multiple repositories within a project
#   .\1_check_active_process.ps1 -Repositories @("repo1", "repo2") -TeamProject "project"

param(
    [string]$ConfigPath = "migration-config.json",
    [string]$RepoCSV = "",  # Optional override
    [string]$AdoOrg = "",
    [string]$TeamProject = "",  # Optional: filter to specific team project
    [string]$Repository = "",  # Optional: single repository
    [string[]]$Repositories = @()  # Optional: multiple repositories
)

# Import helper module
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$scriptPath\MigrationHelpers.psm1" -Force -ErrorAction Stop

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Pre-Migration: Active Process Check" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# 1. Validate PAT tokens
Write-Host "[1/5] Validating PAT tokens..." -ForegroundColor Yellow
if (!(Test-RequiredPATs)) { exit 1 }

# 2. Load Configuration (migration-config.json)
Write-Host "`n[2/5] Loading configuration..." -ForegroundColor Yellow
$config = Get-MigrationConfig -ConfigPath $ConfigPath
if (!$config) { exit 1 }

# Use parameter overrides if provided, otherwise use config
if ([string]::IsNullOrEmpty($RepoCSV)) {
    $RepoCSV = $config.scripts.checkActiveProcess.repoCSV
}
if ([string]::IsNullOrEmpty($AdoOrg)) {
    $AdoOrg = $config.adoOrganization
}

# 3. Normalize repository input (The code after this comment takes all these different input methods and converts them into a single, consistent format - an array of PowerShell objects with the same structure)
Write-Host "`n[3/5] Normalizing repository input..." -ForegroundColor Yellow

$repoData = @()

if (-not [string]::IsNullOrEmpty($Repository)) {
    # Single repository specified via parameter
    if ([string]::IsNullOrEmpty($TeamProject)) {
        Write-Host "❌ ERROR: TeamProject parameter is required when using -Repository" -ForegroundColor Red
        exit 1
    }
    $repoData = @([PSCustomObject]@{
        org = $AdoOrg
        teamproject = $TeamProject
        repo = $Repository
    })
} elseif ($Repositories.Count -gt 0) {
    # Multiple repositories specified via parameter
    if ([string]::IsNullOrEmpty($TeamProject)) {
        Write-Host "❌ ERROR: TeamProject parameter is required when using -Repositories" -ForegroundColor Red
        exit 1
    }
    $repoData = $Repositories | ForEach-Object {
        [PSCustomObject]@{
            org = $AdoOrg
            teamproject = $TeamProject
            repo = $_
        }
    }
} else {
    # Load from CSV if no repositories specified
    if ([string]::IsNullOrEmpty($RepoCSV)) {
        Write-Host "❌ ERROR: No repositories specified and no CSV file configured" -ForegroundColor Red
        exit 1
    }
    
    if (-not (Test-Path $RepoCSV)) {
        Write-Host "❌ ERROR: Repository CSV file not found: $RepoCSV" -ForegroundColor Red
        exit 1
    }
    
    try {
        $repoData = Import-Csv -Path $RepoCSV | Where-Object { 
            $_.org -and $_.teamproject -and $_.repo
        }
        
        if ($repoData.Count -eq 0) {
            Write-Host "❌ ERROR: No valid repository data found in CSV" -ForegroundColor Red
            Write-Host "   Ensure CSV has columns: org, teamproject, repo" -ForegroundColor Yellow
            exit 1
        }
        
        # If TeamProject parameter specified, filter to only that project
        if (-not [string]::IsNullOrEmpty($TeamProject)) {
            $repoData = $repoData | Where-Object { $_.teamproject -eq $TeamProject }
            if ($repoData.Count -eq 0) {
                Write-Host "❌ ERROR: No repositories found for team project '$TeamProject' in CSV" -ForegroundColor Red
                exit 1
            }
        }
        
        Write-Host "✅ Loaded $($repoData.Count) repositories from $RepoCSV" -ForegroundColor Green
    } catch {
        Write-Host "❌ ERROR: Failed to load CSV: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Write-Host "✅ Repository input validated" -ForegroundColor Green
Write-Host "`n   ADO Organization: $AdoOrg" -ForegroundColor White
if (-not [string]::IsNullOrEmpty($TeamProject)) {
    Write-Host "   Team Project: $TeamProject (filtered)" -ForegroundColor White
} else {
    $uniqueProjects = ($repoData | Select-Object -ExpandProperty teamproject -Unique)
    Write-Host "   Team Projects: $($uniqueProjects.Count) ($($uniqueProjects -join ', '))" -ForegroundColor White
}
Write-Host "   Repositories to check: $($repoData.Count)" -ForegroundColor White

# Helper function to check for active processes on a specific repository
function Test-ActiveProcesses {
    param(
        [string]$TeamProject,
        [string]$Repository
    )
    
    $hasActiveProcesses = $false
    $details = @{
        hasActivePipelines = $false
        pipelineCount = 0
        hasActivePRs = $false
        prCount = 0
        warnings = @()
    }
    
    # Check for in-progress pipelines
    try {
        $pipelineOutput = az pipelines runs list --project $TeamProject --status inProgress --output table 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $lines = $pipelineOutput -split "`n" | Where-Object { $_.Trim() -ne "" }
            if ($lines.Count -gt 2) {
                $details.pipelineCount = $lines.Count - 2
                $details.hasActivePipelines = $true
                $hasActiveProcesses = $true
            }
        }
    } catch {
        $details.warnings += "Could not check pipelines"
    }
    
    # Check for active pull requests on this repository
    try {
        $prOutput = az repos pr list --project $TeamProject --repository $Repository --status active --output table 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $lines = $prOutput -split "`n" | Where-Object { $_.Trim() -ne "" }
            if ($lines.Count -gt 2) {
                $details.prCount = $lines.Count - 2
                $details.hasActivePRs = $true
                $hasActiveProcesses = $true
            }
        }
    } catch {
        $details.warnings += "Could not check pull requests"
    }
    
    return @{
        hasActiveProcesses = $hasActiveProcesses
        details = $details
    }
}

# 4. Check Active Processes
Write-Host "`n[4/5] Checking for active processes on all repositories..." -ForegroundColor Yellow
Write-Host "   This may take a few minutes..." -ForegroundColor Gray

$readyRepos = @()
$blockedRepos = @()
$currentIndex = 0

foreach ($repoItem in $repoData) {
    $currentIndex++
    
    Write-Host "`n[$currentIndex/$($repoData.Count)] Checking: $($repoItem.repo)" -ForegroundColor Cyan
    Write-Host "   Organization: $($repoItem.org)" -ForegroundColor Gray
    Write-Host "   Team Project: $($repoItem.teamproject)" -ForegroundColor Gray
    
    $checkResult = Test-ActiveProcesses -TeamProject $repoItem.teamproject -Repository $repoItem.repo
    $details = $checkResult.details
    
    # Display results
    if ($details.hasActivePipelines) {
        Write-Host "   ⚠️  Active Pipelines: $($details.pipelineCount)" -ForegroundColor Yellow
    } else {
        Write-Host "   ✅ No active pipelines" -ForegroundColor Green
    }
    
    if ($details.hasActivePRs) {
        Write-Host "   ⚠️  Active Pull Requests: $($details.prCount)" -ForegroundColor Yellow
    } else {
        Write-Host "   ✅ No active pull requests" -ForegroundColor Green
    }
    
    if ($details.warnings.Count -gt 0) {
        foreach ($warning in $details.warnings) {
            Write-Host "   ⚠️  $warning" -ForegroundColor Yellow
        }
    }
    
    # Categorize repository
    if ($checkResult.hasActiveProcesses) {
        Write-Host "   🚫 STATUS: BLOCKED - Not ready for migration" -ForegroundColor Red
        $blockedRepos += [PSCustomObject]@{
            org = $repoItem.org
            teamproject = $repoItem.teamproject
            repository = $repoItem.repo
            activePipelines = $details.pipelineCount
            activePRs = $details.prCount
        }
    } else {
        Write-Host "   ✅ STATUS: READY for migration" -ForegroundColor Green
        $readyRepos += [PSCustomObject]@{
            org = $repoItem.org
            teamproject = $repoItem.teamproject
            repository = $repoItem.repo
        }
    }
}

# 5. Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Active Process Check Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ADO Organization: $AdoOrg" -ForegroundColor White
if (-not [string]::IsNullOrEmpty($TeamProject)) {
    Write-Host "Team Project: $TeamProject (filtered)" -ForegroundColor White
} else {
    $uniqueProjects = ($repoData | Select-Object -ExpandProperty teamproject -Unique)
    Write-Host "Team Projects: $($uniqueProjects.Count) checked" -ForegroundColor White
}
Write-Host "Total Repositories Checked: $($repoData.Count)" -ForegroundColor White
Write-Host "✅ Ready for Migration: $($readyRepos.Count)" -ForegroundColor Green
Write-Host "🚫 Blocked (Active Processes): $($blockedRepos.Count)" -ForegroundColor Red

# Show ready repositories
if ($readyRepos.Count -gt 0) {
    Write-Host "`n📋 Repositories Ready for Migration:" -ForegroundColor Green
    foreach ($repo in $readyRepos) {
        Write-Host "   ✅ $($repo.teamproject)/$($repo.repository)" -ForegroundColor Green
    }
}

# Show blocked repositories
if ($blockedRepos.Count -gt 0) {
    Write-Host "`n📋 Blocked Repositories (Active Processes):" -ForegroundColor Red
    foreach ($repo in $blockedRepos) {
        Write-Host "   🚫 $($repo.teamproject)/$($repo.repository)" -ForegroundColor Red
        if ($repo.activePipelines -gt 0) {
            Write-Host "      - Active Pipelines: $($repo.activePipelines)" -ForegroundColor Yellow
        }
        if ($repo.activePRs -gt 0) {
            Write-Host "      - Active PRs: $($repo.activePRs)" -ForegroundColor Yellow
        }
    }
}

# Next Steps
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Next Steps" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($readyRepos.Count -gt 0 -and $blockedRepos.Count -eq 0) {
    Write-Host "✅ All repositories are ready for migration!" -ForegroundColor Green
    Write-Host "`n📋 NEXT STEP:" -ForegroundColor Cyan
    Write-Host "   Run: .\2_migrate_repo.ps1" -ForegroundColor White
    exit 0
} elseif ($readyRepos.Count -gt 0 -and $blockedRepos.Count -gt 0) {
    Write-Host "⚠️  Some repositories are ready, but others are blocked" -ForegroundColor Yellow
    Write-Host "`n📋 NEXT STEP:" -ForegroundColor Cyan
    Write-Host "   - Proceed with migration for ready repositories" -ForegroundColor White
    Write-Host "   - Wait for active processes, then re-run this check for blocked repos" -ForegroundColor White
    exit 0
} else {
    Write-Host "🚫 All repositories are blocked by active processes" -ForegroundColor Red
    Write-Host "`n📋 NEXT STEP:" -ForegroundColor Cyan
    Write-Host "   Wait for active processes to complete, then re-run this check" -ForegroundColor White
    exit 1
}
