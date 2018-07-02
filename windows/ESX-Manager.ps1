param(
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
    [String] $omni_user,
    [String] $hostID,
    [String] $vsphereServer = "",
    [String] $vsphereProtocol,
    [PSCredential] $credential
)

if ($dual)
{
    Set-Variable -Name smoke -Value "" -Option constant -Scope Script
}
else
{
    Set-Variable -Name smoke -Value "-smoke" -Option constant -Scope Script
}

Set-Variable -Name switchName -Value "VM Network" -Option constant -Scope Script
Set-Variable -Name arch -Value "x86_64" -Option constant -Scope Script
Set-Variable -Name snapshotName -Value "ICABase" -Option constant -Scope Script
Set-Variable -Name kernelName -Value "$name-$version-$release" -Option constant -Scope Script
Set-Variable -Name vmName -Value "$kernelName-${buildID}${smoke}" -Option constant -Scope Script
Set-Variable -Name vmNameB -Value "$vmName-B" -Option constant -Scope Script

Get-ChildItem .\Libraries -Recurse | Where-Object { $_.FullName.EndsWith(".psm1") } | ForEach-Object { Import-Module $_.FullName -Force}

function GetDataStore([String] $hostName)
{
    if ( -not $hostName) {
        Write-Host "Error: GetDataStore $hostName is required"
        return $false
    }
    $datastores = (Get-VMHost -Name $hostName | Get-Datastore)

    if ($datastores) {
        # if more than 1 datastores, get the right one.
        if ($datastores -is [array]) {
            foreach ($ds in $datastores) {
                if ($($ds.Name).Contains('datastore')) {
                    Write-Host "Info: Found datastore $ds"
                    return $ds
                 }
            }
        }
        else {
            return $datastores
        }
    }
    else {
        Write-Host "Error: Get-VMHost '$hostName' default datastore failed"
        return $false
    }
}

function NewVM ([String] $vmName,
                [String] $hostID,
                [Switch] $gen2,
                [String] $image,
                [Int32] $cpu,
                [Decimal] $memory,
                [String] $networkAdapterName)
{
    $ProgressPreference = "SilentlyContinue"

    $ds = GetDataStore $hostID
    $hostObj = Get-VMHost -Name $hostID
    Write-Host "Info: Import $vmName from .\$image"
    $newVM = Import-VApp -Source ".\$image" -VMHost $hostObj -Datastore $ds -Name $vmName
    if ($newVM) {
        Write-Host "Info: Set $vmName with CPU - $cpu and Memory - $memory."
        Set-VM -VM $newVM -NumCpu $cpu -MemoryGB $memory -Confirm:$false | Out-Null

        $networkAdapter = Get-NetworkAdapter -VM $newVM
        if ($networkAdapter) {
            if ($networkAdapter.NetworkName -ne $networkAdapterName) {
                Write-Host "Info: Network Adapter $($networkAdapter.NetworkName) - does not belong to $networkAdapterName."
                Set-NetworkAdapter -NetworkAdapter $networkAdapter -NetworkName $networkAdapterName -Confirm:$false
            }
        }

        if ($gen2)
        {
            $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
            $spec.Firmware = [VMware.Vim.GuestOSDescriptorFirmwareType]::efi
            $newVM.ExtensionData.ReconfigVM($spec)

            $vmFirmware = (Get-VM -Name $vmName -Location $hostObj).ExtensionData.config.Firmware
            if ($vmFirmware -ne "efi")
            {
                Write-Host "Error: $vmName actual firmware is: $vmFirmware, but expected is: EFI"
                return $false
            }
        }
    } else {
        Write-Host "Error: Create VM $vmName fail."
        return $false
    }
}

