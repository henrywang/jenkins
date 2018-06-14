##############################################################################
##
## Descrition:
## copy vhdx file to new vhdx with kernel name, create new vm based on new vhdx
##
## Revision:
## v1.0 - xuli - 09/14/2017 - Create script based on huiijing's clone vm script
##
###############################################################################

 #Invoke-Command -FilePath .\downstream-create-vm.ps1 -ComputerName 2016-131-61 -ArgumentList "2016-131-61","RHEL-7.5-DOWNSTREAM-GEN1","http://10.73.199.117/downstream/kernel/kernel-3.10.0-858.el7.x86_64.rpm","D:\new-copy-vhdx\","redhat",'C:\InstallDownstreamKernel.sh',$false,"http://10.73.199.117/downstream/tools/lcov-1.13-1.noarch.rpm",gen1,"3.10.0-858.el7","http://10.73.199.117/downstream/kernel/linux-firmware-20180220-62.git6d51311.el7.noarch.rpm","RHEL-7.5-DOWNSTREAM-GEN1-3.10.0-858.el7"
param (
    [CmdletBinding()]
    [String] $action,
    [String] $name,
    [String] $version,
    [String] $release,
    [String] $image,
    [String] $buildID,
    [String] $hvServer,
    [Switch] $Gen2,
    [Int64] $cpuCount = 2,
    [Int64] $memorySize = 2,
    [String] $omni_ip,
    [String] $omni_port,
    [String] $omni_user
)

Set-Variable -Name switchName -Value "External" -Option constant -Scope Script
Set-Variable -Name arch -Value "x86_64" -Option constant -Scope Script
Set-Variable -Name snapshotName -Value "ICABase" -Option constant -Scope Script
Set-Variable -Name kernelName -Value "$name-$version-$release" -Option constant -Scope Script
Set-Variable -Name vmName -Value "$kernelName-$buildID" -Option constant -Scope Script
Set-Variable -Name vmNameB -Value "$vmName-B" -Option constant -Scope Script
Set-Variable -Name vmPath -Value "C:\downstream-vm-$buildID\" -Option constant -Scope Script
Set-Variable -Name vmIP -Value $null -Scope Script

Get-ChildItem .\Libraries -Recurse | Where-Object { $_.FullName.EndsWith(".psm1") } | ForEach-Object { Import-Module $_.FullName -Force}

function NewImage([String] $vmPath, [String]$vmName, [String]$image, [String]$omni_ip, [String]$omni_port, [String]$omni_user)
{
    if ( -not (Test-Path $vmPath) )
    {
        New-Item -ItemType directory -Path $vmPath | Out-Null
        Write-Host "Info: Create new vhdx directory $NewVHDXDir"
    }

    Write-Output y | bin/pscp -P $omni_port -l $omni_user -i ssh/3rd_id_rsa.ppk ${omni_ip}:${targetRemoteFile}
}

function CreateVMBasedVHDX([String] $NewVHDXPath, [Switch] $Gen2, [String] $VirtualSwitch,[String] $vmName, [Int64] $cpuCount, [Int64] $mem )
{
    # Convert GB to bytes because parameter -MemoryStartupByptes requires bytes
    [Int64]$memory = 1GB * $mem

    if ( $Gen2 )
    {
        New-VM -Name "$vmName" -Generation 2 -BootDevice "VHD" -MemoryStartupBytes $memory -VHDPath $NewVHDXPath -SwitchName $VirtualSwitch | Out-Null
    }
    else
    {
        New-VM -Name "$vmName" -BootDevice "IDE" -MemoryStartupBytes $memory -VHDPath $NewVHDXPath -SwitchName $VirtualSwitch | Out-Null
    }

    if ( -not $? )
    {
        Write-Host "New-VM $vmName failed"
        # rm new created disk
        If ( Test-Path $NewVHDXPath ){
            Remove-Item $NewVHDXPath
        }
        return $false
    }
    Write-Host "Info: New-VM $vmName successfully"

    # If gen 2 vm, set vmfirmware secure boot disabled
    if ( $Gen2 )
    {
        # disable secure boot
        Set-VMFirmware $vmName -EnableSecureBoot Off

        if ( -not $? )
        {
            Write-Host "Info: Set-VMFirmware $vmName secureboot failed"
            return $false
        }

        Write-Host "Info: Set-VMFirmware $vmName secureboot successfully"
    }

    # set processor to 2, default is 1
    Set-VMProcessor -vmName $vmName -Count $cpuCount

    if ( ! $? )
    {
        Write-Host "Error: Set-VMProcessor $vmName  to $cpuCount failed"
        return $false
    }

    if ( (Get-VMProcessor -vmName $vmName).Count -eq $cpuCount )
    {
        Write-Host "Info: Set-VMProcessor $vmName to $cpuCount"
    }
    return $true
}

