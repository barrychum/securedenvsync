# Paths
$secEnvPath = "C:\Users\$env:USERNAME\AppData\Local\sec_env\sec_env"
$privateKeyPath = "C:\Users\$env:USERNAME\.ssh\rsa_private_key.pem"
$publicKeyPath = "C:\Users\$env:USERNAME\.ssh\rsa_public_key.pem"
$rcloneRemote = "remote:backup"

# Encrypt a value using RSA public key
function Encrypt-Value {
    param (
        [string]$value
    )
    $encryptedValue = echo -n "$value" | openssl pkeyutl -encrypt -pubin -inkey $publicKeyPath | base64
    return $encryptedValue
}

# Decrypt a value using RSA private key
function Decrypt-Value {
    param (
        [string]$encryptedValue
    )
    $decryptedValue = echo "$encryptedValue" | base64 --decode | openssl pkeyutl -decrypt -inkey $privateKeyPath
    return $decryptedValue
}

# Add or replace a key-value pair in sec_env
function Add-KeyValue {
    param (
        [string]$key,
        [string]$value
    )
    $encryptedValue = Encrypt-Value -value $value

    # Create sec_env file if it doesn't exist
    if (-not (Test-Path $secEnvPath)) {
        New-Item -ItemType File -Path $secEnvPath
    }

    # Check if key exists and replace its value
    $content = Get-Content $secEnvPath
    $keyExists = $false
    $newContent = @()
    foreach ($line in $content) {
        if ($line -match "^$key=") {
            $newContent += "$key=$encryptedValue"
            $keyExists = $true
        } else {
            $newContent += $line
        }
    }
    if (-not $keyExists) {
        $newContent += "$key=$encryptedValue"
    }
    $newContent | Set-Content $secEnvPath
}

# Retrieve a value from sec_env
function Get-Value {
    param (
        [string]$key
    )
    $line = Select-String -Path $secEnvPath -Pattern "^$key=" -SimpleMatch
    if ($line) {
        $encryptedValue = $line -replace "^$key=", ""
        $decryptedValue = Decrypt-Value -encryptedValue $encryptedValue
        return $decryptedValue
    } else {
        Write-Error "Key not found"
    }
}

# Sync sec_env from remote storage
function Sync-SecEnvDown {
    $result = rclone copy $rcloneRemote\sec_env (Split-Path -Parent $secEnvPath)
    if ($LASTEXITCODE -eq 0) {
        Write-Output "sec_env downloaded successfully."
    } else {
        Write-Error "Failed to download sec_env."
        exit 1
    }
}

# Async sync sec_env to remote storage
function Sync-SecEnvUp {
    Start-Job -ScriptBlock {
        rclone copy $using:secEnvPath $using:rcloneRemote
        if ($LASTEXITCODE -eq 0) {
            Write-Output "sec_env uploaded successfully."
        } else {
            Write-Error "Failed to upload sec_env."
            exit 1
        }
    } | Wait-Job
}

# Example usage
Sync-SecEnvDown
Add-KeyValue -key "API_KEY" -value "my-secret-api-key"
Sync-SecEnvUp

$value = Get-Value -key "API_KEY"
Write-Output "Decrypted value: $value"
