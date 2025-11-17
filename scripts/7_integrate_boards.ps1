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

# ADO2GH Step 7: Integrate Boards (Optional)
# 
# Description:
#   This script integrates Azure Boards with the migrated GitHub repositories.
#   It reads repository inventory from repos.csv and integrates each repository
#   with Azure Boards for cross-platform work item linking.
#
# Note: This is an OPTIONAL step. Azure Boards integration requires specific
#       GitHub PAT scopes and ADO PAT with "All organizations" access.
# 
# Prerequisites:
#   - ADO_PAT and GH_PAT environment variables set
#   - repos.csv from 0_Inventory.ps1
#   - Repositories already migrated to GitHub
#   - Proper PAT permissions for Boards integration
#
# Usage:
#   .\7_integrate_boards.ps1
#   .\7_integrate_boards.ps1 -ReposFile "custom-repos.csv"
#
# Order of Operations:
#   [1/5] Validate PAT tokens (ADO_PAT and GH_PAT)
#   [2/5] Load repository inventory from repos.csv (source of truth)
#   [3/5] Check for existing GitHub connections (prevent VS403674 error)
#   [4/5] Integrate boards for each repository
#   [5/5] Generate integration summary and log
#
# Input Files:
#   - repos.csv (from 0_Inventory.ps1 - repository inventory)
#
# Output Files:
#   - boards-integration-log-YYYYMMDD-HHmmss.txt (detailed integration log)

param(
    [string]$ReposFile = "repos.csv"  # Repository inventory file (current directory)
)

# Import helper module
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$scriptPath\MigrationHelpers.psm1" -Force -ErrorAction Stop

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Step 7: Integrate Boards (Optional)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# 1. CHECK PAT TOKENS
Write-Host "[1/5] Checking PAT tokens..." -ForegroundColor Yellow
if (!(Test-RequiredPATs)) { exit 1 }

# 2. LOAD REPOSITORY INVENTORY FROM CSV
Write-Host "`n[2/5] Loading repository inventory from repos.csv..." -ForegroundColor Yellow

# Check if repos.csv exists
if (-not (Test-Path $ReposFile)) {
    Write-Host "❌ ERROR: Repository inventory file not found: $ReposFile" -ForegroundColor Red
    Write-Host "   Please run 0_Inventory.ps1 first to generate the repository inventory." -ForegroundColor Yellow
    exit 1
}

