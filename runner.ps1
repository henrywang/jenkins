param (
    [CmdletBinding()]
    [String] $action,
    [Switch] $dual,
    [Switch] $gen2
)

if ($dual)
{
    Set-Variable -Name smoke -Value "" -Option constant -Scope Script
    Set-Variable -Name suite -Value "Functional" -Option constant -Scope Script
    Set-Variable -Name vmName -Value "$name-$version-$release-${env:BUILD_ID}" -Option constant -Scope Script
}
else
{
    Set-Variable -Name smoke -Value "-smoke" -Option constant -Scope Script
    Set-Variable -Name suite -Value "downstream" -Option constant -Scope Script
    Set-Variable -Name vmName -Value "$name-$version-$release-${env:BUILD_ID}${smoke}" -Option constant -Scope Script
}

Set-Variable -Name hostFolder -Value "C:\${env:BUILD_ID}${smoke}\" -Option constant -Scope Script

$SecurePassword = $env:DOMAIN_PSW | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential -ArgumentList $env:DOMAIN_USR, $SecurePassword

switch ($action)
{
    "add"
    {
        Write-Host "Info: Starting to remove $hostFolder"
        Invoke-Command -computername $env:HOST_ID -Credential $cred -scriptblock {(Test-Path $args[0]) -and (Remove-Item $args[0] -Confirm:$false -recurse -Force)} -ArgumentList $hostFolder

        Write-Host "Info: Starting to copy windows folder from JSlave to $hostFolder on $env:HOST_ID"
        $Session = New-PSSession -ComputerName $env:HOST_ID -Credential $cred
        Copy-Item ".\windows" -Destination $hostFolder -ToSession $Session -Recurse
        Remove-PSSession -Session $Session

        Write-Host "Info: Running VM-Manager on $env:HOST_ID"
        Invoke-Command -computername $env:HOST_ID -Credential $cred -scriptblock `
        { `
            Set-Location $args[0]; `
            .\VM-Manager $args[1] -dual $args[2] -name $args[3] -version $args[4] -release $args[5] -image $args[6] -buildID $args[7] -Gen2 $args[8] -omni_ip $args[9] -omni_port $args[10] -omni_user $args[11] `
        } `
        -ArgumentList $hostFolder, $action, $dual, $env:name, $env:version, $env:release, $env:IMAGE, $env:BUILD_ID, $gen2, $env:OMNI_IP, $env:API_PORT, $env:OMNI_USER
    }
    "run"
    {
        Set-Variable -Name lisa_home -Value ".\lis\WS2012R2\lisa" -Option constant -Scope Script
        Set-Variable -Name vmNameB -Value "$name-$version-$release-${env:BUILD_ID}-B" -Option constant -Scope Script
        Copy-Item ".\windows\ssh\3rd_id_rsa.ppk" -Destination "${lisa_home}\ssh\"
        Copy-Item ".\windows\bin\*" -Destination "${lisa_home}\bin\"

        Write-Host "Info: Starting to copy LISA from JSlave to $hostFolder on $env:HOST_ID"
        $Session = New-PSSession -ComputerName $env:HOST_ID -Credential $cred
        Copy-Item "${lisa_home}\*" -Destination $hostFolder -ToSession $Session -Recurse
        Remove-PSSession -Session $Session

        Write-Host "Info: Running $suite test cases on $env:HOST_ID"
        Invoke-command -computername $env:HOST_ID -Credential $cred -scriptblock `
        { `
            Set-Location $args[0]; `
            .\lisa run .\xml\cases.xml -vmName $args[1] -hvServer $args[2] -sshKey 3rd_id_rsa.ppk -suite $args[3] -os Linux -dbgLevel 10 -testParams "VM2NAME=${args[4]};SSH_PRIVATE_KEY=id_rsa_private" `
        } `
        -ArgumentList $hostFolder, $vmName, $env:HOST_ID, $suite, $vmNameB

        Write-Host "Info: Copying result back to JSlave"
        $resultDir = "${hostFolder}\TestResults"
        $Session = New-PSSession -ComputerName $env:HOST_ID -Credential $cred
        Copy-Item $resultDir -Destination ".\" -FromSession $Session -Recurse -Confirm:$false
        Remove-PSSession -Session $Session

        # Write-Host "Info: Removing $hostFolder on $env:HOST_ID"
        # Invoke-Command -ComputerName $env:HOST_ID -Credential $cred -ScriptBlock `
        # { `
        #     Remove-Item $args[0] -Force -Confirm:$false -Recurse `
        # } `
        # -ArgumentList $hostFolder
    }
}

