# 🚀 Azure DevOps to GitHub Enterprise Migration: Step-by-Step Workflow

In this guide, we’ll walk through how to migrate repositories from Azure DevOps Cloud to GitHub Enterprise Cloud using the GitHub CLI along with the ADO2GH extension. This extension provides a powerful set of commands that simplify and automate the end-to-end migration process.

we’ll focus specifically on repository migration using a hybrid integration approach. In this model, a service connection is established between Azure DevOps and GitHub Enterprise. Once a repository is migrated, any code changes or pull requests made in GitHub automatically trigger the corresponding pipelines in Azure DevOps. When those pipelines complete successfully, the build status is reported back to GitHub, where the pull request or workflow is marked as completed.

Behind the scenes, a set of PowerShell automation scripts use the ADO2GH CLI extension to perform the migration.

I'll walk you through a **phase-wise approach** to implementing this migration, highlighting each **sequential and dependent step** involved in the process.  

Later, we'll explore the accompanying **PowerShell scripts** that automate these steps end-to-end. These scripts can be leveraged to **streamline and scale** the migration process - making it efficient and repeatable for **hundreds of repositories** across an **Azure DevOps organization or project**.

> 📚 **Looking for the automation scripts?** Check out the **[detailed script documentation](./SCRIPTS.md)** for complete information on the modular PowerShell scripts that automate this entire workflow.

## 🧭 ADO to GHE Migration Flow

[ADO to GHE Migration Flowchart](!!)


## 📋Prerequisites

### 🔐 Install GitHub CLI and ADO2GH extension

