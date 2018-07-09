param (
    [CmdletBinding()]
    [String] $action,
    [Switch] $dual,
    [Switch] $gen2,
    [Switch] $esxi
)

if ($dual)
{
    Set-Variable -Name smoke -Value "" -Option constant -Scope Script
    if ($esxi)
    {
        Set-Variable -Name suite -Value "acceptance" -Option constant -Scope Script
        Set-Variable -Name configFile -Value ".\xml\cases.xml" -Option constant -Scope Script
    }
    else
    {
        Set-Variable -Name suite -Value "Functional" -Option constant -Scope Script
    }
    Set-Variable -Name vmName -Value "$env:name-$env:version-$env:release-$env:BUILD_ID" -Option constant -Scope Script
}
else
{
    Set-Variable -Name smoke -Value "-smoke" -Option constant -Scope Script
    if ($esxi)
    {
        Set-Variable -Name suite -Value "acceptance" -Option constant -Scope Script
        Set-Variable -Name configFile -Value ".\xml\esxi-dsk.xml" -Option constant -Scope Script
    }
    else
    {
        Set-Variable -Name suite -Value "Downstream" -Option constant -Scope Script
    }
    Set-Variable -Name vmName -Value "$env:name-$env:version-$env:release-${env:BUILD_ID}${smoke}" -Option constant -Scope Script
}

if ($esxi)
{
    $SecurePassword = $env:VSPHERE_PSW | ConvertTo-SecureString -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $env:VSPHERE_USR, $SecurePassword
}
else
{
    Set-Variable -Name hostFolder -Value "C:\${env:BUILD_ID}${smoke}" -Option constant -Scope Script

    $SecurePassword = $env:DOMAIN_PSW | ConvertTo-SecureString -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $env:DOMAIN_USR, $SecurePassword
}