# Load repositories from CSV
try {
    $allReposFromCsv = Import-Csv -Path $ReposFile
    
    if ($allReposFromCsv.Count -eq 0) {
        Write-Host "⚠️  No repositories found in inventory file" -ForegroundColor Yellow
        Write-Host "   Nothing to integrate. Exiting." -ForegroundColor Gray
        exit 0
    }
    
    # Validate required CSV columns
    $requiredColumns = @('org', 'teamproject', 'repo', 'ghorg', 'ghrepo')
    $csvColumns = $allReposFromCsv[0].PSObject.Properties.Name
    $missingColumns = $requiredColumns | Where-Object { $_ -notin $csvColumns }
    
    if ($missingColumns.Count -gt 0) {
        Write-Host "❌ ERROR: Missing required columns in CSV file: $($missingColumns -join ', ')" -ForegroundColor Red
        Write-Host "   Required columns: $($requiredColumns -join ', ')" -ForegroundColor Yellow
        Write-Host "   Please ensure 'ghorg' and 'ghrepo' columns are added to the inventory file." -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "✅ Loaded $($allReposFromCsv.Count) repository(ies) from inventory" -ForegroundColor Green
    
    # Group repositories by ADO organization and team project
    $reposByProject = $allReposFromCsv | Group-Object -Property org, teamproject
    Write-Host "   Projects with repositories: $($reposByProject.Count)" -ForegroundColor Gray
    
    foreach ($projectGroup in $reposByProject) {
        $projectParts = $projectGroup.Name -split ', '
        $projName = $projectParts[1]
        Write-Host "      📂 ${projName}: $($projectGroup.Count) repo(s)" -ForegroundColor Cyan
    }
    
} catch {
    Write-Host "❌ ERROR: Failed to load repository inventory: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 3. CHECK FOR EXISTING GITHUB CONNECTIONS
Write-Host "`n[3/5] Preparing for boards integration..." -ForegroundColor Yellow

# Track projects already checked for connections
$projectConnectionsChecked = @{}
$repositoriesToIntegrate = @()
$skippedRepos = @()

Write-Host "   Checking for existing GitHub connections per project..." -ForegroundColor Gray

# Process all repositories from CSV
foreach ($repoEntry in $allReposFromCsv) {
    $adoOrg = $repoEntry.org
    $adoTeamProject = $repoEntry.teamproject
    $adoRepo = $repoEntry.repo
    $githubOrg = $repoEntry.ghorg
    $githubRepo = $repoEntry.ghrepo
    
    # Check if this project already has a GitHub connection (only check once per project)
    $projectKey = "$adoOrg|$adoTeamProject"
    $hasExistingConnection = $false
    
    if (-not $projectConnectionsChecked.ContainsKey($projectKey)) {
        Write-Host "`n   🔍 Checking project: $adoTeamProject" -ForegroundColor Cyan
        
        try {
            # Query for existing GitHub Boards connections using REST API
            # Note: Boards connections are NOT service endpoints, must use githubconnections API
            $uri = "https://dev.azure.com/$adoOrg/$adoTeamProject/_apis/githubconnections?api-version=7.2-preview"
            $base64Pat = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$env:ADO_PAT"))
            $headers = @{
                Authorization = "Basic $base64Pat"
            }
            
            $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
            
            if ($response.value -and $response.value.Count -gt 0) {
                $hasExistingConnection = $true
                Write-Host "      ⚠️  Found $($response.value.Count) existing GitHub Boards connection(s)" -ForegroundColor Yellow
                foreach ($conn in $response.value) {
                    Write-Host "         - $($conn.name) (ID: $($conn.id))" -ForegroundColor DarkGray
                }
                Write-Host "      ℹ️  Skipping integration to avoid conflicts (VS403674 error)" -ForegroundColor Cyan
            } else {
                Write-Host "      ✅ No existing boards connections - will integrate" -ForegroundColor Green
            }
        } catch {
            Write-Host "      ⚠️  Could not check connections: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "      ℹ️  Will attempt integration anyway" -ForegroundColor Gray
        }
        
        $projectConnectionsChecked[$projectKey] = $hasExistingConnection
    } else {
        $hasExistingConnection = $projectConnectionsChecked[$projectKey]
    }
    
    # Add to appropriate list
    if ($hasExistingConnection) {
        $skippedRepos += [PSCustomObject]@{
            AdoOrganization = $adoOrg
            AdoTeamProject = $adoTeamProject
            AdoRepository = $adoRepo
            GitHubOrganization = $githubOrg
            GitHubRepository = $githubRepo
            Reason = "Project already has GitHub connection configured"
        }
    } else {
        $repositoriesToIntegrate += [PSCustomObject]@{
            AdoOrganization = $adoOrg
            AdoTeamProject = $adoTeamProject
            AdoRepository = $adoRepo
            GitHubOrganization = $githubOrg
            GitHubRepository = $githubRepo
        }
    }
}

Write-Host "`n✅ Pre-check complete" -ForegroundColor Green
Write-Host "   Repositories ready for integration: $($repositoriesToIntegrate.Count)" -ForegroundColor White
Write-Host "   Repositories skipped (existing connections): $($skippedRepos.Count)" -ForegroundColor Yellow

if ($repositoriesToIntegrate.Count -eq 0) {
    Write-Host "`n⚠️  No repositories to integrate - all projects have existing GitHub connections" -ForegroundColor Yellow
    Write-Host "   Total repositories: $($allReposFromCsv.Count), Skipped: $($skippedRepos.Count)" -ForegroundColor Gray
    exit 0
}

# 4. INTEGRATE BOARDS
Write-Host "`n[4/5] Integrating Azure Boards with GitHub repositories..." -ForegroundColor Yellow

$successCount = 0
$failureCount = 0
$skippedCount = $skippedRepos.Count
$results = @()

# Add skipped repos to results
foreach ($skipped in $skippedRepos) {
    $results += [PSCustomObject]@{
        AdoOrganization = $skipped.AdoOrganization
        AdoTeamProject = $skipped.AdoTeamProject
        AdoRepository = $skipped.AdoRepository
        GitHubOrganization = $skipped.GitHubOrganization
        GitHubRepository = $skipped.GitHubRepository
        Status = "⏭️ SKIPPED"
        Error = $skipped.Reason
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

foreach ($repoInfo in $repositoriesToIntegrate) {
    $adoOrg = $repoInfo.AdoOrganization
    $adoTeamProject = $repoInfo.AdoTeamProject
    $adoRepo = $repoInfo.AdoRepository
    $githubOrg = $repoInfo.GitHubOrganization
    $githubRepo = $repoInfo.GitHubRepository
    
    Write-Host "`n   🔄 Processing: $githubRepo" -ForegroundColor Cyan
    Write-Host "      ADO: $adoOrg/$adoTeamProject" -ForegroundColor Gray
    Write-Host "      GitHub: $githubOrg/$githubRepo" -ForegroundColor Gray
    
    try {
        # Execute integrate-boards command
        $integrationOutput = gh ado2gh integrate-boards `
            --github-org "$githubOrg" `
            --github-repo "$githubRepo" `
            --ado-org "$adoOrg" `
            --verbose `
            --ado-team-project "$adoTeamProject" 2>&1 | Out-String
        
        # Check for the conflict error specifically (fallback detection)
        if ($integrationOutput -match "VS403674.*existing connection conflicting") {
            $skippedCount++
            Write-Host "      ⏭️  SKIPPED (connection already exists)" -ForegroundColor Yellow
            $projectConnectionsChecked["$adoOrg|$adoTeamProject"] = $true  # Update cache
            $results += [PSCustomObject]@{
                AdoOrganization = $adoOrg
                AdoTeamProject = $adoTeamProject
                AdoRepository = $adoRepo
                GitHubOrganization = $githubOrg
                GitHubRepository = $githubRepo
                Status = "⏭️ SKIPPED"
                Error = "VS403674: GitHub connection already exists"
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            continue
        }
        
        # Check exit code for success
        if ($LASTEXITCODE -eq 0) {
            $successCount++
            Write-Host "      ✅ SUCCESS" -ForegroundColor Green
            $results += [PSCustomObject]@{
                AdoOrganization = $adoOrg
                AdoTeamProject = $adoTeamProject
                AdoRepository = $adoRepo
                GitHubOrganization = $githubOrg
                GitHubRepository = $githubRepo
                Status = "✅ SUCCESS"
                Error = ""
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        } else {
            $failureCount++
            Write-Host "      ❌ FAILED" -ForegroundColor Red
            Write-Host "         Error: $integrationOutput" -ForegroundColor DarkGray
            $results += [PSCustomObject]@{
                AdoOrganization = $adoOrg
                AdoTeamProject = $adoTeamProject
                AdoRepository = $adoRepo
                GitHubOrganization = $githubOrg
                GitHubRepository = $githubRepo
                Status = "❌ FAILED"
                Error = $integrationOutput.Trim()
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }
    } catch {
        $failureCount++
        Write-Host "      ❌ FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $results += [PSCustomObject]@{
            AdoOrganization = $adoOrg
            AdoTeamProject = $adoTeamProject
            AdoRepository = $adoRepo
            GitHubOrganization = $githubOrg
            GitHubRepository = $githubRepo
            Status = "❌ FAILED"
            Error = $_.Exception.Message
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
    
    Start-Sleep -Seconds 1
}

# 5. SUMMARY
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Boards Integration Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Repositories Processed: $($allReposFromCsv.Count)" -ForegroundColor White
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failureCount" -ForegroundColor Red
Write-Host "Skipped: $skippedCount" -ForegroundColor Yellow

# Generate integration log
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$logFile = "boards-integration-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

$logContent = @"
Azure Boards Integration Log - $timestamp
========================================
Total Repositories: $($allReposFromCsv.Count)
Repositories Ready for Integration: $($repositoriesToIntegrate.Count)
Repositories Skipped: $skippedCount
Successful: $successCount
Failed: $failureCount

Detailed Results:
$(foreach ($result in $results) {
    "$($result.Status): $($result.GitHubOrganization)/$($result.GitHubRepository) | ADO: $($result.AdoOrganization)/$($result.AdoTeamProject)$(if ($result.Error) { " | Error: $($result.Error)" })"
})
========================================
"@

$logContent | Out-File -FilePath $logFile -Encoding UTF8
Write-Host "`n📄 Log saved: $logFile" -ForegroundColor Gray

# Next steps
if ($successCount -gt 0 -and $failureCount -eq 0) {
    Write-Host "`n🎉 Boards integration completed successfully!" -ForegroundColor Green
    Write-Host "`n📝 Next Steps:" -ForegroundColor Cyan
    Write-Host "   1. Verify Azure Boards integration in GitHub repository settings" -ForegroundColor White
    Write-Host "   2. Test work item linking by creating/updating GitHub issues" -ForegroundColor White
    Write-Host "   3. Run: .\8_disable_ado_repos.ps1 (optional - disable ADO repositories)" -ForegroundColor White
    exit 0
} elseif ($successCount -gt 0 -and $failureCount -gt 0) {
    Write-Host "`n⚠️  Partial success: $successCount integrated, $failureCount failed" -ForegroundColor Yellow
    Write-Host "`n📝 Next Steps:" -ForegroundColor Cyan
    Write-Host "   1. Review failures in the log file: $logFile" -ForegroundColor White
    Write-Host "   2. Fix issues and retry if needed" -ForegroundColor White
    Write-Host "   3. For successful integrations, verify in GitHub repository settings" -ForegroundColor White
    exit 0
} else {
    Write-Host "`n❌ Boards integration encountered failures - review output and retry" -ForegroundColor Red
    exit 1
}
