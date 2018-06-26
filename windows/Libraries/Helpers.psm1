#
# Hyper-V Helper Functions
#
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

#
# ESXi Helper Functions
#
function PowerCLIImport () {
    # Add vmware.vimautomation.core path to environment variables
    $p = [Environment]::GetEnvironmentVariable("PSModulePath")
    if ( ! $p.Contains("VMware") )
    {
        $p += ";C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Modules\"
        [Environment]::SetEnvironmentVariable("PSModulePath",$p)
    }

    $modules = Get-Module

    $foundVimautomation = $false
    foreach($module in $modules)
    {
        if($module.Name -eq "VMware.VimAutomation.Core")
        {
            Write-Host "Info: PowerCLI module VMware.VimAutomation.Core already exists."
            $foundVimautomation = $true
            break
        }
    }

    if (-not $foundVimautomation)
    {
        Import-Module VMware.VimAutomation.Core
    }
}
  
function ConnectToVIServer ([string] $visIpAddr,
                            [PSCredential] $credential,
                            [string] $visProtocol)
{
    # Verify the VIServer related environment variable existed.
    if (-not $visIpAddr)
    {
        Write-Host "Error: vCenter IP address is not configured, it is required."
        exit
    }

    if (-not $credential)
    {
        Write-Host "Error: vCenter login credential is not configured, it is required."
        exit
    }

    if (-not $visProtocol)
    {
        Write-Host "Error: vCenter connection method is not configured, it is required."
        exit
    }

    # Check the PowerCLI package installed
    $module = get-module -Name VMware.VimAutomation.Core
    if (-not $module)
    {
        Write-Host "Error: Please install VMWare PowerCLI package."
        exit
    }

    if (-not $global:DefaultVIServer)
    {
        Write-Host "Info: Connecting to VIServer $visIpAddr."
        Connect-VIServer -Server $visIpAddr -Protocol $visProtocol -Credential $credential -Force | Out-Null
        if (-not $?)
        {
            Write-Host "Error: Cannot connect to vCenter with $visIpAddr address, $visProtocol protocol, and credential $credential."
            exit
        }
        Write-Host "Debug: vCenter connected to session id $($global:DefaultVIServer.SessionId)"
    }
    else
    {
        Write-Host "Info: vCenter connected already! Session id: $($global:DefaultVIServer.SessionId)"
    }
}

function DisconnectWithVIServer ()
{
    # Disconnect with vCenter if there's a connection.
    if ($global:DefaultVIServer)
    {
        foreach ($viserver in $global:DefaultVIServer)
        {
            Write-Host "Info : Disconnect with VIServer $($viserver.name)."
            Disconnect-VIServer -Server $viserver -Force -Confirm:$false
        }
    }
    else
    {
        Write-Host "Info: There is not session to VI Server exist."
    }
}

function  WaitForVMToStop ([string] $vmName ,[string] $hostID)
{
    $timeout = 120
    Get-VMHost -Name $hostID | Get-VM -Name $vmName | Stop-VM -Confirm:$false
    if ($? -eq $false) {
        Write-Host "Error: Stop VM '$vmName' failed"
        return $false
    }
    while ($timeout -gt 0)
    {
        $state = (Get-VMHost -Name $hostID | Get-VM -Name $vmName).PowerState
        if ( $state -ne "PoweredOff" ) {
            $timeout -= 5
            Start-Sleep -S 5
        } else {
            return $true
        }
    }

    Write-Error -Message "StopVM: VM did not stop within timeout period" -Category OperationTimeout -ErrorAction SilentlyContinue
    return $false
}

function ESXRemove ([String] $vmName, [String] $hostID)
{
    $ProgressPreference = "SilentlyContinue"

    $hostObj = Get-VMHost -Name $hostID
    try
    {
        $vmObj = Get-VM -Name $vmName -Location $hostObj
    }
    catch
    {
        Write-Error "Error: Cloud not find $vmName."
        return $false
    }
    if ( $vmObj ) {
        Write-Host "Info: Found $vmName, remove it."
        if ( $vmObj.PowerState -eq "PoweredOn") {
            Write-Host "Info: Before remove '$vmName', stop first"
            Stop-VM -VM $vmObj -Confirm:$false
            if ($? -eq $false) {
                Write-Host "Error: Stop VM '$vmName' failed"
                return $false
            }
            $timeout = 120
            while ($timeout -gt 0) {
                $state = (Get-VM -Name $vmName -Location $hostObj).PowerState
                if ( $state -ne "PoweredOff" ) {
                    $timeout -= 1
                    Start-Sleep -S 1
                } else {
                    break
                }
            }
        }
        Remove-VM -VM $vmObj -DeletePermanently -Confirm:$false -RunAsync
        if ( $? -eq $true ){
            Write-Host "Info: Remove $vmName successfully"
        }
        else {
            Write-Host "Error: Remove $vmName failed"
            return $false
        }
    }
}

