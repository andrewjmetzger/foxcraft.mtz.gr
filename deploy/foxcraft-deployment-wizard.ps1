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
    $latestTag = (git describe --abbrev=0)
    $latestTagDate = (git log -1 --format=%aI $latestTag).Split("T")[0]
    Write-Output "[INFO] Latest version tag is $latestTag, committed on $latestTagDate."
    
    $latestVersion = [version]((git describe --abbrev=0) -Replace "v", "")
    $nextVersion = ([string]$latestVersion.Major) + "." + ([string]$latestVersion.Minor) + "." + ([string]([int]$latestVersion.Build + 1))
    $nextTag = "v$nextVersion"
    Write-Output "[INFO] Next tag will be $nextTag."
}
else {
    Write-Error "[ERR] Directory '$PWD' is not linked to a Github repository."
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
    $file -Replace "v\d+\.\d+\.\d+", "$nextTag" | Set-Content -Path "$PWD\pack.mcmeta"
}

Remove-Item -Path "$PWD\pack.mcmeta.old"
Write-Output "[INFO] Compressing resource pack to ZIP, please wait..."

$zip = "$PWD\FoxcraftCustom.zip"
$p = Get-ChildItem -Path $PWD
Compress-Archive -Path $p -DestinationPath $zip -CompressionLevel Fastest -Force
Write-Output "[INFO] Finished compressing resource pack."

Pop-Location

# Update git
#foo

<#
# FTP Stuff
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

        # Session.FileTransferred event handler
        function FileTransferred {
            param($e)
 
            if ($e.Error -eq $Null) {
                Write-Host "Upload of $($e.FileName) succeeded"
            }
            else {
                Write-Host "Upload of $($e.FileName) failed: $($e.Error)"
            }
 
            if ($e.Chmod -ne $Null) {
                if ($e.Chmod.Error -eq $Null) {
                    Write-Host "Permissions of $($e.Chmod.FileName) set to $($e.Chmod.FilePermissions)"
                }
                else {
                    Write-Host "Setting permissions of $($e.Chmod.FileName) failed: $($e.Chmod.Error)"
                }
 
            }
            else {
                Write-Host "Permissions of $($e.Destination) kept with their defaults"
            }
 
            if ($e.Touch -ne $Null) {
                if ($e.Touch.Error -eq $Null) {
                    Write-Host "Timestamp of $($e.Touch.FileName) set to $($e.Touch.LastWriteTime)"
                }
                else {
                    Write-Host "Setting timestamp of $($e.Touch.FileName) failed: $($e.Touch.Error)"
                }
 
            }
            else {
                # This should never happen during "local to remote" synchronization
                Write-Host "Timestamp of $($e.Destination) kept with its default (current time)"
            }
        }
 

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
            # Continuously report synchronization progress 
            $session.add_FileTransferred( { FileTransferred($_) } )
 
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
            Write-Output "[INFO] Uploading modified files, please wait..."
            $session.PutFiles("$PWD\*", "/*").Check()
        }
        finally {
            Write-Output "[INFO] Cleaning up, please wait..."
            $session.Dispose()
            Pop-Location
            Remove-Item -Path "$PWD\tmp\" -Recurse
        }

        # Synchronize server-side mods

 
        try {
            $session = New-Object WinSCP.Session
            try {
                # Continuously report synchronization progress 
                $session.add_FileTransferred( { FileTransferred($_) } )
 
                # Connect
                $session.Open($sessionOptions)
 
                # Synchronize files
                Write-Output "[INFO] Synchronizing server-side mods, please wait..."
                $synchronizationResult = $session.SynchronizeDirectories(
                    [WinSCP.SynchronizationMode]::Remote, "$PWD/static/mods/server", "/mods", $False)
 
                # Throw on any error
                $synchronizationResult.Check()
            }
            finally {
                # Disconnect, clean up
                $session.Dispose()
            }
 
            exit 0
        }
        catch {
            Write-Host "Error: $($_.Exception.Message)"
            exit 1
        }

        # End FTP operations
    }
}
#>


Write-Output "[INFO] Deployment complete! Check the console above for more information."