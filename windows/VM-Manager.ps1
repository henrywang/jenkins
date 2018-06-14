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
    [Bool] $dual,
    [String] $name,
    [String] $version,
    [String] $release,
    [String] $image,
    [String] $buildID,
    [Bool] $gen2,
    [Int64] $cpuCount = 2,
    [Int64] $memorySize = 2,
    [String] $omni_ip,
    [String] $omni_port,
    [String] $omni_user
)

if ($dual)
{
    Set-Variable -Name smoke -Value "" -Option constant -Scope Script
}
else
{
    Set-Variable -Name smoke -Value "-smoke" -Option constant -Scope Script
}

Set-Variable -Name switchName -Value "External" -Option constant -Scope Script
Set-Variable -Name arch -Value "x86_64" -Option constant -Scope Script
Set-Variable -Name snapshotName -Value "ICABase" -Option constant -Scope Script
Set-Variable -Name kernelName -Value "$name-$version-$release" -Option constant -Scope Script
Set-Variable -Name vmName -Value "$kernelName-${buildID}${smoke}" -Option constant -Scope Script
Set-Variable -Name vmNameB -Value "$vmName-B" -Option constant -Scope Script
Set-Variable -Name vmPath -Value "C:\downstream-vm\" -Option constant -Scope Script

Get-ChildItem .\Libraries -Recurse | Where-Object { $_.FullName.EndsWith(".psm1") } | ForEach-Object { Import-Module $_.FullName -Force}

function GetImage([String]$vmPath, [String]$vmName, [String]$image, [String]$omni_ip, [String]$omni_port, [String]$omni_user)
{
    Write-Host "Info: Downloading $image from ${omni_ip}:${omni_port} to $vmPath."
    if (-not (Test-Path $vmPath))
    {
        New-Item -ItemType directory -Path $vmPath | Out-Null
        Write-Host "Info: Create new vhdx directory $vmPath"
    }

    Write-Output y | bin\pscp -P $omni_port -l $omni_user -i ssh\3rd_id_rsa.ppk ${omni_ip}:nfs/${image} "${vmPath}${vmName}.vhdx"
}

function NewVMFromVHDX([String]$vmPath, [Switch]$gen2, [String]$switchName, [String]$vmName, [Int64]$cpuCount, [Int64]$mem)
{
    Write-Host "Info: Creating $vmName with $cpuCount CPU and ${mem}G memory."
    # Convert GB to bytes because parameter -MemoryStartupByptes requires bytes
    [Int64]$memory = 1GB * $mem

    if ($gen2)
    {
        New-VM -Name "$vmName" -Generation 2 -BootDevice "VHD" -MemoryStartupBytes $memory -VHDPath $vmPath -SwitchName $switchName | Out-Null
    }
    else
    {
        New-VM -Name "$vmName" -BootDevice "IDE" -MemoryStartupBytes $memory -VHDPath $vmPath -SwitchName $switchName | Out-Null
    }

    if (-not $?)
    {
        Write-Host "New-VM $vmName failed"
        # rm new created disk
        If (Test-Path $vmPath){
            Remove-Item $vmPath
        }
        return $false
    }
    Write-Host "Info: New-VM $vmName successfully"

    # If gen 2 vm, set vmfirmware secure boot disabled
    if ($gen2)
    {
        # disable secure boot
        Set-VMFirmware $vmName -EnableSecureBoot Off

        if (-not $?)
        {
            Write-Host "Info: Set-VMFirmware $vmName secureboot failed"
            return $false
        }

        Write-Host "Info: Set-VMFirmware $vmName secureboot successfully"
    }

    # set processor to 2, default is 1
    Set-VMProcessor -vmName $vmName -Count $cpuCount

    if (! $?)
    {
        Write-Host "Error: Set-VMProcessor $vmName  to $cpuCount failed"
        return $false
    }

    if ((Get-VMProcessor -vmName $vmName).Count -eq $cpuCount)
    {
        Write-Host "Info: Set-VMProcessor $vmName to $cpuCount"
    }
    return $true
}

function VMSetup([String]$vmPath, [String]$vmName, [String]$image, [String]$omni_ip, [String]$omni_port, [String]$omni_user, [Bool]$gen2, [String]$switchName, [Int64]$cpuCount, [Int64]$mem, [String]$snapshotName, [String]$kernelName)
{
    GetImage -vmPath $vmPath -vmName $vmName -image $image -omni_ip $omni_ip -omni_port $omni_port -omni_user $omni_user
    # remove vm if already exists same name VM already exists
    VMRemove -vmName $vmName
    # Create vm based on new vhdx file
    if ($gen2)
    {
        NewVMFromVHDX -vmPath "${vmPath}${vmName}.vhdx" -gen2 -switchName $switchName -vmName $vmName -cpuCount $cpuCount -mem $mem
    }
    else
    {
        NewVMFromVHDX -vmPath "${vmPath}${vmName}.vhdx" -switchName $switchName -vmName $vmName -cpuCount $cpuCount -mem $mem
    }
    # Now Start the VM
    Write-Host "Info: Starting VM $vmName."
    $timeout = 300
    Start-VM -Name $vmName
    WaitForVMToStartKVP -vmName $vmName -timeout $timeout
    $vmIP = GetIPv4ViaKVP $vmName

    Write-Host "Info: Downloading $kernelName to VM $vmIP."
    # Download kernel rpm from omni server and install
    Write-Output y | plink -l root -i ssh\3rd_id_rsa.ppk $vmIP "exit 0"
    Write-Output y | plink -l root -i ssh\3rd_id_rsa.ppk $vmIP "scp -o StrictHostKeyChecking=no -P $omni_port -i /root/.ssh/id_rsa_private data@${omni_ip}:kernel* . && yum install -y ./kernel* && reboot"

    WaitForVMToStartKVP -vmName $vmName -timeout $timeout
    $vmIP = GetIPv4ViaKVP $vmName

    Write-Output y | plink -l root -i ssh\3rd_id_rsa.ppk $vmIP "exit 0"
    $kernel = Write-Output y | plink -l root -i ssh\3rd_id_rsa.ppk $vmIP "uname -r"
    Write-Host "Info: Get kernel version from VM ${vmName}: ${kernel}, expect ${kernelName} "
    if ("${kernelName}.x86_64" -Match $kernel)
    {
        Write-Host "Info: Kernel version matched"
        VMStop -vmName $vmName
        NewCheckpoint -vmName $vmName -snapshotName $snapshotName
    }
    else
    {
        Write-host "ERROR: Unable get correct kernel version" -ErrorAction SilentlyContinue
        VMStop -vmName $vmName
        VMRemove -vmName $vmName -vmPath $vmPath
    }
}

switch ($action)
{
    "add"
    {
        VMSetup -vmPath $vmPath -vmName $vmName -image $image -omni_ip $omni_ip -omni_port $omni_port -omni_user $omni_user -gen2 $gen2 -switchName $switchName -cpuCount $cpuCount -mem $memorySize -snapshotName $snapshotName -kernelName $kernelName
        if ($dual)
        {
            VMSetup -vmPath $vmPath -vmName $vmNameB -image $image -omni_ip $omni_ip -omni_port $omni_port -omni_user $omni_user -gen2 $gen2 -switchName $switchName -cpuCount $cpuCount -mem $memorySize -snapshotName $snapshotName -kernelName $kernelName
        }
    }
    "remove"
    {
        VMRemove -vmName $vmName
    }
}
