# Attaches files to a Gitea release, replacing any existing asset with the same
# name (the equivalent of `gh release upload --clobber`, which Gitea lacks).
# Windows counterpart of upload-release-asset.sh, for the Windows runner.
#
# Usage: upload-release-asset.ps1 FILE [FILE...]
# Environment: GITEA_TOKEN, GITEA_SERVER_URL, GITEA_REPOSITORY, RELEASE_ID
#
# Uses curl.exe (bundled with Windows 10 and later) because Windows
# PowerShell 5.1's Invoke-RestMethod cannot send multipart forms.
param(
  [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
  [string[]] $Files
)
$ErrorActionPreference = 'Stop'

foreach ($var in 'GITEA_TOKEN', 'GITEA_SERVER_URL', 'GITEA_REPOSITORY', 'RELEASE_ID') {
  if (-not [Environment]::GetEnvironmentVariable($var)) { throw "$var is not set" }
}

$api = "$($env:GITEA_SERVER_URL.TrimEnd('/'))/api/v1/repos/$env:GITEA_REPOSITORY/releases/$env:RELEASE_ID/assets"
$auth = "Authorization: token $env:GITEA_TOKEN"

function Invoke-Curl([string[]] $CurlArgs) {
  $out = & curl.exe -fsS @CurlArgs
  if ($LASTEXITCODE -ne 0) { throw "curl failed ($LASTEXITCODE): $($CurlArgs -join ' ')" }
  return $out
}

foreach ($file in $Files) {
  if (-not (Test-Path $file -PathType Leaf)) { throw "No such file: $file" }
  $name = Split-Path $file -Leaf

  # A re-run of the job must replace what the earlier run uploaded.
  $existing = (Invoke-Curl @('-H', $auth, $api)) -join "`n" | ConvertFrom-Json
  foreach ($asset in @($existing)) {
    if ($asset -and $asset.name -eq $name) {
      Invoke-Curl @('-X', 'DELETE', '-H', $auth, "$api/$($asset.id)") | Out-Null
      Write-Host "Replaced existing $name"
    }
  }

  Invoke-Curl @('-X', 'POST', '-H', $auth, '-F', "attachment=@$file", "$api`?name=$([uri]::EscapeDataString($name))") | Out-Null
  Write-Host "Uploaded $name"
}
