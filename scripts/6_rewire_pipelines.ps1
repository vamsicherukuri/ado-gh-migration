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

# ADO2GH Step 6: Rewire Pipelines
# 
# Description:
#   This script rewires Azure DevOps pipelines to use the new GitHub repositories.
#   It reads pipeline inventory from pipelines.csv and updates YAML pipelines
#   to point to the corresponding GitHub repositories using a service connection.
#
# Prerequisites:
#   - ADO_PAT and GH_PAT environment variables set
#   - GitHub service connection configured in Azure DevOps
#   - Migration state file from 2_migrate_repo.ps1
#   - pipelines.csv from 0_Inventory.ps1
#   - migration-config.json exists with proper configuration
#
# Order of operations:
# [1/7] Validate PAT tokens (ADO_PAT and GH_PAT)
# [2/7] Load configuration from migration-config.json with parameter overrides
# [3/7] Load migration state file with successfully migrated repositories
# [4/7] Load pipeline inventory from pipelines.csv (source of truth)
# [5/7] Process pipelines from inventory:
#       - Query pipeline details (YAML vs Classic, already on GitHub)
#       - Skip Classic pipelines (require manual rewiring)
#       - Skip pipelines already rewired to GitHub
#       - Map ADO repo to GitHub repo using migration state
# [6/7] Validate service connections per project:
#       - Query GitHub service connections for each project
#       - Test connection authentication with dry-run
#       - Exclude projects with no connections or invalid credentials
# [7/7] Rewire pipelines using project-specific service connections
#
# Usage:
#   .\6_rewire_pipelines.ps1
#   .\6_rewire_pipelines.ps1 -StateFile "migration-state-YYYYMMDD-HHMMSS.json"
#   .\6_rewire_pipelines.ps1 -ConfigPath "custom-config.json"
#
# Input Files:
#   - migration-state-comprehensive-YYYYMMDD-HHMMSS.json (from 2_migrate_repo.ps1)
#   - migration-config.json (contains configuration paths)
#   - pipelines.csv (from 0_Inventory.ps1 - pipeline inventory)
#
# Output Files:
#   - pipeline-rewiring-log-YYYYMMDD-HHMMSS.txt (detailed rewiring log)

param(
    [string]$ConfigPath = "migration-config.json",
    [string]$StateFile = "",  # Optional override
    [string]$PipelinesFile = "pipelines.csv"  # Pipeline inventory file
)

# Import helper module
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$scriptPath\MigrationHelpers.psm1" -Force -ErrorAction Stop

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Step 6: Rewire Pipelines" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# 1. Validate PAT tokens
Write-Host "[1/7] Validating PAT tokens..." -ForegroundColor Yellow
if (!(Test-RequiredPATs)) { exit 1 }

# 2. Load configuration
Write-Host "`n[2/7] Loading configuration..." -ForegroundColor Yellow
$config = Get-MigrationConfig -ConfigPath $ConfigPath
if (!$config) { exit 1 }

# Use parameter override if provided, otherwise use config
if ([string]::IsNullOrEmpty($StateFile)) {
    $StateFile = $config.scripts.rewirePipelines.stateFile
}

# 3. Load migration state
Write-Host "`n[3/7] Loading migration state..." -ForegroundColor Yellow

$StateFile = Get-LatestStateFile -StateFile $StateFile
if (!$StateFile) { exit 1 }