function PreSetupVM( [String] $vmName, [String] $vcpu, [String] $mem)
{
    $NewVHDXPath = GetNewVHDXPath $NewVHDXDir $vm_name
    if (-not $NewVHDXPath )
    {
        Write-Host "Failed to get new vhd path"
        return $false
    }
    else
    {
        Write-Host "Info: New vhdx file paths are $NewVHDXPath"
    }

    # remove vm if already exists same name VM already exists
    RemoveTargetVM $vm_name $hvServer
    # copy to new vhdx file
    $ret = CopyNewVHD $NewVHDXPath
    if (-not $ret)
    {
        Write-Host "Error: Failed to cpy vhdx to $NewVHDXPath"
        return $false
    }

    # Create vm based on new vhdx file
    $ret = CreateVMBasedVHDX $NewVHDXPath $VmGeneration $VirtualSwitch $vm_name $vcpu $mem
    if (-not $ret)
    {
        Write-Host "Error: Failed to create vm based on $NewVHDXPath"
        return $false
    }

    # Now Start the VM
    $timeout = 300

    Start-VM -Name $vm_name -ComputerName $hvServer

    if (-not (WaitForVMToStartKVP $vm_name $hvServer $timeout ))
    {
        Write-Host "ERROR: ${vm_name} failed to start"
        return $False
    }
    else
    {
        Write-Host "Info: Started VM ${vm_name}"
        return $True
    }
}

function InstallKernel()
{
    Write-Host "before start install, sleep 2 minutes "
    Start-Sleep -Seconds 120
    # get around plink questions
    Write-Output y | plink -l root -pw $password ${vmIP} "exit 0"

    echo y | pscp -l root -pw $password ${remoteFile} ${ipv4}:${targetRemoteFile}

    echo y | plink -l root -pw $password ${ipv4} "dos2unix ${targetRemoteFile} 2>/dev/null"

    echo y | plink -l root -pw $password ${ipv4} " chmod +x ${targetRemoteFile}  2> /dev/null"


    Write-Host "Info: Start to send command ./${targetRemoteFile} ${Kernel_URL} ${kernel_vr} ${firmware_url} ${Gcov} ${lcov_url}"

    plink -l root -pw $password ${ipv4} "sh -x ./${targetRemoteFile} ${Kernel_URL} ${kernel_vr} ${firmware_url} ${Gcov} ${lcov_url} &> /root/${targetRemoteFile}.log"
    #if ( $? -eq $False )
    #{
    #    Write-Host "Error: './${targetRemoteFile} ${Kernel_URL} ${kernel_vr} ${firmware_url} ${Gcov} ${lcov_url}' failed, pls check"
    #    return $False
    #}
    #else
    #{
    #    Write-Host "Info: './${targetRemoteFile} ${Kernel_URL} ${kernel_vr} ${firmware_url} ${Gcov} ${lcov_url}' successfully"
    #}

    start-sleep -s 2
    Write-Host "Info: Prepare to restart VM "

    $value = WaitForVMToStop $vmName
    if ( $value -ne $true )
    {
        Write-Host "Error : stop vm $vmName failed"
        return $false
    }
    else
    {
        Write-Host "Info : stop vm $vmName successfully"
    }

    $timeout = 300

    Start-VM -Name $vmName -ComputerName $hvServer

    if (-not (WaitForVMToStartKVP $vmName $hvServer $timeout))
    {
        Write-Host "ERROR: ${vmName} failed to start"
        return $False
    }
    else
    {
        Write-Host "Info: Restart VM ${vmName}"
    }

    Start-Sleep -Seconds 120

    $ExpKernel = "${kernel_vr}.${ARCH}"

    echo y | plink -l root -pw $password ${ipv4} "exit 0"
    $kernel = plink -l root -pw ${password} ${ipv4} "uname -r"

    Write-Host "Info: Get kernel version from VM ${vmName}: ${kernel}, expect ${ExpKernel} "

    if ( $kernel -match $ExpKernel)
    {
        Write-Host "Info: Kernel version matched"
        return $true
    }
    else
    {
        Write-host "ERROR: Unable get correct kernel version" -ErrorAction SilentlyContinue
        return $False
     }
}

