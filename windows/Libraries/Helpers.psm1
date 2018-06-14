function VMStop([String] $vmName)
{
    $vm = get-vm $vmName
    if ( $vm.State -eq "Off")
    {
        Write-Host "Info : $vmName is stopped"
        return $true
    }

    stop-vm $vmName
    if ( $? -ne $true )
    {
        Write-Host "Error : stop-VM $vm failed"
        return $false
    }

    $timeout = 100
    while ($timeout -gt 0)
    {
        $vm = get-vm $vmName
        if ($vm.state -eq "Off")
        {
            Write-Host "Info : $vmName state is Off now"
            break
        }
        else
        {
            Write-Host "Info : $vmName state is not Off, waiting..."
            start-sleep -seconds 1
            $timeout -= 1
        }
    }
    if ( $timeout -eq 0 -and $vm.state -ne "Off")
    {
        Write-Host "Error : Stop $vm failed (timeout=$timeout)"
        return $false
    }

    return $true
}

function VMRemove([String]$vmName)
{
    # Check the vm, if exists, then delete
    Get-VM -Name $vmName -ErrorAction "SilentlyContinue" | out-null
    if ( $? )
    {
        # check vm is not Running
        if ( $(Get-VM -Name $vmName).State -eq "Running")
        {
            VMStop($vmName)
        }
        Write-Host "Info: Remove $vmName"
        # get parent and vhd path
        $vhdParentPath = (Get-VM -VMName ${vmName} | Select-Object VMId | Get-VHD).ParentPath
        $vhdPath = (Get-VM -VMName ${vmName} | Select-Object VMId | Get-VHD).Path

        Remove-VM ${vmName} -Force
        if ( $? )
        {
            Write-Host "Info: Remove $vmName successfully"
        }
        else
        {
            Write-Host "Error: Remove $vmName failed"
        }
    }

    # Delete vhd file.
    $vhd = ""
    if ( $vhdParentPath )
    {
        $vhd = $vhdParentPath
    }
    else
    {
        $vhd = $vhdPath
    }

    if ($vhd)
    {
        write-host "REMOVING .vhd VM DISK FILE - ${vhd}."
        Remove-Item -Path $vhd -Force
    }
}

function GetIPv4ViaKVP([String] $vmName)
{
    $vmObj = Get-WmiObject -Namespace root\virtualization\v2 -Query "Select * From Msvm_ComputerSystem Where ElementName=`'$vmName`'"
    if (-not $vmObj)
    {
        Write-Error -Message "GetIPv4ViaKVP: Unable to create Msvm_ComputerSystem object" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }

    $kvp = Get-WmiObject -Namespace root\virtualization\v2 -Query "Associators of {$vmObj} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent"
    if (-not $kvp)
    {
        Write-Error -Message "GetIPv4ViaKVP: Unable to create KVP exchange component" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }

    $rawData = $Kvp.GuestIntrinsicExchangeItems
    if (-not $rawData)
    {
        Write-Error -Message "GetIPv4ViaKVP: No KVP Intrinsic data returned" -Category ReadError -ErrorAction SilentlyContinue
        return $null
    }

    $addresses = $null

    foreach ($dataItem in $rawData)
    {
        $found = 0
        $xmlData = [Xml] $dataItem
        foreach ($p in $xmlData.INSTANCE.PROPERTY)
        {
            if ($p.Name -eq "Name" -and $p.Value -eq "NetworkAddressIPv4")
            {
                $found += 1
            }

            if ($p.Name -eq "Data")
            {
                $addresses = $p.Value
                $found += 1
            }

            if ($found -eq 2)
            {
                $addrs = $addresses.Split(";")
                foreach ($addr in $addrs)
                {
                    if ($addr.StartsWith("127."))
                    {
                        Continue
                    }
                    return $addr
                }
            }
        }
    }

    Write-Error -Message "GetIPv4ViaKVP: No IPv4 address found for VM ${vmName}" -Category ObjectNotFound -ErrorAction SilentlyContinue
    return $null
}

function WaitForVMToStartKVP([String] $vmName, [int] $timeout)
{
    $waitTimeOut = $timeout
    while ($waitTimeOut -gt 0)
    {
        $ipv4 = GetIPv4ViaKVP $vmName
        if ($ipv4)
        {
            return $true
        }

        $waitTimeOut -= 10
        Start-Sleep -s 10
    }

    Write-Error -Message "WaitForVMToStartKVP: VM ${vmName} did not start KVP within timeout period ($timeout)" -Category OperationTimeout -ErrorAction SilentlyContinue
    return $false
}

function NewCheckpoint([String] $vmName, [String] $snapshotName)
{
    Write-Host "Info: make checkpoint of $vmName, checkpoint name is $snapshotName"
    Checkpoint-VM -Name $vmName -SnapshotName $snapshotName

    if ( $snapshotName -eq $(Get-VMSnapshot $vmName).Name)
    {
        Write-Host "Info: $snapshotName for $vmName is created successfully"
        return $true
    }
    else
    {
        return $false
    }
}