function GetIPv4ViaPowerCLI([String] $vmName, [String] $hostID)
{
    $hostObj = Get-VMHost -Name $hostID
    $vmOut = Get-VM -Name $vmName -Location $hostObj
    if (-not $vmOut)
    {
        Write-Error -Message "GetIPv4ViaPowerCLI: Unable to create VM object for VM ${vmName}" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }

    $vmguestOut = Get-VMGuest -VM $vmOut
    if ($vmguestOut -eq $false)
    {
        Write-Error -Message "GetIPv4ViaPowerCLI: Unable to create VM object for VM ${vmName}" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }
    $ipAddresses = $vmguestOut.IPAddress
    if (-not $ipAddresses)
    {
        Write-Error -Message "GetIPv4ViaPowerCLI: No network adapters found on VM ${vmName}" -Category ObjectNotFound -ErrorAction SilentlyContinue
        return $null
    }
    foreach ($address in $ipAddresses)
    {
        # Ignore address if it is not an IPv4 address
        $addr = [IPAddress] $address
        if ($addr.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork)
        {
            Continue
        }

        # Ignore address if it a loopback address
        if ($address.StartsWith("127."))
        {
            Continue
        }

        # See if it is an address we can access
        $ping = New-Object System.Net.NetworkInformation.Ping
        $sts = $ping.Send($address)
        if ($sts -and $sts.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
        {
            return $address
        }
    }

    Write-Error -Message "GetIPv4ViaPowerCLI: No IPv4 address found on any NICs for VM ${vmName}" -Category ObjectNotFound -ErrorAction SilentlyContinue
    return $null
}

function MakeSnapshot([String] $vmName, [String] $hostID, [String] $snapshotName)
{
    Get-VMHost -Name $hostID | Get-VM -Name $vmName | New-Snapshot -Name $snapshotName -WarningAction SilentlyContinue
    if ( $? -ne $true )
    {
        write-host "Error: makeSnapshot - new snapshot $snaphostName failed"
        return $false
    }

    $vmSnapshot = Get-VMHost -Name $hostID | Get-VM -Name $vmName | Get-Snapshot
    if ( $vmSnapshot.Name -eq $snapshotName )
    {
        write-host "Info: makeSnapshot - $vmName create $snapshotName successfully"
        return $true
    }
    else
    {
        write-host "Error: makeSnapshot - $vmName create $snapshotName failed, actual is $($vmSnapshot.Name)"
        return $false
    }
}

function WaitForVMStart([String] $vmName, [String] $hostID)
{
    write-host "Info: Check $vmName status"
    $timeout = 300
    while ($timeout -gt 0)
    {
        $vmOut = Get-VMHost -Name $hostID | Get-VM -Name $vmName
        if ( $vmOut.PowerState -eq "PoweredOn")
        {
            $ipv4 = GetIPv4ViaPowerCLI -vmName $vmName -hostID $hostID
            if ($ipv4)
            {
                write-host "Info: VM IP is $ipv4"
                return $true
            }
            else
            {
                write-host "Info: Get IP of $vmName is NULL"
                start-sleep -seconds 60
                $timeout -= 60
            }
        }
    }

    if ($timeout -eq 0)
    {
        write-host "Info: Check $vmName installation timeout(30min)"
        return $false
    }
}

function TestPort ([String] $serverName, [Int] $port=22, [Int] $to=600)
{
    <#
    .Synopsis
        Check to see if a specific TCP port is open on a server.
    .Description
        Try to create a TCP connection to a specific port (22 by default)
        on the specified server. If the connect is successful return
        true, false otherwise.
    .Parameter Host
        The name of the host to test
    .Parameter Port
        The port number to test. Default is 22 if not specified.
    .Parameter Timeout
        Timeout value in seconds
    .Example
        Test-Port $serverName
    .Example
        Test-Port $serverName -port 22 -timeout 5
    #>

    $timeout = $to * 1000

    # Try an async connect to the specified machine/port
    $tcpclient = new-Object system.Net.Sockets.TcpClient
    $iar = $tcpclient.BeginConnect($serverName,$port,$null,$null)

    # Wait for the connect to complete. Also set a timeout
    # so we don't wait all day
    $connected = $iar.AsyncWaitHandle.WaitOne($timeout,$false)

    # Check to see if the connection is done
    if($connected)
    {
        Write-Host "Info: Port $port got avaliable now."
        # Close our connection
        try
        {
            $tcpclient.EndConnect($iar) | Out-Null
            Write-Host "Info: TCP connection $iar end now."
        }
        catch
        {
            Write-Host "Info: Cannot end TCP connection $iar."
        }
    }
    else
    {
        Write-Host "Info: Port $port is not avaliable for $to seconds."
    }
    $tcpclient.Close()
    Write-Host "Info: TCP client $tcpclient closed now."
}

function SendCommandToVM([String]$vmIP, [int]$port=22, [String]$sskKey, [String]$command)
{
    $retVal = $false

    $process = Start-Process bin\plink -ArgumentList "-P $port -i $sshKey root@${vmIP} ${command}" -PassThru -NoNewWindow -redirectStandardOutput lisaOut.tmp -redirectStandardError lisaErr.tmp
    $commandTimeout = 30
    while(!$process.hasExited)
    {
        Write-Host "Waiting 1 second to check the process status for Command = '$command'."
        Start-Sleep 1
        $commandTimeout -= 1
        if ($commandTimeout -le 0)
        {
            Write-Host "Killing process for Command = '$command'."
            $process.Kill()
            Write-Host "Error: Send command to VM $vmIP timed out for Command = '$command'"
        }
    }

    if ($commandTimeout -gt 0)
    {
        $retVal = $true
        Write-Host "Success: Successfully sent command to VM. Command = '$command'"
    }

    Remove-Item lisaOut.tmp -ErrorAction "SilentlyContinue"
    Remove-Item lisaErr.tmp -ErrorAction "SilentlyContinue"

    return $retVal
}