function GetCredential () {
    $SecurePassword = $env:HV_PASSWORD | ConvertTo-SecureString -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential -ArgumentList $env:HV_USERNAME, $SecurePassword
}

function ProvisionVM ([String] $hostID) {
    $cred = GetCredential
    Invoke-Command -Credential $cred -ComputerName $hostID -ScriptBlock ${function:Foo} -ArgumentList $x,$y
}

function ClearVM ([String] $hostID, [String] $vmName, [String]$vmPath) {
    $cred = GetCredential
    Invoke-Command -Credential $cred -ComputerName $hostID -ScriptBlock ${function:VMRemove} -ArgumentList $vmName, $hostID, $vmPath
}

switch ($action)
{
    "Add"
    {
        ProvisionVM $hostID
    }
    "Remove"
    {
        ClearVM -hostID $hostID -vmName $vmName -vmPath $vmPath
    }
}
$start = (Get-Date)

$ret = PreSetupVM $vmName $vcpu $mem
Write-Host "Info: PreSetupVM return '${ret}' "
if (-not $ret[-1])
{
    Write-Host "Error: PreSetupVM run failed"
    exit 1
}
else
{
    Write-Host "Info: PreSetupVM run success"
}
Start-Sleep -Seconds 5
#$vmName = "RHEL-7.4-DOWNSTREAM-GEN2_3.10.0-709"
# $hvServer = "2016-Auto"

Write-Host "Info: VmName is $vmName"
Write-Host "Info: hvServer is $hvServer"
$vmIP = GetIPv4ViaKVP $vmName $hvServer
Write-Host -f red "Info: VM ${vmName} ipv4 is $vmIP"

$ret=InstallKernel
Write-Host "Info: InstallKernel return ${ret} "
if ( $false -eq $ret[-1] )
{
    Write-Host "Error: InstallKernel run failed"
    exit 1
}
else
{
    Write-Host "Info: InstallKernel run success"
}

$exitCode = makeCheckpoint $vmName
Write-Host "Info: makeCheckpoint return ${exitCode}"
if ( -not $exitCode )
{
    Write-Host "Info: Make Checkpoint of vm $vmName with result $exitCode"
    exit 1
}

# create vm B
if ( $vmNameB )
{
    $vmName = $vmNameB
    $vcpu = 2
    $mem = 2
    $ret = PreSetupVM $vmName $vcpu $mem
    Write-Host "Info: PreSetupVM return '${ret}' "
    if (-not $ret[-1])
    {
        Write-Host "Error: PreSetupVM run failed"
        exit 1
    }
    else
    {
        Write-Host "Info: PreSetupVM run success"
    }
    Start-Sleep -Seconds 5

    Write-Host "Info: VmName is $vmName"
    Write-Host "Info: hvServer is $hvServer"
    $ipv4 = GetIPv4ViaKVP $vmName $hvServer
    Write-Host -f red "Info: VM ${vmName} ipv4 is $ipv4"

    $exitCode = makeCheckpoint $vmName
    Write-Host "Info: makeCheckpoint return ${exitCode}"
}

$end = (Get-Date)
Write-Host "Info: The script executed $(($end-$start).TotalMinutes) minutes"
if ( -not $exitCode )
{
    Write-Host "Info: Make Checkpoint of vm $vmName with result $exitCode"
    exit 1
}
else
{
    exit 0
}
