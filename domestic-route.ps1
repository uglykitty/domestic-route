# Adds routes for CN APNIC prefixes through the current default Windows gateway.
# Run from an elevated PowerShell session.

$ErrorActionPreference = 'Stop'

$DelegatedApnicLatestUrl = 'https://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest'
$DelegatedApnicLatestFile = Join-Path $env:TEMP 'delegated-apnic-latest'
$ExtraIpv4Routes = @('10.0.0.0/8')
$ExtraHostName = 'wangguofang.net'
$AddedRouteCount = 0
$FailedRouteCount = 0

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DefaultRoute {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('IPv4', 'IPv6')]
        [string]$AddressFamily
    )

    Get-NetRoute -AddressFamily $AddressFamily |
        Where-Object {
            $_.DestinationPrefix -in @('0.0.0.0/0', '::/0') -and
            $_.NextHop -and
            $_.NextHop -notin @('0.0.0.0', '::')
        } |
        Sort-Object -Property RouteMetric, InterfaceMetric |
        Select-Object -First 1
}

function Get-PrefixLengthFromAddressCount {
    param(
        [Parameter(Mandatory = $true)]
        [uint64]$AddressCount
    )

    return [int](32 - [Math]::Log($AddressCount, 2))
}

function ConvertTo-Ipv4Mask {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 32)]
        [int]$PrefixLength
    )

    $mask = [uint32]0
    if ($PrefixLength -gt 0) {
        $mask = [uint32]::MaxValue -shl (32 - $PrefixLength)
    }

    return @(
        ($mask -shr 24) -band 0xff
        ($mask -shr 16) -band 0xff
        ($mask -shr 8) -band 0xff
        $mask -band 0xff
    ) -join '.'
}

function Add-Ipv4RouteFast {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationPrefix,

        [Parameter(Mandatory = $true)]
        [string]$NextHop,

        [Parameter(Mandatory = $true)]
        [uint32]$InterfaceIndex
    )

    $parts = $DestinationPrefix -split '/'
    $destination = $parts[0]
    $mask = ConvertTo-Ipv4Mask -PrefixLength ([int]$parts[1])

    & route.exe ADD $destination MASK $mask $NextHop IF $InterfaceIndex *> $null
    if ($LASTEXITCODE -eq 0) {
        $script:AddedRouteCount++
    }
    else {
        $script:FailedRouteCount++
    }
}

function Add-Ipv6RouteFast {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationPrefix,

        [Parameter(Mandatory = $true)]
        [string]$NextHop,

        [Parameter(Mandatory = $true)]
        [uint32]$InterfaceIndex
    )

    & route.exe ADD -6 $DestinationPrefix $NextHop IF $InterfaceIndex *> $null
    if ($LASTEXITCODE -eq 0) {
        $script:AddedRouteCount++
    }
    else {
        $script:FailedRouteCount++
    }
}

if (-not (Test-IsAdministrator)) {
    throw 'This script must be run as Administrator because it modifies the Windows route table.'
}

Write-Host "Updating APNIC delegated file at $DelegatedApnicLatestFile ..."
if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    & curl.exe -L -z $DelegatedApnicLatestFile -o $DelegatedApnicLatestFile $DelegatedApnicLatestUrl
}
else {
    Invoke-WebRequest -Uri $DelegatedApnicLatestUrl -OutFile $DelegatedApnicLatestFile -UseBasicParsing
}

$ipv4DefaultRoute = Get-DefaultRoute -AddressFamily IPv4
$ipv6DefaultRoute = Get-DefaultRoute -AddressFamily IPv6
$delegatedLines = Get-Content -Path $DelegatedApnicLatestFile

if ($ipv4DefaultRoute) {
    Write-Host "IPv4 default route: via $($ipv4DefaultRoute.NextHop), if $($ipv4DefaultRoute.InterfaceIndex)"

    try {
        $hostAddress = Resolve-DnsName -Name $ExtraHostName -Type A -ErrorAction Stop |
            Where-Object { $_.IPAddress } |
            Select-Object -ExpandProperty IPAddress -First 1

        if ($hostAddress) {
            Add-Ipv4RouteFast `
                -DestinationPrefix "$hostAddress/32" `
                -NextHop $ipv4DefaultRoute.NextHop `
                -InterfaceIndex $ipv4DefaultRoute.InterfaceIndex
        }
    }
    catch {
        Write-Warning "Failed to resolve $ExtraHostName A record. $($_.Exception.Message)"
    }

    foreach ($prefix in $ExtraIpv4Routes) {
        Add-Ipv4RouteFast `
            -DestinationPrefix $prefix `
            -NextHop $ipv4DefaultRoute.NextHop `
            -InterfaceIndex $ipv4DefaultRoute.InterfaceIndex
    }

    $delegatedLines |
        Where-Object { $_ -like 'apnic|CN|ipv4|*' } |
        ForEach-Object {
            $fields = $_ -split '\|'
            $prefixLength = Get-PrefixLengthFromAddressCount -AddressCount ([uint64]$fields[4])
            "$($fields[3])/$prefixLength"
        } |
        ForEach-Object {
            Add-Ipv4RouteFast `
                -DestinationPrefix $_ `
                -NextHop $ipv4DefaultRoute.NextHop `
                -InterfaceIndex $ipv4DefaultRoute.InterfaceIndex
        }
}
else {
    Write-Warning 'No IPv4 default route was found. Skipping IPv4 route updates.'
}

if ($ipv6DefaultRoute) {
    Write-Host "IPv6 default route: via $($ipv6DefaultRoute.NextHop), if $($ipv6DefaultRoute.InterfaceIndex)"

    $delegatedLines |
        Where-Object { $_ -like 'apnic|CN|ipv6|*' } |
        ForEach-Object {
            $fields = $_ -split '\|'
            "$($fields[3])/$($fields[4])"
        } |
        ForEach-Object {
            Add-Ipv6RouteFast `
                -DestinationPrefix $_ `
                -NextHop $ipv6DefaultRoute.NextHop `
                -InterfaceIndex $ipv6DefaultRoute.InterfaceIndex
        }
}
else {
    Write-Warning 'No IPv6 default route was found. Skipping IPv6 route updates.'
}

Write-Host "Finished adding domestic routes to the active route table. Added: $AddedRouteCount, failed or already existed: $FailedRouteCount."
