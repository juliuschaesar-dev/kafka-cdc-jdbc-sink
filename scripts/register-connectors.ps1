# Registers the Debezium source and ClickHouse JDBC sink connectors against a
# running Kafka Connect worker (exposed on localhost:8083 by docker-compose).

$ErrorActionPreference = "Stop"

$ConnectUrl = "http://localhost:8083"
$ConnectorsDir = Join-Path $PSScriptRoot "..\connectors"

Write-Host "Waiting for Kafka Connect at $ConnectUrl ..."
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    try {
        Invoke-RestMethod -Uri "$ConnectUrl/connectors" -Method Get | Out-Null
        $ready = $true
        break
    } catch {
        Start-Sleep -Seconds 2
    }
}
if (-not $ready) {
    Write-Error "Kafka Connect did not become available in time."
    exit 1
}
Write-Host "Kafka Connect is up."

# Source is registered before sink so the sink's topics already exist or are about to be created.
foreach ($dir in @("source", "sink")) {
    Get-ChildItem -Path (Join-Path $ConnectorsDir $dir) -Filter "*.json" | ForEach-Object {
        $name = $_.BaseName
        $body = Get-Content -Raw -Path $_.FullName

        try {
            Invoke-RestMethod -Uri "$ConnectUrl/connectors/$name" -Method Delete | Out-Null
        } catch {
            # 404 = no previous instance; anything else is a real failure.
            if ($_.Exception.Response.StatusCode.value__ -ne 404) { throw }
        }

        Write-Host "Registering connector '$name' from $dir/$($_.Name) ..."
        try {
            Invoke-RestMethod -Uri "$ConnectUrl/connectors" -Method Post -ContentType "application/json" -Body $body | Out-Null
        } catch {
            Write-Error "Failed to register ${name}: $($_.ErrorDetails.Message)"
            exit 1
        }
        Write-Host "  -> OK"
    }
}

Write-Host "All connectors registered."
