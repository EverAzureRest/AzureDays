<# 
 
.SYNOPSIS 
This Powershell script simplify the installation/configuration of BGInfo local/remote. 
 
.DESCRIPTION 
This script need to be run with administrator rights. 
 
To install on remote computer enable: "Enable-PSRemoting -Force" on remote maschine.  
Target_Host need to be a member of a domain 
Read more here: https://technet.microsoft.com/da-dk/library/hh849694(v=wps.630).aspx 
 
.EXAMPLE 
BGInfo Examples 
Install Local with default config: 
PSBgInfo.ps1  
 
Install with custom config: 
Local install:                    PSBgInfo.ps1 -DeploymentType "Install" 
Remote install single Host:        PSBgInfo.ps1 -DeploymentType "Install" -ComputerName "Target_Host" 
 
Uninstall 
Local uninstall:                PSBgInfo.ps1 -DeploymentType "Uninstall" 
Remote uninstall single Host:    PSBgInfo.ps1 -DeploymentType "Uninstall" -ComputerName "Target_Host" 
 
Remote multiple host 
Remote install multiple Host:    PSBgInfo.ps1 -DeploymentType "Install" -File "c:\Host_list.txt" 
Remote uninstall multiple Host:    PSBgInfo.ps1 -DeploymentType "Uninstall" -File "c:\Host_list.txt" 
 
Host_list.txt contains hostname on seperate lines like 
Target_Host01 
Target_Host02 
Target_Host03 
 
.NOTES 
# Powershell - Created with Windows PowerShell ISE 
# NAME:  PSBgInfo.ps1 
# AUTHOR: Long Truong 
# DATE  : 06-03-2016 
# Version : 1.0.0.1   
# Requirement: 
# Windows Management Framework 4.0 https://www.microsoft.com/en-us/download/details.aspx?id=40855 
 
.LINK 
https://gallery.technet.microsoft.com/scriptcenter/PSBginfo-BgInfo-powershell-199249c7 
 
#> 
 
[CmdletBinding(DefaultParametersetName = 'Set 1')] 
Param ( 
    [ValidateSet('Install', 'Uninstall')] 
    [string] 
    $DeploymentType = 'Install', 
     
    [Parameter(ParameterSetName = 'Set 1')] 
    [string] 
    $ComputerName = $env:ComputerName, 
     
    [Parameter(ParameterSetName = 'Set 2')] 
    [ValidateScript({ Test-Path $_ })] 
    [string] 
    $File, 
     
    [string] 
    $Config = 'default', 
     
    [PSCredential] 
    $Credential, 
     
    [string] 
    $UserName = 'devlab\admin' 
) 
$start_time = Get-Date 
 
# Retrieve the active parameter set 
$ParSet = $PSCmdlet.ParameterSetName 
 
#region Utility Functions 
function Write-Message 
{ 
    param ( 
        [string] 
        $sMessage 
    ) 
    Write-Verbose "$(Get-Date -Format 'dd-MM-yy HH:mm:ss') # $sMessage" 
} 
 