#### ⚙️ Install GitHub CLI
Install the **GitHub CLI** on your local machine to interact with GitHub directly from the terminal.  
You can download it from the [GitHub CLI official site](https://cli.github.com/).

#### 🔌 Install ADO2GH Extension
Once the GitHub CLI is installed, add the **ADO2GH extension** to enable Azure DevOps to GitHub migration commands:

```bash
gh extension install github/gh-ado2gh
```
>🚀 **Tip**: Keep both the **GitHub CLI** and the **ADO2GH extension** updated to ensure compatibility with the latest migration features.

### 🗝️ Generate Personal Access Tokens (PATs)

Generate **Personal Access Tokens** for both **Azure DevOps** and **GitHub Enterprise** with the required access privileges.

#### 🧩 Azure DevOps PAT
- Grant **Full Access** permissions to enable complete control during repository migration.
- This token is used for authenticating with Azure DevOps services such as Repositories, Pipelines, and Service Connections.

#### 🧩 GitHub Enterprise PAT
Grant the following specific scopes to ensure proper access for migration and integration tasks:

- `repo` – Full control of private repositories  
- `workflow` – Manage and trigger GitHub Actions workflows  
- `admin:org` – Full control of organizations and teams  
- `user:read` – Read user profile data  
- `write:discussion` – Create and manage discussions

> 💡 **Note:** Store these tokens securely as environment variables before running any migration scripts.

```bash
$env:ADO_PAT = “YOUR-ADO-PAT"
$env:GH_PAT ="YOUR-GH-PAT"
```
## 🧭Planning Phase

Once you’ve completed the prerequisites, the next step is the **Planning Phase**.

#### 📊 Run ADO Inventory Report
Start by running the **Azure DevOps Inventory Report**, which provides a list of repositories along with their associated pipeline details.  This helps in identifying which repositories are in scope for migration.
```bash
gh ado2gh inventory-report --ado-org "your-ado-org"
```

This command generates several CSV files, including **`repos.csv`** with these columns:
- `org` - Azure DevOps organization
- `teamproject` - Team project name
- `repo` - Repository name
- `visibility` - Public/Private
- `last-push-date` - Last push timestamp
- `git-source` - Source control type (AdoGit)

**⚠️ Important:** Before migration, you must manually add two columns to `repos.csv`:
- **`ghorg`** - Target GitHub organization name
- **`ghrepo`** - Target GitHub repository name

**Example:**
```csv
org,teamproject,repo,visibility,last-push-date,git-source,ghorg,ghrepo
contosodevopstest,ContosoAir,ContosoAir,private,2023-07-27T18:53:54Z,AdoGit,MyGitHubOrg,contosoair-migrated
```

#### 📏 Categorize and Prioritize Repositories
After identifying the repositories, perform a **T-shirt sizing** exercise to classify them into: Example 
- 🟢 **Small** (repos size >200MB)
- 🟡 **Medium** (repo size 200MB-1GB)
- 🔴 **Large** (repo size >1GB)

Prioritize migrations based on:
- Expected **CI/CD process downtime**
- **Post-migration validation** effort required

## ⚠️ Pre-Migration Process Check

Before executing the repository migration, it’s **strongly recommended** to verify that there are no **in-progress pipelines** or **active pull requests** within the Azure DevOps team project.
Running a migration while these processes are active may lead to:
- Incomplete or inconsistent migration results  
- Potential **data loss** or missing repository information  

To avoid such issues:
- ✅ Check for any **in-progress pipelines** at the team project level  
- ✅ Review and close or merge any **active pull requests**  

> 💡 **Tip:** Always perform this validation step before locking and migrating repositories to ensure data consistency and a clean migration process.

```bash
# If you don't know the pipeline IDs, list all pipelines currently in progress:
az pipelines runs list --project $TeamProject --status inProgress --output table
```

```bash
# If you have pipeline IDs, get detailed runs for a specific pipeline:
az pipelines runs list --project $TeamProject --status inProgress --output table
```

## 🧪 Pilot Migration

It’s highly recommended to perform a **Proof of Concept (PoC)** or **Pilot Migration** with 2–3 representative repositories.  
This helps validate the end-to-end workflow, identify gaps, and fine-tune automation scripts before scaling to bulk migrations.


>🚀 **Note**:
> Before starting the migration, ensure Your **GitHub organization**, **teams**, and **user permissions** are properly configured. The **destination repository name** has been finalized but **not yet created** — it will be created automatically during the migration process.


```bash
# lock the ADO repository:
gh ado2gh lock-ado-repo --ado-org $ADO_ORG --ado-team-project $ADO_TEAM_PROJECT --ado-repo $ADO_REPO
```

```bash
# Migrate ADO repo to GitHub
gh ado2gh migrate-repo --ado-org <ORG> --ado-team-project <PROJECT> --ado-repo <REPO> --github-org <GITHUB_ORG> --github-repo <GITHUB_REPO>

```

## 🔍 Post-Migration Validation

After each migration, repository owners should conduct **post-migration validation**, either manually or using automated scripts.

Recommended validation checks include:
- 🔁 **Commit history**
- 🌿 **Branches**
- 🏷️ **Tags and releases**
- 📦 **Repository size**
- 🌐 **Default branch**
- ⚙️ **Build and pipeline validation** *(only after the rewiring step is complete)*


These checks are performed against the repositories that have been **migrated to GitHub Enterprise**.

```bash
# Get list of migrated repositories
gh repo view "$GITHUB_ORG/$repo" --json name,description,createdAt,diskUsage,defaultBranchRef | ConvertFrom-Json
```

```bash
# Check for branch protection
gh api "/repos/$GITHUB_ORG/$repo/branches/main/protection" --silent | Out-Null
```

> ⚠️ **Note:**  
> You might encounter this warning when running the command if you’re using a **non-Pro GitHub account** or if the **repository is private** instead of public.

```bash
# Check recent activity
gh api "/repos/$GITHUB_ORG/$repo/commits" | ConvertFrom-Json | Select-Object -First 1
```
You can now perform similar validation checks on the **Azure DevOps repositories** to verify and cross-check the migration results.

```bash
# Get repository details (similar to gh repo view):
az repos show --repository $repo --project $TeamProject --output json | ConvertFrom-Json
```

```bash
# Check branch protection on a branch (similar to GitHub branch protection check):
az repos policy list --project $TeamProject --repository-id $repoId | ConvertFrom-Json
```

```bash
# Check recent commit activity (similar to gh api /commits):
az repos pr list --repository $repo --project $TeamProject --top 1 --output json | ConvertFrom-Json
```
> ⚠️ **Note:**  
> The only rollback option is to **delete the GitHub repository** and **repeat the migration step**.

To perform this action, you need the `delete_repo` scope enabled for your GitHub token.

```bash
# Refresh authentication with delete_repo scope
gh auth refresh -h github.com -s delete_repo

# Delete the migrated repository
gh repo delete <ADO_ORG_NAME>/<GITHUB_REPO_NAME> --yes
```

## 🔄 Rewire: Connect Pipelines to Migrated Repositories

Now that the **migration** and **post-migration validation** are successfully completed, the next step is to verify the **service connection** between **GitHub Enterprise** and **Azure DevOps**.

Once the service endpoint is confirmed, proceed to **rewire the pipelines** — this means updating each pipeline’s **source repository** to point to the newly migrated repository in GitHub.

> ⚙️ This step is critical to ensure that your **CI/CD processes** continue seamlessly in the **hybrid DevOps model**, maintaining workflow continuity without any disruptions.

```bash
# List all service connections in a specified Azure DevOps project
az devops service-endpoint list --org https://dev.azure.com/<ADO_ORG_NAME> --project <ADO_PROJECT_NAME> --query "[?name=='<SERVICE_CONNECTION_NAME>'].id" -o tsv
```

```bash
# Rewire the pipeline
gh ado2gh rewire-pipeline --ado-org "<ADO_ORG_NAME>" --ado-team-project "<ADO_PROJECT_NAME>" --ado-pipeline "<ADO_PIPELINE_NAME>" --github-org "<GITHUB_ORG_NAME>" --github-repo "<GITHUB_REPO_NAME>" --service-connection-id "<SERVICE_CONNECTION_ID>"
```
## 🔄 After Post Rewiring Pipeline Validation 

After all Azure DevOps pipelines have been **rewired** to point to their new **GitHub repositories**, perform a validation to ensure end-to-end functionality.

1. **Trigger the pipelines** by creating **code commits** or **pull requests** in GitHub.  
2. Verify that these GitHub activities **automatically trigger** the corresponding **Azure DevOps pipelines**.  
3. Confirm that, upon successful pipeline completion in ADO, the **GitHub workflow or pull request status** is updated to reflect a **successful build**.

📘 **Recommended Reading**

For a detailed walkthrough, review my comprehensive article - 
**[GitHub + Azure DevOps: A Hybrid CI/CD Approach](https://www.linkedin.com/pulse/github-azure-devops-hybrid-cicd-approach-vamsi-cherukuri-nppfe/?trackingId=2onWvK9gaGstJ3kTcSkXnw%3D%3D)**  
which provides in-depth guidance on creating service connections and validating Azure DevOps pipelines in a hybrid GitHub–ADO environment.

## 🔒 Disable Azure DevOps Repositories

Now that the **rewiring** and **pipeline testing** are complete, proceed to the next phase - **Disabling the Azure DevOps repositories**.  
This step ensures that no further changes or activities occur on the ADO repository.

```bash
# avoid any activities on the ADO repo disable it by command:
gh ado2gh disable-ado-repo --ado-org $ADO_ORG --ado-team-project $ADO_TEAM_PROJECT --ado-repo $ADO_REPO
```

---

## 🤖 Automation Scripts

For **bulk migrations** and to **streamline the entire process**, we've created a comprehensive set of **PowerShell automation scripts** that implement all the steps outlined in this workflow.

📚 **[View Detailed Script Documentation →](./SCRIPTS.md)**

These modular scripts provide:
- ✅ **Automated execution** of all migration phases
- ✅ **Parallel repository migration** (4 concurrent jobs)
- ✅ **Pre-migration validation** (active processes check)
- ✅ **Post-migration validation** and reporting
- ✅ **Pipeline rewiring automation**
- ✅ **Mannequin user management**
- ✅ **GitHub Actions workflow** for CI/CD integration

**Quick Start:**
```powershell
# Navigate to scripts directory
cd scripts

# Step 0: Generate inventory
.\0_Inventory.ps1

# Step 1: Check for active processes (optional)
.\1_check_active_process.ps1

# Step 2: Migrate repositories (parallel execution)
.\2_migrate_repo.ps1 -RepoCSV "repos.csv"

# Continue with remaining steps...
```

For complete script documentation, parameters, usage examples, and troubleshooting, refer to the **[SCRIPTS.md](./SCRIPTS.md)** file.

---

## Contributing

Pull requests are welcome. For major changes, please open an issue first
to discuss what you would like to change.

Please make sure to update tests as appropriate.

## License

[MIT](https://choosealicense.com/licenses/mit/)
