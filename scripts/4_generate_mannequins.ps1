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

# ADO2GH Step 4: Generate Mannequins
# 
# Description:
# This script generates a CSV file of mannequin users (placeholder accounts)
# that were created during the migration process. This CSV is used in the
# next step to reclaim and map these mannequins to actual GitHub users.
#
# Prerequisites:
# - GH_PAT environment variable set (GitHub Personal Access Token)
# - Repositories must be migrated first (run 2_migrate_repo.ps1)
# - migration-config.json configuration file
#
# Order of operations:
# [1/3] Validate GitHub PAT token
# [2/3] Load configuration from migration-config.json
# [3/3] Generate mannequin CSV using gh ado2gh CLI
#
# Usage:
# .\4_generate_mannequins.ps1
# .\4_generate_mannequins.ps1 [-ConfigPath "migration-config.json"]
# .\4_generate_mannequins.ps1 [-OutputCSV "custom-mannequins.csv"]
#
# Output Files:
# - mannequins.csv (list of placeholder users requiring GitHub mapping)

param(
    [string]$ConfigPath = "migration-config.json",
    [string]$OutputCSV = ""  # Optional override
)

# Import helper module
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$scriptPath\MigrationHelpers.psm1" -Force -ErrorAction Stop

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Step 4: Generate Mannequins" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# 1. CHECK PAT TOKEN
Write-Host "[1/3] Checking GitHub PAT token..." -ForegroundColor Yellow
if (!(Test-RequiredPATs -ADORequired $false -GitHubRequired $true)) { exit 1 }

# 2. LOAD CONFIGURATION
Write-Host "`n[2/3] Loading configuration..." -ForegroundColor Yellow
$config = Get-MigrationConfig -ConfigPath $ConfigPath
if (!$config) { exit 1 }

$GITHUB_ORG = $config.githubOrganization

# Use parameter override if provided, otherwise use config
if ([string]::IsNullOrEmpty($OutputCSV)) {
    $OUTPUT_FILE = $config.scripts.generateMannequins.outputCSV
} else {
    $OUTPUT_FILE = $OutputCSV
}

Write-Host "`n   GitHub Organization: $GITHUB_ORG" -ForegroundColor Gray
Write-Host "   Output File: $OUTPUT_FILE" -ForegroundColor Gray

# 3. GENERATE MANNEQUIN CSV
Write-Host "`n[3/3] Generating mannequin CSV..." -ForegroundColor Yellow
Write-Host "   This may take a few moments depending on the number of users..." -ForegroundColor Gray

try {
    # Generate mannequin CSV using gh ado2gh CLI
    gh ado2gh generate-mannequin-csv --github-org $GITHUB_ORG --output $OUTPUT_FILE
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✅ Mannequin CSV generated successfully!" -ForegroundColor Green
        
        # Check if file was created and display stats
        if (Test-Path $OUTPUT_FILE) {
            $csvContent = Import-Csv -Path $OUTPUT_FILE
            $mannequinCount = $csvContent.Count
            
            Write-Host "`n📊 Mannequin Statistics:" -ForegroundColor Cyan
            Write-Host "   Total mannequins found: $mannequinCount" -ForegroundColor White
            Write-Host "   Output file: $OUTPUT_FILE" -ForegroundColor White
            
            if ($mannequinCount -eq 0) {
                Write-Host "`n⚠️  No mannequins found - all users may already exist in GitHub" -ForegroundColor Yellow
            } else {
                Write-Host "`n💡 Next Step: Review the mannequins CSV file and update it with target GitHub users" -ForegroundColor Blue
            }
        } else {
            Write-Host "`n⚠️  CSV file was not created. This may indicate no mannequins were found." -ForegroundColor Yellow
        }
        
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  Generation Complete" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        
        Write-Host "`n📋 Next Steps:" -ForegroundColor Cyan
        Write-Host "   1. Review and update the mannequins CSV file: $OUTPUT_FILE" -ForegroundColor White
        Write-Host "   2. Run: .\5_reclaim_mannequins.ps1" -ForegroundColor White
        
        exit 0
    } else {
        Write-Host "`n❌ Failed to generate mannequin CSV" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "`n❌ Error during mannequin generation: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
