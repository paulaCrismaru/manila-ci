Param(
    [Parameter(Mandatory=$true)][string]$devstackIP,
    [string]$branchName='master'
)

$openstackDir = "C:\OpenStack"
$baseDir = "$openstackDir\manila-ci\HyperV"
$scriptdir = "$baseDir\scripts"
$configDir = "C:\OpenStack\etc"
$templateDir = "$baseDir\templates"
$buildDir = "c:\OpenStack\build\openstack"
$binDir = "$openstackDir\bin"
$novaTemplate = "$templateDir\nova.conf"
$neutronTemplate = "$templateDir\neutron_hyperv_agent.conf"
$hostname = hostname
$rabbitUser = "stackrabbit"
$pythonDir = "C:\Python27"
$pythonArchive = "python27new.tar.gz"
$pythonTar = "python27new.tar"
$pythonExec = "$pythonDir\python.exe"

$openstackLogs="$openstackDir\Log"
$remoteConfigs="\\"+$devstackIP+"\openstack\config"

. "$scriptdir\utils.ps1"

$hasNova = Test-Path $buildDir\nova
$hasNeutron = Test-Path $buildDir\neutron
$hasNeutronTemplate = Test-Path $neutronTemplate
$hasNovaTemplate = Test-Path $novaTemplate
$hasConfigDir = Test-Path $configDir
$hasBinDir = Test-Path $binDir
$hasMkisoFs = Test-Path $binDir\mkisofs.exe
$hasQemuImg = Test-Path $binDir\qemu-img.exe

$pip_conf_content = @"
[global]
index-url = http://dl.openstack.tld:8080/cloudbase/CI/+simple/
[install]
trusted-host = dl.openstack.tld
"@

$ErrorActionPreference = "Stop"


if ($hasBinDir -eq $false){
    mkdir $binDir
}

if (($hasMkisoFs -eq $false) -or ($hasQemuImg -eq $false)){
    Invoke-WebRequest -Uri "http://dl.openstack.tld/openstack_bin.zip" -OutFile "$bindir\openstack_bin.zip"
    if (Test-Path "C:\Program Files\7-Zip\7z.exe"){
        pushd $bindir
        & "C:\Program Files\7-Zip\7z.exe" x -y "$bindir\openstack_bin.zip"
        Remove-Item -Force "$bindir\openstack_bin.zip"
        popd
    } else {
        Throw "Required binary files (mkisofs, qemuimg etc.)  are missing"
    }
}

if ($hasNovaTemplate -eq $false){
    Throw "Nova template not found"
}

if ($hasNeutronTemplate -eq $false){
    Throw "Neutron template not found"
}

git config --global user.email "hyper-v_ci@microsoft.com"
git config --global user.name "Hyper-V CI"


ExecRetry {
        GitClonePull "$buildDir\nova" "https://github.com/openstack/nova.git" $branchName
}
ExecRetry {
    GitClonePull "$buildDir\neutron" "https://github.com/openstack/neutron.git" $branchName
}
ExecRetry {
    GitClonePull "$buildDir\networking-hyperv" "https://github.com/openstack/networking-hyperv.git" "master"
}
ExecRetry {
    GitClonePull "$buildDir\compute-hyperv" "https://github.com/openstack/compute-hyperv.git" $branchName
}

$hasLogDir = Test-Path $openstackLogs
if ($hasLogDir -eq $false){
    mkdir $openstackLogs
}

$hasConfigDir = Test-Path $remoteConfigs\$hostname
if ($hasConfigDir -eq $false){
    mkdir $remoteConfigs\$hostname
}

pushd C:\
if (Test-Path $pythonArchive)
{
    Remove-Item -Force $pythonArchive
}
Invoke-WebRequest -Uri http://dl.openstack.tld/python27new.tar.gz -OutFile $pythonArchive
if (Test-Path $pythonTar)
{
    Remove-Item -Force $pythonTar
}
if (Test-Path $pythonDir)
{
    Remove-Item -Recurse -Force $pythonDir
}
Write-Host "Ensure Python folder is up to date"
Write-Host "Extracting archive.."
& "C:\Program Files\7-Zip\7z.exe" x -y "$pythonArchive"
& "C:\Program Files\7-Zip\7z.exe" x -y "$pythonTar"

$hasPipConf = Test-Path "$env:APPDATA\pip"
if ($hasPipConf -eq $false){
    mkdir "$env:APPDATA\pip"
}
else 
{
    Remove-Item -Force "$env:APPDATA\pip\*"
}
Add-Content "$env:APPDATA\pip\pip.ini" $pip_conf_content

& easy_install -U pip
& pip install -U setuptools
& pip install -U wmi
& pip install cffi
& pip install numpy
popd

$hasPipConf = Test-Path "$env:APPDATA\pip"
if ($hasPipConf -eq $false){
    mkdir "$env:APPDATA\pip"
}
else 
{
    Remove-Item -Force "$env:APPDATA\pip\*"
}
Add-Content "$env:APPDATA\pip\pip.ini" $pip_conf_content

cp $templateDir\distutils.cfg C:\Python27\Lib\distutils\distutils.cfg

