# =============================================================================
# Camiva - one-shot payment setup (Fapshi sandbox)
# =============================================================================
#
#   .\tool\setup_payments.ps1
#
# It does, in order:
#   1. checks supabase/functions/.env is actually filled in
#   2. verifies the credentials against the Fapshi SANDBOX before deploying
#   3. links the Supabase project
#   4. uploads the secrets
#   5. deploys the four payment functions
#
# It stops at the first failure, so nothing is half-deployed. Safe to re-run.
# Nothing here touches live: the .env ships with FAPSHI_ENV=sandbox and the
# credential check is hard-wired to the sandbox host.
# =============================================================================

$ErrorActionPreference = 'Stop'

$ProjectRef = 'ixobcntcqhjhmamtntop'
$Root       = Split-Path -Parent $PSScriptRoot
$EnvFile    = Join-Path $Root 'supabase\functions\.env'
$WebhookUrl = "https://$ProjectRef.supabase.co/functions/v1/fapshi-webhook"

function Step($n, $text) { Write-Host "`n[$n] $text" -ForegroundColor Cyan }
function Ok($text)       { Write-Host "    OK  $text" -ForegroundColor Green }
function Die($text)      { Write-Host "`nSTOPPED: $text" -ForegroundColor Red; exit 1 }

# ---- 1. Is the .env filled in? ----------------------------------------------
Step 1 'Checking supabase/functions/.env'

if (-not (Test-Path $EnvFile)) {
  Die "$EnvFile does not exist. Copy .env.example to .env and paste your sandbox values."
}

$values = @{}
foreach ($line in Get-Content $EnvFile) {
  if ($line -match '^\s*#') { continue }
  if ($line -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$') {
    $values[$Matches[1]] = $Matches[2].Trim()
  }
}

foreach ($key in @('FAPSHI_COLLECTION_API_USER','FAPSHI_COLLECTION_API_KEY')) {
  $v = $values[$key]
  if ([string]::IsNullOrWhiteSpace($v) -or $v -like 'PASTE_*') {
    Die "$key is not set in supabase/functions/.env - paste your sandbox value and run this again."
  }
}

if ($values['FAPSHI_ENV'] -eq 'live') {
  Die 'FAPSHI_ENV is set to live. This script is for sandbox only; switching to live is a deliberate, separate decision.'
}
Ok 'sandbox credentials present'

# The shared webhook secret is optional in sandbox (the dashboard may not offer
# one) but mandatory before going live, because on live it is the only thing
# authenticating that endpoint.
$secret = $values['FAPSHI_WEBHOOK_SECRET']
if ([string]::IsNullOrWhiteSpace($secret) -or $secret -like 'PASTE_*') {
  Write-Host '    NOTE  no webhook secret set - fine for sandbox.' -ForegroundColor Yellow
  Write-Host '          Every webhook is still re-checked with Fapshi before it' -ForegroundColor Yellow
  Write-Host '          changes anything. Required before going live.' -ForegroundColor Yellow
} else {
  Ok 'webhook secret present'
}

# ---- 2. Do the credentials actually work? -----------------------------------
Step 2 'Verifying the credentials against the Fapshi sandbox'

& dart run (Join-Path $Root 'tool\fapshi_sandbox_check.dart') `
    "--apiuser=$($values['FAPSHI_COLLECTION_API_USER'])" `
    "--apikey=$($values['FAPSHI_COLLECTION_API_KEY'])"
if ($LASTEXITCODE -eq 3) {
  Die 'Could not REACH Fapshi (see above). Your credentials were never sent, so this is a network problem, not a credential problem. Check VPN/proxy or try another network, then re-run.'
}
if ($LASTEXITCODE -ne 0) {
  Die 'Fapshi rejected those credentials. Nothing was deployed. Re-copy apiuser/apikey from the sandbox dashboard.'
}
Ok 'Fapshi sandbox accepted the credentials'

# ---- 3. Find a Supabase CLI that actually runs -------------------------------
# npx is unreliable here ("could not determine executable to run" when its cache
# is in a bad state), so an installed CLI is preferred and npx is only the
# fallback. Whatever is found is verified with --version before being used.
Step 3 'Locating the Supabase CLI'

$Cli = $null
$installed = Get-Command supabase -ErrorAction SilentlyContinue
if ($installed) {
  & supabase --version *> $null
  if ($LASTEXITCODE -eq 0) { $Cli = @('supabase') }
}
if (-not $Cli) {
  & npx --yes supabase@latest --version *> $null
  if ($LASTEXITCODE -eq 0) { $Cli = @('npx','--yes','supabase@latest') }
}
if (-not $Cli) {
  Write-Host ''
  Write-Host 'No working Supabase CLI found. Install it once with either:' -ForegroundColor Yellow
  Write-Host '    scoop install supabase' -ForegroundColor Yellow
  Write-Host '  or download supabase_windows_amd64.exe from' -ForegroundColor Yellow
  Write-Host '    https://github.com/supabase/cli/releases' -ForegroundColor Yellow
  Write-Host '  and put it on your PATH as supabase.exe' -ForegroundColor Yellow
  Die 'Supabase CLI unavailable. Nothing was deployed.'
}
Ok "using: $($Cli -join ' ')"

function Supabase { & $Cli[0] @($Cli[1..($Cli.Count-1)] + $args) }

# ---- 4. Signed in? -----------------------------------------------------------
Step 4 'Checking you are signed in to Supabase'
Supabase projects list *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host ''
  Write-Host "Run this once, then re-run this script:" -ForegroundColor Yellow
  Write-Host "    $($Cli -join ' ') login" -ForegroundColor Yellow
  Die 'Not signed in to Supabase.'
}
Ok 'signed in'

# ---- 5-7. Link, secrets, deploy ---------------------------------------------
Step 5 "Linking Supabase project $ProjectRef"
Supabase link --project-ref $ProjectRef
if ($LASTEXITCODE -ne 0) { Die 'supabase link failed - see the error above.' }
Ok 'linked'

Step 6 'Uploading secrets (they stay server-side)'
Supabase secrets set --env-file $EnvFile
if ($LASTEXITCODE -ne 0) { Die 'Could not upload secrets.' }
Ok 'secrets uploaded'

Step 7 'Deploying the payment functions'
Supabase functions deploy payments-create payments-verify withdrawals-request fapshi-webhook
if ($LASTEXITCODE -ne 0) { Die 'Deploy failed. Fix the error above and re-run - this script is safe to repeat.' }
Ok 'payments-create, payments-verify, withdrawals-request, fapshi-webhook deployed'

# ---- Done -------------------------------------------------------------------
Write-Host "`nDone." -ForegroundColor Green
Write-Host ''
Write-Host 'Last step, on the Fapshi dashboard (this cannot be done from here):'
Write-Host ''
Write-Host "  Webhook URL     $WebhookUrl" -ForegroundColor Yellow
Write-Host '  Webhook secret  the same value as FAPSHI_WEBHOOK_SECRET in your .env'
Write-Host ''
Write-Host 'Until that URL is saved on the dashboard, payments will sit on'
Write-Host '"Payment processing..." - the app re-checks with Fapshi as a fallback,'
Write-Host 'but the webhook is what settles them promptly.'
Write-Host ''
Write-Host 'Then open the app and pay for a child''s tutoring. No real money moves'
Write-Host 'in sandbox.'