# Load from state file
try {
    Write-Host "📂 Loading from migration state file: $StateFile" -ForegroundColor Cyan
    $migrationState = Get-Content -Path $StateFile -Raw | ConvertFrom-Json
    
    # All repositories in the state file are successful migrations
    $REPOSITORIES = $migrationState.MigratedRepositories
    
    if ($REPOSITORIES.Count -eq 0) {
        Write-Host "❌ ERROR: No migrated repositories found in state file" -ForegroundColor Red
        exit 1
    }
    
    # Get organization details from first successful migration
    $ADO_ORG = $REPOSITORIES[0].AdoOrganization
    $GITHUB_ORG = $REPOSITORIES[0].GitHubOrganization
    
    # Group repositories by team project
    $projectGroups = $REPOSITORIES | Group-Object -Property AdoTeamProject
    
    Write-Host "✅ Loaded $($REPOSITORIES.Count) successful migration(s) from state file" -ForegroundColor Green
    Write-Host "   Migration timestamp: $($migrationState.MigrationTimestamp)" -ForegroundColor Gray
    Write-Host "   ADO Organization: $ADO_ORG" -ForegroundColor Gray
    Write-Host "   GitHub Organization: $GITHUB_ORG" -ForegroundColor Gray
    Write-Host "   Team Projects: $($projectGroups.Count)" -ForegroundColor Gray
    
    foreach ($projectGroup in $projectGroups) {
        Write-Host "      - $($projectGroup.Name): $($projectGroup.Count) repo(s)" -ForegroundColor Cyan
    }
} catch {
    Write-Host "❌ ERROR: Failed to load state file: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 4. Load pipeline inventory from CSV
Write-Host "`n[4/7] Loading pipeline inventory from pipelines.csv..." -ForegroundColor Yellow

# Check if pipelines.csv exists
if (-not (Test-Path $PipelinesFile)) {
    Write-Host "❌ ERROR: Pipeline inventory file not found: $PipelinesFile" -ForegroundColor Red
    Write-Host "   Please run 0_Inventory.ps1 first to generate the pipeline inventory." -ForegroundColor Yellow
    exit 1
}

# Load pipelines from CSV
try {
    $allPipelinesFromCsv = Import-Csv -Path $PipelinesFile
    
    if ($allPipelinesFromCsv.Count -eq 0) {
        Write-Host "⚠️  No pipelines found in inventory file" -ForegroundColor Yellow
        Write-Host "   Nothing to rewire. Exiting." -ForegroundColor Gray
        exit 0
    }
    
    Write-Host "✅ Loaded $($allPipelinesFromCsv.Count) pipeline(s) from inventory" -ForegroundColor Green
    
    # Group pipelines by project for display
    $pipelinesByProject = $allPipelinesFromCsv | Group-Object -Property teamproject
    Write-Host "   Projects with pipelines: $($pipelinesByProject.Count)" -ForegroundColor Gray
    
    foreach ($projectGroup in $pipelinesByProject) {
        Write-Host "      📂 $($projectGroup.Name): $($projectGroup.Count) pipeline(s)" -ForegroundColor Cyan
    }
    
} catch {
    Write-Host "❌ ERROR: Failed to load pipeline inventory: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 5. Process pipelines from inventory
Write-Host "`n[5/7] Processing pipelines from inventory..." -ForegroundColor Yellow

# Build mapping: ADO Repo → GitHub Repo from successfully migrated repositories
$repoMapping = New-RepositoryMapping -Repositories $REPOSITORIES

Write-Host "   Migrated repositories:" -ForegroundColor Cyan
foreach ($key in $repoMapping.Keys) {
    $mapping = $repoMapping[$key]
    Write-Host "      📁 $($mapping.AdoTeamProject)/$($mapping.AdoRepository) → $($mapping.GitHubRepository)" -ForegroundColor Gray
}

# Process all pipelines from CSV (CSV is source of truth)
$pipelinesToRewire = @()
$skippedPipelines = @()

Write-Host "`n   Checking pipeline details..." -ForegroundColor Cyan

foreach ($pipelineEntry in $allPipelinesFromCsv) {
    $projectName = $pipelineEntry.teamproject
    $repoName = $pipelineEntry.repo
    $pipelineName = $pipelineEntry.pipeline
    $pipelineUrl = $pipelineEntry.url
    
    # Extract pipeline ID from URL (e.g., definitionId=17)
    $pipelineId = $null
    if ($pipelineUrl -match "definitionId=(\d+)") {
        $pipelineId = $matches[1]
    }
    
    # Get GitHub repo name from migration mapping
    $lookupKey = "$projectName|$repoName"
    $githubRepoName = $null
    
    if ($repoMapping.ContainsKey($lookupKey)) {
        $githubRepoName = $repoMapping[$lookupKey].GitHubRepository
    } else {
        # Repo not in migration state - assume same name
        $githubRepoName = $repoName
        Write-Host "      ℹ️  $pipelineName → repo not in migration state, using same name: $repoName" -ForegroundColor Gray
    }
    
    # Query pipeline details to check if it's YAML and not already on GitHub
    try {
        $pipelineDetails = az pipelines show --org "https://dev.azure.com/$ADO_ORG" --project "$projectName" --id $pipelineId -o json 2>$null | ConvertFrom-Json
        
        if ($null -eq $pipelineDetails) {
            Write-Host "      ⚠️  $pipelineName → could not retrieve details (skip)" -ForegroundColor Yellow
            $skippedPipelines += [PSCustomObject]@{
                Project = $projectName
                Name = $pipelineName
                Reason = "Could not retrieve pipeline details"
            }
            continue
        }
        
        # Check pipeline type (Classic vs YAML)
        $processType = $pipelineDetails.process.type
        
        # Type 1 = Classic/Visual Designer (not supported by gh ado2gh)
        # Type 2 = YAML
        if ($processType -eq 1) {
            Write-Host "      ⚠️  $pipelineName → Classic pipeline (manual rewiring required)" -ForegroundColor Yellow
            $skippedPipelines += [PSCustomObject]@{
                Project = $projectName
                Name = $pipelineName
                Reason = "Classic/Visual Designer pipeline - not supported by gh ado2gh rewire-pipeline"
            }
            continue
        }
        
        # Check if pipeline is already using GitHub repository
        if ($pipelineDetails.repository -and $pipelineDetails.repository.type -eq "GitHub") {
            Write-Host "      ⏭️  $pipelineName → already using GitHub (skip)" -ForegroundColor Gray
            $skippedPipelines += [PSCustomObject]@{
                Project = $projectName
                Name = $pipelineName
                Reason = "Already rewired to GitHub"
            }
            continue
        }
        
        # This is a YAML pipeline that needs rewiring
        $pipelinesToRewire += [PSCustomObject]@{
            Id = $pipelineId
            Name = $pipelineName
            Project = $projectName
            AdoRepo = $repoName
            GitHubRepo = $githubRepoName
        }
        Write-Host "      ✅ $pipelineName → uses $repoName (will rewire to $githubRepoName)" -ForegroundColor Green
        
    } catch {
        Write-Host "      ⚠️  $pipelineName → error checking details: $($_.Exception.Message)" -ForegroundColor Yellow
        $skippedPipelines += [PSCustomObject]@{
            Project = $projectName
            Name = $pipelineName
            Reason = "Error: $($_.Exception.Message)"
        }
    }
}

if ($pipelinesToRewire.Count -eq 0) {
    Write-Host "`n❌ No YAML pipelines found to rewire" -ForegroundColor Red
    Write-Host "   Total pipelines in inventory: $($allPipelinesFromCsv.Count)" -ForegroundColor Yellow
    
    if ($skippedPipelines.Count -gt 0) {
        Write-Host "   Skipped pipelines: $($skippedPipelines.Count)" -ForegroundColor Yellow
        Write-Host "`n   Skipped pipeline reasons:" -ForegroundColor Cyan
        $skippedPipelines | Group-Object -Property Reason | ForEach-Object {
            Write-Host "      - $($_.Name): $($_.Count)" -ForegroundColor Gray
        }
    }
    
    exit 1
}

Write-Host "`n✅ Found $($pipelinesToRewire.Count) YAML pipeline(s) to rewire" -ForegroundColor Green

# 6. Validate service connections per project
Write-Host "`n[6/7] Validating service connections per project..." -ForegroundColor Yellow

# Query service connections for each project that has pipelines to rewire
$projectsNeedingRewire = $pipelinesToRewire | Group-Object -Property Project
$serviceConnectionsByProject = @{}
$projectsWithoutConnections = @()
$projectsWithInvalidConnections = @()

foreach ($projectGroup in $projectsNeedingRewire) {
    $projectName = $projectGroup.Name
    
    Write-Host "`n   📂 Checking project: $projectName" -ForegroundColor Cyan
    
    try {
        $serviceConnections = Get-ProjectServiceConnections -AdoOrg $ADO_ORG -ProjectName $projectName
        
        if ($null -eq $serviceConnections -or $serviceConnections.Count -eq 0) {
            Write-Host "      ⚠️  No GitHub service connections found" -ForegroundColor Yellow
            $projectsWithoutConnections += $projectName
            continue
        }
        
        # Prioritize GitHub service connections and filter by isReady
        $githubConnections = $serviceConnections | Where-Object { $_.isReady -eq $true } | Sort-Object { $_.type -ne "github" }, name
        
        if ($null -eq $githubConnections -or $githubConnections.Count -eq 0) {
            Write-Host "      ⚠️  Found $($serviceConnections.Count) service connection(s) but none are ready/authenticated" -ForegroundColor Yellow
            foreach ($conn in $serviceConnections) {
                Write-Host "         - $($conn.name) (Type: $($conn.type), Ready: $($conn.isReady))" -ForegroundColor Yellow
            }
            $projectsWithInvalidConnections += $projectName
            continue
        }
        
        # Test the first connection by attempting a simple test rewire
        $testConnection = $githubConnections[0]
        Write-Host "      🔍 Testing service connection: $($testConnection.name)..." -ForegroundColor Gray
        
        # Get a sample pipeline from this project to test with
        $testPipeline = $projectGroup.Group[0]
        
        $testOutput = gh ado2gh rewire-pipeline `
            --ado-org "$ADO_ORG" `
            --ado-team-project "$projectName" `
            --ado-pipeline "$($testPipeline.Name)" `
            --github-org "$GITHUB_ORG" `
            --github-repo "$($testPipeline.GitHubRepo)" `
            --service-connection-id "$($testConnection.id)" `
            --dry-run 2>&1 | Out-String
        
        # Check if the test failed with GitHub authentication error specifically
        # Ignore pipeline configuration errors (like missing variable groups) - those are separate issues
        if ($testOutput -match "Requires authentication|Unable to configure a service.*GitHub returned") {
            Write-Host "      ⚠️  Service connection authentication failed (GitHub authentication error)" -ForegroundColor Yellow
            Write-Host "         Connection exists but cannot authenticate with GitHub" -ForegroundColor Yellow
            Write-Host "         - $($testConnection.name) (Type: $($testConnection.type))" -ForegroundColor Yellow
            $projectsWithInvalidConnections += $projectName
            continue
        }
        
        Write-Host "      ✅ Service connection authenticated successfully:" -ForegroundColor Green
        Write-Host "         - $($testConnection.name) (Type: $($testConnection.type))" -ForegroundColor Gray
        
        # Store the validated GitHub connection for this project
        $serviceConnectionsByProject[$projectName] = $testConnection.id
        
    } catch {
        Write-Host "      ❌ Error querying service connections: $($_.Exception.Message)" -ForegroundColor Red
        $projectsWithoutConnections += $projectName
    }
}

# Filter out pipelines from projects without service connections
$validPipelines = @()
$pipelinesSkippedNoConnection = @()

foreach ($pipeline in $pipelinesToRewire) {
    if ($serviceConnectionsByProject.ContainsKey($pipeline.Project)) {
        $validPipelines += $pipeline
    } else {
        $reason = if ($projectsWithInvalidConnections -contains $pipeline.Project) {
            "Service connection exists but is not authenticated/ready"
        } else {
            "No GitHub service connection available in project"
        }
        
        $pipelinesSkippedNoConnection += [PSCustomObject]@{
            Project = $pipeline.Project
            Name = $pipeline.Name
            Reason = $reason
        }
    }
}

$totalIdentified = $pipelinesToRewire.Count
$pipelinesToRewire = $validPipelines

if ($projectsWithoutConnections.Count -gt 0 -or $projectsWithInvalidConnections.Count -gt 0) {
    Write-Host "`n⚠️  Service Connection Issues:" -ForegroundColor Yellow
    
    if ($projectsWithoutConnections.Count -gt 0) {
        Write-Host "   No connections: " -NoNewline -ForegroundColor Yellow
        Write-Host "$($projectsWithoutConnections -join ', ')" -ForegroundColor White
    }
    
    if ($projectsWithInvalidConnections.Count -gt 0) {
        Write-Host "   Invalid/unauthenticated: " -NoNewline -ForegroundColor Yellow
        Write-Host "$($projectsWithInvalidConnections -join ', ')" -ForegroundColor White
    }
    
    Write-Host "`n💡 To fix: Create or update GitHub service connection in Azure DevOps project settings" -ForegroundColor Cyan
    Write-Host "   Or share existing: gh ado2gh share-service-connection --ado-org '$ADO_ORG' --ado-team-project '<project>' --service-connection-id '<id>'" -ForegroundColor Gray
}

if ($pipelinesToRewire.Count -eq 0) {
    Write-Host "`n❌ No pipelines can be rewired - all projects lack valid GitHub service connections" -ForegroundColor Red
    Write-Host "   Total identified: $totalIdentified, Skipped: $($pipelinesSkippedNoConnection.Count)" -ForegroundColor Yellow
    exit 1
}

Write-Host "`n✅ Service connection validation complete" -ForegroundColor Green
Write-Host "   Projects ready: $($serviceConnectionsByProject.Keys.Count), Pipelines: $($pipelinesToRewire.Count)" -ForegroundColor White

# 7. Rewire pipelines
Write-Host "`n[7/7] Rewiring pipelines..." -ForegroundColor Yellow
Write-Host "   Processing $($pipelinesToRewire.Count) pipeline(s) across $($serviceConnectionsByProject.Keys.Count) project(s)..." -ForegroundColor Gray

$successCount = 0
$failureCount = 0
$results = @()

foreach ($pipelineRecord in $pipelinesToRewire) {
    $pipelineName = $pipelineRecord.Name
    $projectName = $pipelineRecord.Project
    $repoName = $pipelineRecord.AdoRepo
    $githubRepo = $pipelineRecord.GitHubRepo
    
    # Get the service connection for this project
    $serviceConnectionId = $serviceConnectionsByProject[$projectName]
    
    Write-Host "`n   🔄 Processing: $pipelineName" -ForegroundColor Cyan
    Write-Host "      Project: $projectName" -ForegroundColor Gray
    Write-Host "      ADO Repo: $repoName → GitHub Repo: $githubRepo" -ForegroundColor Gray
    Write-Host "      Service Connection ID: $serviceConnectionId" -ForegroundColor Gray
    
    gh ado2gh rewire-pipeline `
        --ado-org "$ADO_ORG" `
        --ado-team-project "$projectName" `
        --ado-pipeline "$pipelineName" `
        --github-org "$GITHUB_ORG" `
        --github-repo "$githubRepo" `
        --service-connection-id "$serviceConnectionId"
    
    if ($LASTEXITCODE -eq 0) {
        $successCount++
        Write-Host "      ✅ SUCCESS" -ForegroundColor Green
        $results += [PSCustomObject]@{
            Project = $projectName
            Pipeline = $pipelineName
            AdoRepo = $repoName
            GitHubRepo = $githubRepo
            Status = "✅ SUCCESS"
        }
    } else {
        $failureCount++
        Write-Host "      ❌ FAILED" -ForegroundColor Red
        $results += [PSCustomObject]@{
            Project = $projectName
            Pipeline = $pipelineName
            AdoRepo = $repoName
            GitHubRepo = $githubRepo
            Status = "❌ FAILED"
        }
    }
    
    Start-Sleep -Seconds 2
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Pipeline Rewiring Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Pipelines Processed: $($pipelinesToRewire.Count)" -ForegroundColor White
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failureCount" -ForegroundColor Red

if ($skippedPipelines.Count -gt 0) {
    Write-Host "`n⏭️  Skipped Pipelines: $($skippedPipelines.Count)" -ForegroundColor Yellow
    
    # Group skipped pipelines by reason
    $skippedByReason = $skippedPipelines | Group-Object -Property Reason
    foreach ($reasonGroup in $skippedByReason) {
        Write-Host "   $($reasonGroup.Name): $($reasonGroup.Count)" -ForegroundColor Gray
        
        # Show classic pipelines with manual steps
        if ($reasonGroup.Name -like "*Classic*") {
            Write-Host "      💡 Manual Steps: Edit pipeline → Change 'Get sources' from Azure Repos to GitHub → Select service connection → Save" -ForegroundColor Cyan
        }
    }
    
    # Highlight Classic pipelines requiring manual attention
    $classicPipelines = $skippedPipelines | Where-Object { $_.Reason -like "*Classic*" }
    if ($classicPipelines.Count -gt 0) {
        Write-Host "`n⚠️  Classic Pipelines Requiring Manual Rewiring: $($classicPipelines.Count)" -ForegroundColor Yellow
        foreach ($classic in $classicPipelines) {
            Write-Host "   📌 $($classic.Project)/$($classic.Name)" -ForegroundColor Gray
        }
        Write-Host "   💡 These pipelines use the Visual Designer and cannot be automatically rewired." -ForegroundColor Cyan
        Write-Host "   💡 You must manually update the 'Get sources' task in each pipeline to point to GitHub." -ForegroundColor Cyan
    }
}

if ($pipelinesSkippedNoConnection.Count -gt 0) {
    Write-Host "`n⚠️  Skipped (no service connection): $($pipelinesSkippedNoConnection.Count)" -ForegroundColor Yellow
    $skippedConnByProject = $pipelinesSkippedNoConnection | Group-Object -Property Project
    foreach ($projectGroup in $skippedConnByProject) {
        Write-Host "   $($projectGroup.Name): $($projectGroup.Group.Name -join ', ')" -ForegroundColor Gray
    }
}

Write-Host "`n📋 Detailed Results:" -ForegroundColor Cyan
foreach ($result in $results) {
    Write-Host "   $($result.Status) | $($result.Project)/$($result.Pipeline) | $($result.AdoRepo) → $($result.GitHubRepo)" -ForegroundColor Gray
}

# Generate rewiring log
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$logFile = "pipeline-rewiring-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

$logContent = @"
Pipeline Rewiring Log - $timestamp
========================================
ADO Organization: $ADO_ORG
GitHub Organization: $GITHUB_ORG
Service Connections: Multiple (per project) - See detailed results below
Total Pipelines in Inventory: $($allPipelinesFromCsv.Count)
YAML Pipelines Identified for Rewiring: $($pipelinesToRewire.Count)
Pipelines Skipped: $($skippedPipelines.Count)
Successful: $successCount
Failed: $failureCount

Detailed Results (Rewired Pipelines):
$(foreach ($result in $results) {
    "$($result.Status): $($result.Project)/$($result.Pipeline) | $($result.AdoRepo) → $($result.GitHubRepo)"
})

Skipped Pipelines:
$(foreach ($skipped in $skippedPipelines) {
    "  $($skipped.Project)/$($skipped.Name) - $($skipped.Reason)"
})

Pipelines Skipped (No Service Connection):
$(foreach ($skip in $pipelinesSkippedNoConnection) {
    "  $($skip.Project)/$($skip.Name)"
})
========================================
"@

$logContent | Out-File -FilePath $logFile -Encoding UTF8
Write-Host "`n📄 Log saved: $logFile" -ForegroundColor Gray

# Next steps
if ($successCount -gt 0) {
    Write-Host "`n🎉 Pipeline rewiring completed successfully!" -ForegroundColor Green
    Write-Host "`n📊 Next Steps:" -ForegroundColor Cyan
    Write-Host "   1. Test rewired pipelines in Azure DevOps" -ForegroundColor White
    Write-Host "   2. Verify pipeline runs complete successfully" -ForegroundColor White
    Write-Host "   3. Run: .\7_integrate_boards.ps1 (optional - Azure Boards integration)" -ForegroundColor White
    Write-Host "   4. Run: .\8_disable_ado_repos.ps1 (optional - disable ADO repositories)" -ForegroundColor White
    Write-Host "   5. Update documentation with new GitHub repository URLs" -ForegroundColor White
    exit 0
} elseif ($successCount -gt 0 -and $failureCount -gt 0) {
    Write-Host "`n⚠️  Partial success: $successCount pipeline(s) rewired, $failureCount failed" -ForegroundColor Yellow
    Write-Host "`n📝 Next Steps:" -ForegroundColor Cyan
    Write-Host "   1. Review failures in the log file: $logFile" -ForegroundColor White
    Write-Host "   2. Fix issues with failed pipelines and retry if needed" -ForegroundColor White
    Write-Host "   3. For successful pipelines, proceed to:" -ForegroundColor White
    Write-Host "      - Run: .\7_integrate_boards.ps1 (integrate Azure Boards with GitHub)" -ForegroundColor White
    Write-Host "      - Run: .\8_disable_ado_repos.ps1 (optional - disable ADO repositories)" -ForegroundColor White
    Write-Host "   4. Update documentation with new GitHub repository URLs" -ForegroundColor White
    exit 0
} else {
    Write-Host "`n❌ Pipeline rewiring encountered failures - review output and retry" -ForegroundColor Red
    exit 1
}
