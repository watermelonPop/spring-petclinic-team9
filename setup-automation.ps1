param(
    [string]$JobName = "petclinic-ci",
    [string]$PollSchedule = "H/2 * * * *",
    [string]$RepoUrl = "",
    [string]$Branch = "",
    [string]$SonarToken = $env:SONAR_TOKEN,
    [switch]$TriggerBuild
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Escape-Xml {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    return [System.Security.SecurityElement]::Escape($Text)
}

function Get-BasicAuthHeader {
    param([string]$Username, [string]$Password)
    $bytes = [System.Text.Encoding]::ASCII.GetBytes("${Username}:${Password}")
    $encoded = [Convert]::ToBase64String($bytes)
    return "Basic $encoded"
}

function Wait-ForJenkins {
    param([string]$Url, [int]$TimeoutSeconds = 300)

    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
        try {
            $resp = Invoke-WebRequest -Uri "$Url/login" -UseBasicParsing -TimeoutSec 5
            if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 500) {
                return
            }
        }
        catch {
            Start-Sleep -Seconds 3
        }
    }

    throw "Jenkins did not become ready within $TimeoutSeconds seconds."
}

function Get-JenkinsCrumb {
    param(
        [string]$JenkinsUrl,
        [hashtable]$Headers
    )

    try {
        return Invoke-RestMethod -Method Get -Uri "$JenkinsUrl/crumbIssuer/api/json" -Headers $Headers -TimeoutSec 15
    }
    catch {
        return $null
    }
}

function Invoke-Jenkins {
    param(
        [string]$JenkinsUrl,
        [string]$Path,
        [string]$Method = "GET",
        [hashtable]$BaseHeaders,
        [string]$Body = "",
        [string]$ContentType = "application/x-www-form-urlencoded"
    )

    $headers = @{}
    foreach ($k in $BaseHeaders.Keys) { $headers[$k] = $BaseHeaders[$k] }

    $crumb = Get-JenkinsCrumb -JenkinsUrl $JenkinsUrl -Headers $headers
    if ($null -ne $crumb -and $crumb.crumbRequestField -and $crumb.crumb) {
        $headers[$crumb.crumbRequestField] = $crumb.crumb
    }

    $uri = "$JenkinsUrl$Path"

    if ($Method -in @("POST", "PUT")) {
        return Invoke-WebRequest -Method $Method -Uri $uri -Headers $headers -Body $Body -ContentType $ContentType -UseBasicParsing -TimeoutSec 60
    }

    return Invoke-WebRequest -Method $Method -Uri $uri -Headers $headers -UseBasicParsing -TimeoutSec 60
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "docker is required." }
if (-not (Get-Command vagrant -ErrorAction SilentlyContinue)) { throw "vagrant is required." }
if (-not (Test-Path ".\petclinic-prod-vm\Vagrantfile")) { throw "petclinic-prod-vm/Vagrantfile not found from current directory." }
if (-not (Test-Path ".\docker-compose.devops.yml")) { throw "docker-compose.devops.yml not found from current directory." }

if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
    $RepoUrl = (git remote get-url origin).Trim()
}
if ([string]::IsNullOrWhiteSpace($Branch)) {
    $Branch = (git rev-parse --abbrev-ref HEAD).Trim()
}

$jenkinsUrl = "http://localhost:8088"

Write-Step "Starting/ensuring production VM is running"
Push-Location .\petclinic-prod-vm
vagrant up
Pop-Location

Write-Step "Starting DevOps services (Jenkins, SonarQube, Prometheus, Grafana, Postgres)"
docker compose -f docker-compose.devops.yml up -d --build

Write-Step "Waiting for Jenkins to become reachable"
Wait-ForJenkins -Url $jenkinsUrl -TimeoutSeconds 360

Write-Step "Getting Jenkins bootstrap admin password"
$jenkinsPassword = (docker exec petclinic-jenkins cat /var/jenkins_home/secrets/initialAdminPassword).Trim()
if ([string]::IsNullOrWhiteSpace($jenkinsPassword)) {
    throw "Could not read Jenkins initialAdminPassword from container."
}

$authHeader = Get-BasicAuthHeader -Username "admin" -Password $jenkinsPassword
$baseHeaders = @{ Authorization = $authHeader }

Write-Step "Ensuring Jenkins SSH key exists"
docker exec petclinic-jenkins bash -lc "mkdir -p /var/jenkins_home/.ssh && chmod 700 /var/jenkins_home/.ssh && [ -f /var/jenkins_home/.ssh/id_rsa ] || ssh-keygen -t rsa -b 4096 -N '' -f /var/jenkins_home/.ssh/id_rsa"
$pubKey = (docker exec petclinic-jenkins cat /var/jenkins_home/.ssh/id_rsa.pub).Trim()
if ([string]::IsNullOrWhiteSpace($pubKey)) {
    throw "Failed to read Jenkins SSH public key."
}

