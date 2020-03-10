# Foxcraft Deployment Wizard
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
        EnableFTP   = $ConfigFile.Settings.ServerSettings.EnableFTP
        FTPLib      = $ConfigFile.Settings.ServerSettings.FTPLib
        FTPAddress  = $ConfigFile.Settings.ServerSettings.FTPAddress
        FTPPort     = $ConfigFile.Settings.ServerSettings.FTPPort
        FTPUsername = $ConfigFile.Settings.ServerSettings.FTPUsername
        FTPPassword = $ConfigFile.Settings.ServerSettings.FTPPassword
        FTPHome     = $ConfigFile.Settings.ServerSettings.FTPHome 
    }
    Write-Output "[INFO] Script is configured. Thanks for reading the docs!"
}
else {
    Write-Warning "[WARN] Settings file not found. Create a settings file first!";
    Write-Warning "[WARN] Learn how to use this script here: https://github.com/andrewjmetzger/foxcraft.mtz.gr/wiki/Foxcraft-Deployment-Wizard:-Automatic-Deployment-with-PowerShell";
}


if ( Test-Path -Path "$PWD\.git" ) {
    $gitRemote = (git config --get remote.origin.url)
    $latestTag = (git describe --abbrev=0)
    $latestTagDate = (git log -1 --format=%aI $latestTag).Split("T")[0]
    Write-Output "[INFO] Latest version tag is $latestTag, committed on $latestTagDate."
    $nextTag = (Read-Host -Prompt "Enter the next tag (ex: v1.2.3)")
    Write-Output "[INFO] Next tag will be $nextTag."
}
else {
    Write-Error "[ERR] Directory '$PWD' is not linked to a valid repository."
    break
}


### Update resource pack
Push-Location "$PWD\static\resourcepacks\FoxcraftCustom"

# Update pack.mcmeta
$filePath = "pack.mcmeta"
$file = (Get-Content "$filePath")
if ($file -Match "v\d+\.\d+\.\d+") {
    $file -Replace "v\d+\.\d+\.\d+", "$nextTag" | Set-Content -Path "$filePath"
    Write-Output "[INFO] Finished modifying '$filePath'."
}
else {
    Write-Error "[ERR] Could not modify '$filePath'."
}

if ( Test-Path "$PWD\FoxcraftCustom*.zip" ) {
    Write-Information "[INFO] Found existing ZIP, will remove."
    Remove-Item "$PWD\FoxcraftCustom*.zip" 
}


Pop-Location


Write-Output "[INFO] Compressing resource pack to ZIP, please wait..."
Start-Process $PWD/deploy/7za.exe -ArgumentList "a -tzip $PWD/static/resourcepacks/FoxcraftCustom/FoxcraftCustom-$nextTag.zip $PWD/static/resourcepacks/FoxcraftCustom/*" -NoNewWindow -Wait
Write-Output "[INFO] Finished compressing resource pack."


### TODO: Update launcher


### Update site
$filePath = "$PWD\_config.yml"
$file = (Get-Content -Path "$filePath")
if ($file -Match "modpackVersion") {
    $file -replace "modpackVersion.+", "modpackVersion: '$nextTag'" | Set-Content -Path "$filePath"
    Write-Output "[INFO] Finished modifying '$filePath'."
}
else {
    Write-Error "[ERR] Could not modify '$filePath'."
}


### Update git
Write-Output "[INFO] Connecting to remote '$gitRemote'"
git add -A
git commit -m "FDW: Automatic deploy for $nextTag"
git push origin master
git tag -a $nextTag -m "FDW: Automatic tag for $nextTag"
git push origin $nextTag
Write-Output "[INFO] Successfully tagged commit with '$nextTag'"


#==============================================================================#
#  FTP OPERATIONS BEGIN HERE - REQUIRES A CONFIGFURED FTP SERVER AND SETTINGS  #
#==============================================================================#

### Update server.properties
if ( $Config.EnableFTP ) {

    Write-Output "[INFO] FTP is enabled, let's go!"

    if ( $Config.FTPAddress -eq '' ) {
        Write-Error "[ERR] FTP is enabled, but not configured!"
    }
    elseif ( $Config.FTPUsername -eq '' ) {
        Write-Error "[ERR] FTP is enabled, but not configured!"
    }
    else {
        # FTP is properly configured 
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
            $path = $Config.FTPHome + "/server.properties"
            $session.GetFiles($path, "$PWD\*").Check()
        }
        finally {
            $session.Dispose()
        }

        # Modify files
        $filePath = "server.properties"
        $file = (Get-Content -Path "$filePath")
        $descriptor = $gitRemote.Split("/")[3]
        $descriptor += "/"
        $descriptor += $gitRemote.Split("/")[4]
        $descriptor = $descriptor -replace '.git', ''
        $raw = "https\://raw.githubusercontent.com/$descriptor/$nextTag"
        $raw += '/static/resourcepacks/FoxcraftCustom/FoxcraftCustom.zip'
        Write-Output "New pack URL is '$raw'"

        if ($file -Match "resource-pack") {
            $file -Replace "resource-pack=.+", "resource-pack=$raw" | Set-Content -Path "$filePath"
            Write-Output "[INFO] Finished modifying '$filePath'."
        }
        else {
            Write-Error "[ERR] Could not modify '$filePath'."
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
            $session.Dispose()
            Pop-Location
            Remove-Item -Path "$PWD\tmp\" -Recurse
        }
    }
    # End FTP operations
}

Write-Output "[INFO] Deployment complete! Check the console above for more information."