function VMSetup([String]$vmName, [String]$hostID, [String]$image, [String]$omni_ip, [String]$omni_port, [String]$omni_user, [Bool]$gen2, [String]$switchName, [Int32]$cpuCount, [Decimal]$mem, [String]$snapshotName, [String]$kernelName)
{
    Write-Host "Info: Downloading $image from ${omni_ip}:${omni_port} to current folder."
    Write-Output y | bin\pscp -P $omni_port -l $omni_user -i ssh\3rd_id_rsa.ppk ${omni_ip}:nfs/${image} "."
    # remove vm if already exists same name VM already exists
    ESXRemove -vmName $vmName -hostID $hostID
    # Create vm based on new vhdx file
    if ($gen2)
    {
        NewVM -vmName $vmName -hostID $hostID -gen2 -image $image -cpu $cpuCount -memory $mem -networkAdapterName $switchName
    }
    else
    {
        NewVM -vmName $vmName -hostID $hostID -image $image -cpu $cpuCount -memory $mem -networkAdapterName $switchName
    }

    #Remove BIG image file to avoid clearing workspace fail.
    Write-Host "Info: Removing image file $image."
    Remove-Item -Path ".\$image" -Force
    # Now Start the VM
    Write-Host "Info: Starting VM $vmName."
    Get-VMHost -Name $hostID | Get-VM -Name $vmName | Start-VM
    WaitForVMStart -vmName $vmName -hostID $hostID
    $vmIP = GetIPv4ViaPowerCLI -vmName $vmName -hostID $hostID

    # Download kernel rpm from omni server and install
    Write-Host "Info: Sleep 60 seconds for ssh service up before kernel upgrade."
    TestPort -serverName $vmIP
    Start-Sleep -seconds 60
    Write-Output y | bin\plink -v -l root -i ssh\3rd_id_rsa.ppk $vmIP "exit 0"
    Write-Host "Info: Downloading $kernelName to VM $vmIP."
    bin\plink -v -l root -i ssh\3rd_id_rsa.ppk $vmIP "scp -o StrictHostKeyChecking=no -P $omni_port -i /root/.ssh/id_rsa_private data@${omni_ip}:kernel* . && yum install -y ./kernel* && reboot"

    WaitForVMStart -vmName $vmName -hostID $hostID
    $vmIP = GetIPv4ViaPowerCLI -vmName $vmName -hostID $hostID

    Write-Host "Info: Sleep 60 seconds for ssh service up before checking kernel version."
    TestPort -serverName $vmIP
    Start-Sleep -seconds 60
    bin\plink -v -l root -i ssh\3rd_id_rsa.ppk $vmIP "exit 0"
    $kernel = bin\plink -v -l root -i ssh\3rd_id_rsa.ppk $vmIP "uname -r"
    Write-Host "Info: Get kernel version from VM ${vmName}: ${kernel}, expect ${kernelName} "
    if ("${kernelName}.x86_64" -Match $kernel)
    {
        Write-Host "Info: Kernel version matched"
        WaitForVMToStop -vmName $vmName -hostID $hostID
        MakeSnapshot -vmName $vmName -hostID $hostID -snapshotName $snapshotName
    }
    else
    {
        Write-Host "ERROR: Unable get correct kernel version"
        WaitForVMToStop -vmName $vmName -hostID $hostID
        ESXRemove -vmName $vmName -hostID $hostID
    }
}

PowerCLIImport
ConnectToVIServer -visIpAddr $vsphereServer -credential $credential -visProtocol $vsphereProtocol
switch ($action)
{
    "add"
    {
        VMSetup -vmName $vmName -hostID $hostID -image $image -omni_ip $omni_ip -omni_port $omni_port -omni_user $omni_user -gen2 $gen2 -switchName $switchName -cpuCount $cpuCount -mem $memorySize -snapshotName $snapshotName -kernelName $kernelName
        if ($dual -and (-not $vsphereServer))
        {
            VMSetup -vmName $vmNameB -hostID $hostID -image $image -omni_ip $omni_ip -omni_port $omni_port -omni_user $omni_user -gen2 $gen2 -switchName $switchName -cpuCount $cpuCount -mem $memorySize -snapshotName $snapshotName -kernelName $kernelName
        }
    }
    "del"
    {
        ESXRemove -vmName $vmName -hostID $hostID
        if ($dual -and (-not $vsphereServer))
        {
            ESXRemove -vmName $vmNameB -hostID $hostID
        }
    }
}
DisconnectWithVIServer