Function Install-BGInfo 
{ 
    [CmdletBinding()] 
    Param ( 
        [string] 
        $ComputerName, 
         
        [PSCredential] 
        $Credential, 
         
        [string] 
        $Config 
    ) 
     
    # Prepare Paths 
    $url = 'https://download.sysinternals.com/files/BGInfo.zip' 
    $instfile = "$env:temp\BGInfo.zip" 
    $instfolder = "\\$ComputerName\c$\BGinfo" 
    $exec_bginfo = "$instfolder\Bginfo.exe" 
     
     
    Write-Message "DeploymentType: $DeploymentType" 
    Write-Message "Config: $Config" 
     
    #region Ensure BGInfo.exe is in place 
    if (Test-Path -Path $instfolder\Bginfo.exe) 
    { 
        Write-Message "$instfolder\Bginfo.exe exist" 
    } 
    Else 
    { 
        if (Test-Path -Path $instfile) 
        { 
            Write-Message "$env:temp\BGInfo.zip exist" 
        } 
        Else 
        { 
            Write-Message "Downloading BGInfo.zip to $env:temp" 
            Import-Module BitsTransfer 
            Start-BitsTransfer -Source $url -Destination $instfile 
        } 
        Write-Message "Extracting BGInfo to: $instfolder" 
        try { Add-Type -AssemblyName 'System.IO.Compression.FileSystem' -ErrorAction Stop } 
        catch { } 
        [System.IO.Compression.ZipFile]::ExtractToDirectory($instfile, $instfolder) 
    } 
    #endregion Ensure BGInfo.exe is in place 
     
    #region Transfer BGI Config file 
    if (Test-Path -Path $PSScriptRoot\$config.bgi) 
    { 
        Write-Message "Copy config: '$config.bgi' to '$instfolder\' folder" 
        Copy-Item -Path $PSScriptRoot\$config.bgi -Destination $instfolder\$config.bgi 
    } 
    Else 
    { 
        Write-Message "Config: '$config.bgi' does not exist in '$PSScriptRoot\' check folder!!!" 
        $config = 'default' 
         
        if (Test-Path -Path $PSScriptRoot\$config.bgi) 
        { 
            Write-Message "Using default config: 'default.bgi'" 
            Write-Message "Copy config: '$config.bgi' to '$instfolder\' folder" 
            Copy-Item -Path $PSScriptRoot\$config.bgi -Destination $instfolder\default.bgi 
        } 
        Else 
        { 
            Write-Message "Config: '$config.bgi' does not exist in '$PSScriptRoot\' check folder!!!" 
        } 
    } 
    #endregion Transfer BGI Config file 
     
    #region Add BGInfo to Autorun 
    If ($ComputerName -ne $env:ComputerName) 
    { 
        Write-Message 'Remote - Creating regedit Key for Startup - HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\BgInfo' 
        Invoke-Command -Credential $credential -ComputerName $ComputerName -ScriptBlock { 
            param ($instfolder, 
                 
                $Config) 
            New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name BgInfo -Value """$instfolder\Bginfo.exe"" $instfolder\$config.bgi /timer:00 /accepteula /silent" -PropertyType 'String' -Force 
        } -ArgumentList $instfolder, $Config 
    } 
    Else 
    { 
        Write-Message 'Local - Creating regedit Key for Startup under:' 
        Write-Message 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\BgInfo' 
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name BgInfo -Value """$instfolder\Bginfo.exe"" $instfolder\$config.bgi /timer:00 /accepteula /silent" -PropertyType 'String' -Force 
        Write-Message "Executing: $instfolder\Bginfo.exe $instfolder\$config.bgi /timer:00 /accepteula /silent" 
        & $instfolder\Bginfo.exe "$instfolder\$config.bgi" /timer:00 /accepteula /silent 
    } 
    #endregion Add BGInfo to Autorun 
} 
 
Function Uninstall-BGInfo 
{ 
    [CmdletBinding()] 
    Param ( 
        [string] 
        $ComputerName, 
         
        [PSCredential] 
        $Credential, 
         
        [string] 
        $DeploymentType, 
         
        [string] 
        $Config 
    ) 
     
    # Prepare Paths 
    $url = 'https://download.sysinternals.com/files/BGInfo.zip' 
    $instfile = "$env:temp\BGInfo.zip" 
    $instfolder = "\\$ComputerName\c$\BGinfo" 
    $exec_bginfo = "$instfolder\Bginfo.exe" 
     
    Write-Message "DeploymentType: $DeploymentType" 
    Write-Message "Config: $Config" 
     
    #region remote Execution 
    If ($ComputerName -ne $env:ComputerName) 
    { 
        Write-Message 'Remote - Cleanup desktop at next reboot' 
        Copy-Item -Path $PSScriptRoot\restore.bgi -Destination $instfolder\restore.bgi 
        Invoke-Command -Credential $credential -ComputerName $ComputerName -ScriptBlock { 
            param ($instfolder, 
                 
                $Config) 
            remove-itemproperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name BgInfo 
            New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name BgInfo -Value """$instfolder\Bginfo.exe"" $instfolder\restore.bgi /timer:00 /accepteula /silent" -PropertyType 'String' -Force 
        } -ArgumentList $instfolder, $Config 
    } 
    #endregion remote Execution 
     
    #region Local Execution 
    Else 
    { 
        Write-Message 'Local - Removing BgInfo' 
        Write-Message 'Restoring wallpaper' 
        Write-Message "Executing: $instfolder\Bginfo.exe $PSScriptRoot\restore.bgi /timer:00 /accepteula /silent" 
        & $instfolder\Bginfo.exe "$PSScriptRoot\restore.bgi" /timer:00 /accepteula /silent 
        Write-Message 'Removing regedit Key for Startup:' 
        Write-Message 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\BgInfo' 
        remove-itemproperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name BgInfo 
        Start-Sleep -m 2000 
        Write-Message "Removing folder: $instfolder" 
        Remove-Item "$instfolder" -recurse 
    } 
    #endregion Local Execution 
} 
#endregion Utility Functions 
 
switch ($ParSet) 
{ 
    'Set 1' 
    { 
        If ($ComputerName -ne $env:ComputerName) 
        { 
            if ($PSBoundParameters['Credential']) { $UseCred = $Credential } 
            else { $UseCred = Get-Credential -Credential $UserName } 
             
            Write-Message "ComputerName: $ComputerName" 
            switch ($DeploymentType) 
            { 
                'Install' { Install-BGInfo -ComputerName $ComputerName -Credential $UseCred -Config $Config } 
                'Uninstall' { Uninstall-BGInfo -ComputerName $ComputerName -Credential $UseCred -Config $Config } 
            } 
            Write-Message "Executed on remote host: $ComputerName" 
        } 
        else 
        { 
            Write-Message "ComputerName: $ComputerName" 
            switch ($DeploymentType) 
            { 
                'Install' { Install-BGInfo -ComputerName $ComputerName -Config $Config } 
                'Uninstall' { Uninstall-BGInfo -ComputerName $ComputerName -Config $Config } 
            } 
            Write-Message "Executed on localhost: $env:computername" 
        } 
    } 
    'Set 2' 
    { 
        if ($PSBoundParameters['Credential']) { $UseCred = $Credential } 
        else { $UseCred = Get-Credential -Credential $UserName } 
         
        Write-output "$File is a file" 
         
        $computers = Get-Content -Path $File 
        foreach ($Computer in $computers) 
        { 
            switch ($DeploymentType) 
            { 
                'Install' { Install-BGInfo -ComputerName $ComputerName -Credential $UseCred -Config $Config } 
                'Uninstall' { Uninstall-BGInfo -ComputerName $ComputerName -Credential $UseCred -Config $Config } 
            } 
            Write-Message "Executed on remote host: $Computer" 
        } 
    } 
} 
Write-Message "Powershell script execution time taken: $((Get-Date).Subtract($start_time).TotalSeconds) second(s)"