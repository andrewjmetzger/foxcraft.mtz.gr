# Foxcraft Updater
# DO NOT MODIFY THIS SCRIPT 
# To configure your deployment, create a configuration file. 
# Documentation: https://github.com/andrewjmetzger/foxcraft.mtz.gr/wiki/Foxcraft-Deployment-Wizard:-Automatic-Deployment-with-PowerShell


# Default $PWD to the script's parent directory
Set-Location (Split-Path -Parent $PSScriptRoot)
Write-Output "Current location is $PWD"

# Load external configuration, if present
if ( Test-Path -Path "$PWD\deploy\FDWSettings.xml" ) {
    [xml]$ConfigFile = Get-Content -Path "$PWD\deploy\FDWSettings.xml"
    $Config = @{
        GithubRemote = $ConfigFile.Settings.GithubSettings.Remote
        EnableFTP    = $ConfigFile.Settings.ServerSettings.EnableFTP
        FTPLib       = $ConfigFile.Settings.ServerSettings.FTPLib
        FTPAddress   = $ConfigFile.Settings.ServerSettings.FTPAddress
        FTPPort      = $ConfigFile.Settings.ServerSettings.FTPPort
        FTPUsername  = $ConfigFile.Settings.ServerSettings.FTPUsername
        FTPPassword  = $ConfigFile.Settings.ServerSettings.FTPPassword
    }
    Write-Output "[INFO] Script is configured. Thanks for reading the docs!"
}
else {
    Write-Output "[ERR] Settings file not found. Create a settings file first!";
    Write-Output "Learn how to use the FDW here: https://github.com/andrewjmetzger/foxcraft.mtz.gr/wiki/Foxcraft-Deployment-Wizard:-Automatic-Deployment-with-PowerShell";
}



if ( Test-Path -Path "$PWD\.git" ) {
    $latestTag = (git describe)
    Write-Output "[INFO] Latest version tag is $latestTag"
}
else {
    Write-Error "[ERR] Directory '$PWD' is not a Github repository."
    break
}

# Resource pack
Push-Location "$PWD\static\resourcepacks\FoxcraftCustom"

if ( Test-Path "$PWD\FoxcraftCustom.zip" ) {
    Write-Information "[INFO] Found existing ZIP, will remove."
    Remove-Item "$PWD\FoxcraftCustom.zip" 
}

# Create a copy of the old mcmeta to revert if needed
Copy-Item -Path "$PWD\pack.mcmeta" -Destination "$PWD\pack.mcmeta.old" -Force
Write-Output "[INFO] Successfully backed up 'pack.mcmeta' to 'pack.mcmeta.old'"

# Replace placeholder with the latest tagged release number
$file = (Get-Content "$PWD\pack.mcmeta")
IF ($file -Match "v\d+\.\d+\.\d+") {
    $file -Replace "v\d+\.\d+\.\d+", "$latestTag" | Set-Content -Path "$PWD\pack.mcmeta"
}

Remove-Item -Path "$PWD\pack.mcmeta.old"
Write-Output "[INFO] Compressing resource pack to ZIP, please wait..."

$zip = "$PWD\FoxcraftCustom.zip"
$p = Get-ChildItem -Path $PWD
Compress-Archive -Path $p -DestinationPath $zip -CompressionLevel Fastest -Force
Write-Output "[INFO] Finished compressing resource pack."

Pop-Location
Write-Output "Current location is $PWD"

if ( $Config.EnableFTP ) {

    Write-Output "[INFO] FTP is enabled, let's go!"

    if ( $Config.FTPAddress -eq '' ) {
        Write-Error "[ERR] FTP is enabled, but not configured!"
    }
    elseif ( $Config.FTPUsername -eq '' ) {
        Write-Error "[ERR] FTP is enabled, but not configured!"
    }
    else {
        # Begin FTP operations
        Remove-Item "$PWD\tmp\" -Recurse -Force -ErrorAction Ignore
        New-Item "$PWD\tmp" -ItemType Directory -Force | Out-Null
        Push-Location "$PWD\tmp\"
        Write-Output "[INFO] Created temp directory. New location is '$PWD'."

        # Load WinSCP .NET assembly
        Add-Type -Path $Config.FTPLib

        # Set up session options
        $sessionOptions = New-Object WinSCP.SessionOptions -Property @{
            Protocol   = [WinSCP.Protocol]::Ftp
            HostName   = $Config.FTPAddress
            PortNumber = $Config.FTPPort
            UserName   = $Config.FTPUsername
            Password   = $Config.FTPPassword
        }

        $session = New-Object WinSCP.Session

        try {
            # Connect
            $session.Open($sessionOptions)

            # Download files
            Write-Output "[INFO] Downloading 'server.properties'"
            $session.GetFiles("/server.properties", "$PWD\*").Check()
        }
        finally {
            $session.Dispose()
        }

        # Modify files
        $file = (Get-Content -Path "server.properties")
        $descriptor = $Config.GithubRemote.Split("/")[3]
        $descriptor += "/"
        $descriptor += $Config.GithubRemote.Split("/")[4]
        $descriptor = $descriptor -replace '.git', ''
        $raw = "https\://raw.githubusercontent.com/$descriptor/$latestTag"
        $raw += '/static/resourcepacks/FoxcraftCustom/FoxcraftCustom.zip'
        Write-Output "New pack URL is '$raw'"

        if ($file -Match "resource-pack") {
            $file -Replace "resource-pack=.+", "resource-pack=$raw" | Set-Content -Path "server.properties"
            Write-Output "[INFO] Finished modifying 'server.properties'."
        }
        else {
            Write-Error "[ERR] Could not modify 'server.properties'."
        }

        # Upload
        $session = New-Object WinSCP.Session

        try {
            # Connect
            $session.Open($sessionOptions)

            # Transfer files
            Write-Output "[INFO] Uploading 'server.properties' to '$Config.FTPAddress/' as '$Config.FTPUsername'"
            $session.PutFiles("$PWD\*", "/*").Check()
        }
        finally {
            Write-Output "[INFO] Cleaning up, please wait..."
            $session.Dispose()
            Pop-Location
            Remove-Item -Path "$PWD\tmp\" -Recurse
        }
        # End FTP operations
    }
}