function cherry_pick($commit) {
    $eapSet = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    git cherry-pick $commit

    if ($LastExitCode) {
        echo "Ignoring failed git cherry-pick $commit"
        git checkout --force
    }
    $ErrorActionPreference = $eapSet
}

ExecRetry {
    & pip install C:\OpenStack\build\openstack\networking-hyperv
    if ($LastExitCode) { Throw "Failed to install networking-hyperv from repo" }
    popd
}

ExecRetry {
    pushd C:\OpenStack\build\openstack\neutron
    & pip install C:\OpenStack\build\openstack\neutron
    if ($LastExitCode) { Throw "Failed to install neutron from repo" }
    popd
}

ExecRetry {
    pushd C:\OpenStack\build\openstack\nova
    # Hyper-V: Trace original exception before converting exception
    Write-Host "Doing fetch... refs/changes/39/265239/4"
    git fetch https://review.openstack.org/openstack/nova refs/changes/39/265239/4
    cherry_pick FETCH_HEAD
    # end of cherry-pick
    & pip install C:\OpenStack\build\openstack\nova
    if ($LastExitCode) { Throw "Failed to install nova fom repo" }
    popd
}

ExecRetry {
    & pip install C:\OpenStack\build\openstack\compute-hyperv
    if ($LastExitCode) { Throw "Failed to install compute-hyperv from repo" }
    popd
}

$novaConfig = (gc "$templateDir\nova.conf").replace('[DEVSTACK_IP]', "$devstackIP").Replace('[LOGDIR]', "$openstackLogs").Replace('[RABBITUSER]', $rabbitUser)
$neutronConfig = (gc "$templateDir\neutron_hyperv_agent.conf").replace('[DEVSTACK_IP]', "$devstackIP").Replace('[LOGDIR]', "$openstackLogs").Replace('[RABBITUSER]', $rabbitUser)

Set-Content C:\OpenStack\etc\nova.conf $novaConfig
if ($? -eq $false){
    Throw "Error writting $templateDir\nova.conf"
}

Set-Content C:\OpenStack\etc\neutron_hyperv_agent.conf $neutronConfig
if ($? -eq $false){
    Throw "Error writting neutron_hyperv_agent.conf"
}

cp "$templateDir\policy.json" "$configDir\"
cp "$templateDir\interfaces.template" "$configDir\"

$hasNovaExec = Test-Path c:\Python27\Scripts\nova-compute.exe
if ($hasNovaExec -eq $false){
    Throw "No nova exe found"
}

$hasNeutronExec = Test-Path "c:\Python27\Scripts\neutron-hyperv-agent.exe"
if ($hasNeutronExec -eq $false){
    Throw "No neutron exe found"
}


Remove-Item -Recurse -Force "$remoteConfigs\$hostname\*"
Copy-Item -Recurse $configDir "$remoteConfigs\$hostname"

Write-Host "Starting the services"

Write-Host "Starting nova-compute service"
Try
{
    Start-Service nova-compute
}
Catch
{
    $proc = Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonDir\Scripts\nova-compute.exe" -ArgumentList "--config-file $configDir\nova.conf"
    Start-Sleep -s 30
    if (! $proc.HasExited) {Stop-Process -Id $proc.Id -Force}
    Throw "Can not start the nova-compute service"
}
Start-Sleep -s 30
if ($(get-service nova-compute).Status -eq "Stopped")
{
    Write-Host "We try to start:"
    Write-Host Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonDir\Scripts\nova-compute.exe" -ArgumentList "--config-file $configDir\nova.conf"
    Try
    {
    	$proc = Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonDir\Scripts\nova-compute.exe" -ArgumentList "--config-file $configDir\nova.conf"
    }
    Catch
    {
    	Throw "Could not start the process manually"
    }
    Start-Sleep -s 30
    if (! $proc.HasExited)
    {
    	Stop-Process -Id $proc.Id -Force
    	Throw "Process started fine when run manually."
    }
    else
    {
    	Throw "Can not start the nova-compute service. The manual run failed as well."
    }
}

Write-Host "Starting neutron-hyperv-agent service"
Try
{
    Start-Service neutron-hyperv-agent
}
Catch
{
    $proc = Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonDir\Scripts\neutron-hyperv-agent.exe" -ArgumentList "--config-file $configDir\neutron_hyperv_agent.conf"
    Start-Sleep -s 30
    if (! $proc.HasExited) {Stop-Process -Id $proc.Id -Force}
    Throw "Can not start the neutron-hyperv-agent service"
}
Start-Sleep -s 30
if ($(get-service neutron-hyperv-agent).Status -eq "Stopped")
{
    Write-Host "We try to start:"
    Write-Host Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonDir\Scripts\neutron-hyperv-agent.exe" -ArgumentList "--config-file $configDir\neutron_hyperv_agent.conf"
    Try
    {
    	$proc = Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonDir\Scripts\neutron-hyperv-agent.exe" -ArgumentList "--config-file $configDir\neutron_hyperv_agent.conf"
    }
    Catch
    {
    	Throw "Could not start the process manually"
    }
    Start-Sleep -s 30
    if (! $proc.HasExited)
    {
    	Stop-Process -Id $proc.Id -Force
    	Throw "Process started fine when run manually."
    }
    else
    {
    	Throw "Can not start the neutron-hyperv-agent service. The manual run failed as well."
    }
}