switch ($action)
{
    "add"
    {
        if ($esxi)
        {
            Set-Location ".\windows"
            .\ESX-Manager $action -dual $dual -name $env:name -version $env:version -release $env:release -image $env:IMAGE -buildID $env:BUILD_ID -gen2 $gen2 -omni_ip $env:OMNI_IP -omni_port $env:API_PORT -omni_user $env:OMNI_USER -hostID $env:HOST_ID -vsphereServer $env:ENVVISIPADDR -vsphereProtocol $env:ENVVISPROTOCOL -credential $cred
            Write-Host "Info: Action ADD exit code: $global:LastExitCode"
        }
        else
        {
            Write-Host "Info: Starting to remove $hostFolder"
            Invoke-Command -computername $env:HOST_ID -Credential $cred -scriptblock {(Test-Path $args[0]) -and (Remove-Item $args[0] -Confirm:$false -recurse -Force)} -ArgumentList $hostFolder

            Write-Host "Info: Starting to copy windows folder from JSlave to $hostFolder on $env:HOST_ID"
            $Session = New-PSSession -ComputerName $env:HOST_ID -Credential $cred
            Copy-Item ".\windows" -Destination $hostFolder -ToSession $Session -Recurse
            Remove-PSSession -Session $Session

            Write-Host "Info: Running HYPERV-Manager on $env:HOST_ID"
            Invoke-Command -computername $env:HOST_ID -Credential $cred -scriptblock `
            { `
                Set-Location $args[0]; `
                .\HYPERV-Manager $args[1] -dual $args[2] -name $args[3] -version $args[4] -release $args[5] -image $args[6] -buildID $args[7] -gen2 $args[8] -omni_ip $args[9] -omni_port $args[10] -omni_user $args[11] `
            } `
            -ArgumentList $hostFolder, $action, $dual, $env:name, $env:version, $env:release, $env:IMAGE, $env:BUILD_ID, $gen2, $env:OMNI_IP, $env:API_PORT, $env:OMNI_USER
        }
    }
    "run"
    {
        if ($esxi)
        {
            $env:ENVVISUSERNAME = $env:VSPHERE_USR
            $env:ENVVISPASSWORD = $env:VSPHERE_PSW
            Write-Host "Info: Running $suite test cases on $env:HOST_ID"
            Set-Location ".\lis"
            .\lisa.ps1 run $configFile -vmName $vmName -hvServer $env:HOST_ID -sshKey demo_id_rsa.ppk -suite $suite -os Linux -dbgLevel 10
            Write-Host "Info: Copying result to root"
            Copy-Item ".\TestResults" -Destination ".." -Recurse -Confirm:$false
        }
        else
        {
            Set-Variable -Name lisa_home -Value ".\lis\WS2012R2\lisa" -Option constant -Scope Script
            Set-Variable -Name vmNameB -Value "$env:name-$env:version-$env:release-$env:BUILD_ID-B" -Option constant -Scope Script
            Copy-Item ".\windows\ssh\3rd_id_rsa.ppk" -Destination "${lisa_home}\ssh\"
            Copy-Item ".\windows\bin\*" -Destination "${lisa_home}\bin\"
            Copy-Item ".\windows\cases.xml" -Destination "${lisa_home}\xml\"

            Write-Host "Info: Starting to copy LISA from JSlave to $hostFolder on $env:HOST_ID"
            $Session = New-PSSession -ComputerName $env:HOST_ID -Credential $cred
            Copy-Item $lisa_home -Destination $hostFolder -ToSession $Session -Recurse
            Remove-PSSession -Session $Session

            Write-Host "Info: Running $suite test cases on $env:HOST_ID"
            Invoke-command -computername $env:HOST_ID -Credential $cred -scriptblock `
            { `
                Set-Location $args[0]; `
                .\lisa run .\xml\cases.xml -vmName $args[1] -hvServer $args[2] -sshKey 3rd_id_rsa.ppk -suite $args[3] -os Linux -dbgLevel 10 -testParams "VM2NAME=${args[4]};SSH_PRIVATE_KEY=id_rsa_private" `
            } `
            -ArgumentList "${hostFolder}\lisa", $vmName, $env:HOST_ID, $suite, $vmNameB

            Write-Host "Info: Copying result back to JSlave"
            $resultDir = "${hostFolder}\lisa\TestResults"
            $Session = New-PSSession -ComputerName $env:HOST_ID -Credential $cred
            Copy-Item $resultDir -Destination ".\" -FromSession $Session -Recurse -Confirm:$false
            Remove-PSSession -Session $Session
        }
    }
    "del"
    {
        if ($esxi)
        {
            Write-Host "Info: Removing VM(s) on $env:HOST_ID"
            Set-Location ".\windows"
            .\ESX-Manager $action -dual $dual -name $env:name -version $env:version -release $env:release -image $env:IMAGE -buildID $env:BUILD_ID -gen2 $gen2 -omni_ip $env:OMNI_IP -omni_port $env:API_PORT -omni_user $env:OMNI_USER -hostID $env:HOST_ID -vsphereServer $env:ENVVISIPADDR -vsphereProtocol $env:ENVVISPROTOCOL -credential $cred
            Write-Host "Info: Action DEL exit code: $global:LastExitCode"
        }
        else
        {
            Write-Host "Info: Removing VM(s) on $env:HOST_ID"
            Invoke-Command -computername $env:HOST_ID -Credential $cred -scriptblock `
            { `
                Set-Location $args[0]; `
                .\HYPERV-Manager $args[1] -dual $args[2] -name $args[3] -version $args[4] -release $args[5] -image $args[6] -buildID $args[7] -Gen2 $args[8] -omni_ip $args[9] -omni_port $args[10] -omni_user $args[11] `
            } `
            -ArgumentList $hostFolder, $action, $dual, $env:name, $env:version, $env:release, $env:IMAGE, $env:BUILD_ID, $gen2, $env:OMNI_IP, $env:API_PORT, $env:OMNI_USER

            Write-Host "Info: Removing $hostFolder on $env:HOST_ID"
            Invoke-Command -ComputerName $env:HOST_ID -Credential $cred -ScriptBlock `
            { `
                Remove-Item $args[0] -Force -Confirm:$false -Recurse `
            } `
            -ArgumentList $hostFolder
        }
    }
    "put"
    {
        Write-Host "Info: Uploading Report.xml to $env:OMNI_IP"
        Copy-Item ".\TestResults\*\Report*.xml" -Destination ".\report-${env:HOST_ID}${smoke}-${env:owner}-${env:id}.xml"
        Write-Output y | windows\bin\pscp -P $env:API_PORT -l $env:OMNI_USER -i windows\ssh\3rd_id_rsa.ppk ".\report-${env:HOST_ID}${smoke}-${env:owner}-${env:id}.xml" ${env:OMNI_IP}:
        Write-Host "Info: Action PUT exit code: $global:LastExitCode"
    }
}
