#This script allows you to install a program on multiple remote computers from a central point, making software deployment faster and more efficient. 
#The target computers can be identified in two ways: through a text file containing the list of PCs, or by querying Active Directory directly.
#Finally, it writes a log file to check the outcome of each installation.
param(
    [Parameter(Mandatory)]
    [string]$InstallerPath,                 # Enter the path to the MSI or EXE file (local or network share)

    [string]$SearchBase,                    # Enter the OU to get computers from (e.g. OU=PCs,DC=domain,DC=local)
    [string]$ComputerListFile,              # Alternatively: .txt file with the PC names

    [string]$SilentArgs = "/qn /norestart", # MSI: "/qn /norestart" - EXE: varies by program
    [string]$DisplayName,                   # Name as it appears in "Apps & features" (avoids reinstallations)

    [string]$LogPath = ".\install_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $InstallerPath)) { throw "Installer non trovato: $InstallerPath" }

# --- Computer list ---------------------------------------------------------
if ($ComputerListFile) {
    $computers = Get-Content $ComputerListFile | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }
}
elseif ($SearchBase) {
    Import-Module ActiveDirectory
    $computers = Get-ADComputer -Filter 'Enabled -eq $true' -SearchBase $SearchBase |
                 Select-Object -ExpandProperty Name
}
else {
    throw "Specifica -SearchBase oppure -ComputerListFile."
}

$fileName = Split-Path $InstallerPath -Leaf
$isMsi    = $fileName -match '\.msi$'
$results  = @()

foreach ($pc in $computers) {
    Write-Host "[$pc] Avvio..." -ForegroundColor Cyan
    $status = "Errore"; $detail = ""

    try {
        if (-not (Test-Connection $pc -Count 1 -Quiet)) { throw "PC non raggiungibile (spento/offline)" }

        $session = New-PSSession -ComputerName $pc

        # Già installato?
        if ($DisplayName) {
            $already = Invoke-Command -Session $session -ArgumentList $DisplayName -ScriptBlock {
                param($name)
                $keys = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
                [bool](Get-ItemProperty $keys -ErrorAction SilentlyContinue |
                       Where-Object { $_.DisplayName -like "*$name*" })
            }
            if ($already) {
                $status = "Già installato"
                Remove-PSSession $session
                $results += [pscustomobject]@{ Computer = $pc; Stato = $status; Dettaglio = $detail }
                Write-Host "[$pc] $status" -ForegroundColor Yellow
                continue
            }
        }

        # Copy the installer to the client (avoids the "double hop" problem with network shares)
        $remoteDir = Invoke-Command -Session $session -ScriptBlock { $env:TEMP }
        $remoteFile = Join-Path $remoteDir $fileName
        Copy-Item -Path $InstallerPath -Destination $remoteFile -ToSession $session -Force

        # Run silent install
        $exitCode = Invoke-Command -Session $session -ArgumentList $remoteFile, $isMsi, $SilentArgs -ScriptBlock {
            param($file, $msi, $args)
            if ($msi) {
                $p = Start-Process msiexec.exe -ArgumentList "/i `"$file`" $args" -Wait -PassThru
            } else {
                $p = Start-Process $file -ArgumentList $args -Wait -PassThru
            }
            Remove-Item $file -Force -ErrorAction SilentlyContinue
            $p.ExitCode
        }

        # 0 = success, 3010 = success but reboot required
        switch ($exitCode) {
            0       { $status = "Installato" }
            3010    { $status = "Installato (riavvio richiesto)" }
            default { $status = "Errore"; $detail = "Exit code $exitCode" }
        }

        Remove-PSSession $session
    }
    catch {
        $status = "Errore"
        $detail = $_.Exception.Message
        if ($session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
    }

    $color = if ($status -like "Installato*") { "Green" } else { "Red" }
    Write-Host "[$pc] $status $detail" -ForegroundColor $color
    $results += [pscustomobject]@{ Computer = $pc; Stato = $status; Dettaglio = $detail }
}

$results | Export-Csv -Path $LogPath -NoTypeInformation -Encoding UTF8
Write-Host "`nLog salvato in: $LogPath" -ForegroundColor Cyan
$results | Group-Object Stato | Select-Object Name, Count | Format-Table -AutoSize
