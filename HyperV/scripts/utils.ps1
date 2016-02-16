function ExecRetry($command, $maxRetryCount = 10, $retryInterval=2)
{
    $currErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $retryCount = 0
    while ($true)
    {
        try 
        {
            & $command
            break
        }
        catch [System.Exception]
        {
            $retryCount++
            if ($retryCount -ge $maxRetryCount)
            {
                $ErrorActionPreference = $currErrorActionPreference
                throw
            }
            else
            {
                Write-Error $_.Exception
                Start-Sleep $retryInterval
            }
        }
    }

    $ErrorActionPreference = $currErrorActionPreference
}

function GitClonePull($path, $url, $branch="master")
{
    if (!(Test-Path -path $path))
    {
        ExecRetry {
            git clone $url $path
            if ($LastExitCode) { throw "git clone failed" }
        }
        (git checkout $branch) -Or (git checkout master)
        if ($LastExitCode) { throw "git checkout failed" }
    }else{
        pushd $path
        try
        {
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue "$path\*"
            ExecRetry {
                git clone $url $path
                if ($LastExitCode) { throw "git clone failed" }
            }
            ExecRetry {
                (git checkout $branch) -Or (git checkout master)
                if ($LastExitCode) { throw "git checkout failed" }
            }

            Get-ChildItem . -Include *.pyc -Recurse | foreach ($_) {Remove-Item $_.fullname}

            git reset --hard
            if ($LastExitCode) { throw "git reset failed" }

            git clean -f -d
            if ($LastExitCode) { throw "git clean failed" }

            ExecRetry {
                git pull
                if ($LastExitCode) { throw "git pull failed" }
            }
        }
        finally
        {
            popd
        }
    }
}

function Exec-PipInstall{
    <#
    .SYNOPSIS
    This function uses pip to install the specified Python packages.
    WARNING: This function does not support all pip install parameters. The only 
    parameters that are supported are: -U (Upgrade), --use-wheel (usewheel), --no-index
    (-noindex), --find-links (-findlinks), --pre (-pre).
    .PARAMETER packages
    The package(s) to install. If there is more than 1, the packages must
    be separated by comma.
    .PARAMETER usewheel
    If this parameter is present, the --use-wheel option will be added to pip install.
    .PARAMETER noindex
    If this parameter is present, the --no-index option will be added to pip install.
    .PARAMETER findlinks
    This parameter specifies the URL to be used for --find-links option of pip install.
    .PARAMETER Upgrade
    If this parameter is present, the specified package(s) will be upgraded.
    .PARAMETER pre
    If this parameter is present, the --pre option will be added to pip install. 
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [string[]]$packages,
        [parameter(Mandatory=$false)]
        [switch]$usewheel,
        [parameter(Mandatory=$false)]
        [switch]$noindex,
        [parameter(Mandatory=$false)]
        [string]$findlinks=$null,
        [parameter(Mandatory=$false)]
        [switch]$Upgrade,
        [parameter(Mandatory=$false)]
        [switch]$pre,
        [parameter(Mandatory=$false)]
        [switch]$req
    )
    PROCESS {
        foreach($package in $packages){
            $my_command = @("pip install")
            if ($Upgrade.IsPresent){
                $my_command += @("-U ")
            }
            if ($pre.IsPresent){
                $my_command += @("--pre")
            }
            if ($usewheel.IsPresent){
                $my_command += @("--use-wheel")
            }
            if ($noindex.IsPresent){
                $my_command += @("--no-index")
            }
            if ($findlinks -ne $null -and $findlinks.Length -ne 0){
                $my_command += @("--findlinks=$findlinks")
            }
            if ($req.IsPresent){
                $my_command += @("-r")
            }
            $my_command +=  @($package)
            $my_command = $my_command -join " "
            ExecRetry {
                Invoke-Expression $my_command
                if ($LastExitCode) { 
                    Throw "pip failed to install $package" 
                }
            }
        } 
    }
}

function Exec-EasyInstall{
    <#
    .SYNOPSIS
    This function uses the easy_install Python module to install Python packages.
    WARNING: This function does not support all easy_install parameters. The only 
    parameters that are supported are: -f (URL).
    .PARAMETER packages
    The package(s) you want to install. If there is more than 1, the packages must
    be separated by comma.
    .PARAMETER URL
    The URL to be specified at easy_install --find-links.
    #>
    [CmdletBinding()]
    param (        
        [parameter(Mandatory=$true)]
        [string]$packages,
        [parameter(Mandatory=$false)]
        [string]$URL=$null,
        [parameter(Mandatory=$false)]
        [switch]$Upgrade      
)
    PROCESS {
        foreach($package in $packages)
        {   
            $my_command = @("easy_install")
            if ($URL -ne $null -and $URL.Length -ne 0){
                $my_command += @("-f",$URL)
            }
            if ($Upgrade.IsPresent){
                $my_command += @("-U ")
            }
            $my_command += @($package)
            $my_command = $my_command -join " "
            ExecRetry {
                Invoke-Expression $my_command
                if ($LastExitCode) { 
                    Throw "pip easy_install failed to install $package" 
                }
            }
        } 
    }
}