Write-Step "Authorizing Jenkins SSH key on production VM deploy user"
$escapedPubKey = $pubKey.Replace("'", "''")
Push-Location .\petclinic-prod-vm
vagrant ssh -c "sudo mkdir -p /home/deploy/.ssh; sudo touch /home/deploy/.ssh/authorized_keys; sudo grep -qxF '$escapedPubKey' /home/deploy/.ssh/authorized_keys || echo '$escapedPubKey' | sudo tee -a /home/deploy/.ssh/authorized_keys >/dev/null; sudo chown -R deploy:deploy /home/deploy/.ssh; sudo chmod 700 /home/deploy/.ssh; sudo chmod 600 /home/deploy/.ssh/authorized_keys"
Pop-Location

if (-not [string]::IsNullOrWhiteSpace($SonarToken)) {
    Write-Step "Creating/updating Jenkins secret text credential: sonar-token"
    $groovy = @"
import jenkins.model.Jenkins
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.common.StandardCredentials
import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl
import hudson.util.Secret

def provider = Jenkins.instance.getExtensionList(SystemCredentialsProvider.class)[0]
def store = provider.getStore()
def domain = Domain.global()
def id = "sonar-token"
def existing = provider.getCredentials().find { it.id == id }
if (existing != null) {
    store.removeCredentials(domain, existing)
}
def cred = new StringCredentialsImpl(CredentialsScope.GLOBAL, id, "Sonar token managed by setup-automation.ps1", Secret.fromString("$SonarToken"))
store.addCredentials(domain, cred)
println("sonar-token credential configured")
"@
    $body = "script=$([System.Uri]::EscapeDataString($groovy))"
    Invoke-Jenkins -JenkinsUrl $jenkinsUrl -Path "/scriptText" -Method "POST" -BaseHeaders $baseHeaders -Body $body | Out-Null
}
else {
    Write-Host "SONAR_TOKEN not provided. Skipping sonar-token credential setup." -ForegroundColor Yellow
}

Write-Step "Creating or updating Jenkins pipeline job"
$escapedRepo = Escape-Xml $RepoUrl
$escapedBranchSpec = Escape-Xml "*/$Branch"
$escapedPoll = Escape-Xml $PollSchedule

$jobXml = @"
<flow-definition plugin="workflow-job">
  <actions/>
  <description>Automated pipeline for Spring Petclinic (created by setup-automation.ps1)</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>$escapedRepo</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>$escapedBranchSpec</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class="empty-list"/>
      <extensions/>
    </scm>
    <scriptPath>Jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <triggers>
    <hudson.triggers.SCMTrigger>
      <spec>$escapedPoll</spec>
      <ignorePostCommitHooks>false</ignorePostCommitHooks>
    </hudson.triggers.SCMTrigger>
  </triggers>
  <disabled>false</disabled>
</flow-definition>
"@

$jobNameEscaped = [System.Uri]::EscapeDataString($JobName)
$jobExists = $false
try {
    Invoke-Jenkins -JenkinsUrl $jenkinsUrl -Path "/job/$jobNameEscaped/api/json" -Method "GET" -BaseHeaders $baseHeaders | Out-Null
    $jobExists = $true
}
catch {
    $jobExists = $false
}

if ($jobExists) {
    Invoke-Jenkins -JenkinsUrl $jenkinsUrl -Path "/job/$jobNameEscaped/config.xml" -Method "POST" -BaseHeaders $baseHeaders -Body $jobXml -ContentType "application/xml" | Out-Null
    Write-Host "Updated existing job: $JobName"
}
else {
    Invoke-Jenkins -JenkinsUrl $jenkinsUrl -Path "/createItem?name=$jobNameEscaped" -Method "POST" -BaseHeaders $baseHeaders -Body $jobXml -ContentType "application/xml" | Out-Null
    Write-Host "Created job: $JobName"
}

if ($TriggerBuild.IsPresent) {
    Write-Step "Triggering initial Jenkins build"
    Invoke-Jenkins -JenkinsUrl $jenkinsUrl -Path "/job/$jobNameEscaped/build?delay=0sec" -Method "POST" -BaseHeaders $baseHeaders | Out-Null
}

Write-Step "Setup complete"
Write-Host "Jenkins URL: $jenkinsUrl"
Write-Host "Job: $JobName"
Write-Host "Repo: $RepoUrl"
Write-Host "Branch: $Branch"
Write-Host "Poll schedule: $PollSchedule"
Write-Host "Run this after code pushes if needed: .\setup-automation.ps1"
