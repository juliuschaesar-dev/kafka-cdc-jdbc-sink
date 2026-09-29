# Continuously inserts one random order every N seconds, so the CDC pipeline
# (Debezium -> Kafka -> ClickHouse) has a steady stream of changes to show off.
# customer_id is picked at random from existing rows in `customers`.

$ErrorActionPreference = "Stop"

$PostgresContainer = "postgres"

# Credentials come from .env (repo root)
$envFile = Join-Path $PSScriptRoot "..\.env"
if (-not (Test-Path $envFile)) { throw ".env not found at $envFile" }
$envVars = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^#=\s]+)\s*=\s*(.*)$') { $envVars[$Matches[1]] = $Matches[2].Trim() }
}
$PostgresUser = $envVars["POSTGRES_USER"]
$PostgresDb = $envVars["POSTGRES_DB"]
if (-not $PostgresUser -or -not $PostgresDb) { throw "POSTGRES_USER and POSTGRES_DB must be set in .env" }

$IntervalSeconds = 10

Write-Host "Generating one random order every ${IntervalSeconds}s into ${PostgresDb}.orders (Ctrl+C to stop) ..."

$sql = @"
INSERT INTO public.orders (customer_id, amount, status, created_at, updated_at)
SELECT (SELECT id FROM public.customers ORDER BY random() LIMIT 1),
       round((random() * 490 + 10)::numeric, 2),
       (ARRAY['pending','shipped','completed','cancelled'])[floor(random() * 4 + 1)],
       now(),
       now()
RETURNING id, customer_id, amount, status, created_at;
"@

while ($true) {
    docker exec $PostgresContainer psql -U $PostgresUser -d $PostgresDb -c $sql
    Start-Sleep -Seconds $IntervalSeconds
}
