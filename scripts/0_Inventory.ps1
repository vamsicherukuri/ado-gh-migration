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

# ADO2GH Step 0: Generate Inventory Report
#
# Description:
#   This script generates an inventory report of Azure DevOps repositories at the
#   organization level using the gh ado2gh CLI extension. This report is used to
#   identify repositories for migration planning.
#
# Prerequisites:
#   - ADO_PAT environment variable set with full access scope
#   - migration-config.json exists with proper configuration
#
# Order of operations:
# [1/3] Validate ADO PAT tokens
# [2/3] Load configuration from migration-config.json
#       - Reads adoOrganization from config.scripts.inventory.adoOrg
# [3/3] Generate inventory report using gh ado2gh inventory-report
#       - Creates CSV files in current directory
# [4/4] Add GitHub organization columns to repos.csv
#       - Adds ghorg and ghrepo columns
#
# Usage:
#   .\0_Inventory.ps1
#   .\0_Inventory.ps1 -ConfigPath "custom-config.json"
#
# Output Files:
#   - orgs.csv (list of ADO organizations)
#   - team-projects.csv (list of team projects)
#   - repos.csv (list of repositories - used by subsequent scripts)
#   - pipelines.csv (list of pipelines)

param(
    [string]$ConfigPath = "migration-config.json",
    [string]$AdoOrg = ""  # Optional override
)

# Import helper module
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$scriptPath\MigrationHelpers.psm1" -Force -ErrorAction Stop

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Step 0: Generate Inventory Report" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# 1. Validate PAT tokens
Write-Host "[1/4] Validating PAT tokens..." -ForegroundColor Yellow
if (!(Test-RequiredPATs)) { exit 1 }

# 2. Load configuration
Write-Host "`n[2/4] Loading configuration..." -ForegroundColor Yellow
$config = Get-MigrationConfig -ConfigPath $ConfigPath
if (!$config) { exit 1 }

$AdoOrg = $config.scripts.inventory.adoOrg
Write-Host "ADO Organization: $AdoOrg" -ForegroundColor Gray

# 3. Generate inventory report
Write-Host "`n[3/4] Generating inventory report..." -ForegroundColor Yellow
Write-Host "   This may take several minutes depending on organization size..." -ForegroundColor Gray

gh ado2gh inventory-report --ado-org $AdoOrg

# Check command result
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n❌ Inventory report generation failed" -ForegroundColor Red
    exit $LASTEXITCODE
}


Write-Host "`n✅ Inventory report generated successfully!" -ForegroundColor Green

# Add GitHub organization columns to repos.csv
Write-Host "`n[4/4] Adding GitHub organization columns to repos.csv..." -ForegroundColor Yellow

try {
    Add-GitHubColumnsToReposCSV -ConfigPath $ConfigPath
}
catch {
    Write-Host "❌ Failed to add GitHub columns: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Inventory Report Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`n📊 Output Files:" -ForegroundColor Cyan
Write-Host "   - orgs.csv (ADO organizations)" -ForegroundColor White
Write-Host "   - team-projects.csv (Team projects)" -ForegroundColor White
Write-Host "   - repos.csv (Repositories - used by migration scripts)" -ForegroundColor White
Write-Host "   - pipelines.csv (Pipelines)" -ForegroundColor White

Write-Host "`n📋 NEXT STEPS:" -ForegroundColor Cyan
Write-Host "   1. Review the generated CSV files" -ForegroundColor White
Write-Host "   2. Run: .\1_check_active_process.ps1" -ForegroundColor White

exit 0