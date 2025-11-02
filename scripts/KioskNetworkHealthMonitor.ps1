param(
    [Parameter(Mandatory=$true)]
    [string]$KioskId,
    
    [Parameter(Mandatory=$true)]
    [string]$Location
)

# Hardcoded Netlify function endpoint (will not change)
$NetlifyURL = 'https://winnetworkhealthmonitor.netlify.app/.netlify/functions/health-report'

# 函数：获取核心网络适配器的固定信息
function Get-CoreNetworkAdapters {
    # 强制查找三种核心网络适配器
    $CoreAdapters = @()
    
    # 1. 查找有线网卡（排除VMware虚拟网卡）
    $WiredAdapters = Get-NetAdapter | Where-Object { 
        ($_.InterfaceDescription -like "*Ethernet*" -or 
         $_.InterfaceDescription -like "*GbE*" -or 
         $_.InterfaceDescription -like "*PCIe*" -or
         $_.Name -eq "Ethernet") -and
        $_.InterfaceDescription -notlike "*VMware*" -and
        $_.InterfaceDescription -notlike "*Virtual*"
    } | Sort-Object Status -Descending | Select-Object -First 1
    
    # 如果没有找到有线网卡，创建一个虚拟条目
    if (-not $WiredAdapters) {
        $WiredAdapters = [PSCustomObject]@{
            Name = "Ethernet"
            InterfaceDescription = "Wired Network Adapter"
            Status = "Disconnected"
            LinkSpeed = "0 bps"
            InterfaceIndex = -1
        }
    }
    
    # 2. 查找无线网卡
    $WirelessAdapters = Get-NetAdapter | Where-Object { 
        $_.InterfaceDescription -like "*Wireless*" -or 
        $_.InterfaceDescription -like "*Wi-Fi*" -or 
        $_.InterfaceDescription -like "*WLAN*" -or 
        $_.InterfaceDescription -like "*802.11*" -or
        $_.Name -eq "Wi-Fi"
    } | Sort-Object Status -Descending | Select-Object -First 1
    
    # 如果没有找到无线网卡，创建一个虚拟条目
    if (-not $WirelessAdapters) {
        $WirelessAdapters = [PSCustomObject]@{
            Name = "Wi-Fi"
            InterfaceDescription = "Wireless Network Adapter"
            Status = "Disconnected"
            LinkSpeed = "0 bps"
            InterfaceIndex = -2
        }
    }
    
    # 3. 查找OpenVPN适配器
    $OpenVPNAdapters = Get-NetAdapter | Where-Object { 
        ($_.InterfaceDescription -like "*TAP-Windows*" -or 
         $_.InterfaceDescription -like "*TUN*" -or
         $_.Name -like "*OpenVPN*")
    } | Sort-Object Status -Descending | Select-Object -First 1
    
    # 组装核心适配器列表
    $adapters = @($WiredAdapters, $WirelessAdapters, $OpenVPNAdapters)
    
    $CoreAdapterDetails = @()
    foreach ($adapter in $adapters) {
        if ($adapter) {
            # 获取IP地址
            $IPAddress = "No IP"
            $DNSServers = "No DNS"
            $RouteMetric = "N/A"
            
            if ($adapter.InterfaceIndex -gt 0) {
                $IPConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
                $IPAddress = if ($IPConfig) { $IPConfig.IPAddress } else { "No IP" }
                
                $DNSServerList = (Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
                $DNSServers = if ($DNSServerList) { $DNSServerList -join ", " } else { "No DNS" }
                
                # 获取路由跃点数
                $route = Get-NetRoute -InterfaceIndex $adapter.InterfaceIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
                $RouteMetric = if ($route) { $route.RouteMetric } else { "N/A" }
            }
            
            # 判断适配器类型
            $adapterType = if ($adapter.InterfaceDescription -like "*Wireless*" -or 
                              $adapter.InterfaceDescription -like "*Wi-Fi*" -or 
                              $adapter.InterfaceDescription -like "*WLAN*" -or 
                              $adapter.InterfaceDescription -like "*802.11*") {
                "WIFI"
            } elseif ($adapter.InterfaceDescription -like "*Ethernet*" -or 
                     $adapter.InterfaceDescription -like "*GbE*" -or 
                     $adapter.InterfaceDescription -like "*PCIe*") {
                "WIRED"
            } elseif ($adapter.InterfaceDescription -like "*TAP-Windows*" -or 
                     $adapter.InterfaceDescription -like "*TUN*" -or
                     $adapter.Name -like "*OpenVPN*") {
                "OPENVPN"
            } else {
                "OTHER"
            }
            
            $CoreAdapterDetails += [PSCustomObject]@{
                Type = $adapterType
                Name = $adapter.Name
                Description = $adapter.InterfaceDescription
                Status = $adapter.Status
                LinkSpeed = $adapter.LinkSpeed
                IPAddress = $IPAddress
                DNSServers = $DNSServers
                RouteMetric = $RouteMetric
                InterfaceIndex = $adapter.InterfaceIndex
                IsActiveInternet = $false
            }
        }
    }
    
    return $CoreAdapterDetails
}

# 函数：获取详细的网络状态信息
function Get-DetailedNetworkStatus {
    param(
        [string]$ComputerId,
        [string]$SiteLocation
    )

    try {
        # 获取香港时区
        $HKTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId(
            [DateTime]::UtcNow, 
            "China Standard Time"
        )
        
        # 获取核心网络适配器
        $CoreAdapters = Get-CoreNetworkAdapters

        # 方法1：使用路由表确定活动互联网接口
        $DefaultRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | 
                        Where-Object { 
                            $_.NextHop -ne '127.0.0.1' -and 
                            $_.NextHop -ne '::1' -and
                            $_.NextHop -ne '0.0.0.0'
                        } | 
                        Sort-Object RouteMetric

        # 找到真正有效的活动路由
        $ActiveInternetRoute = $DefaultRoutes | Where-Object {
            $adapter = Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue
            $adapter -and $adapter.Status -eq 'Up'
        } | Select-Object -First 1

        # 方法2：测试互联网连通性并测量延迟
        $InternetTestResults = @()
        $TestTargets = @("8.8.8.8", "1.1.1.1", "www.microsoft.com")
        $HasInternet = $false
        $LowestLatency = $null
        
        foreach ($target in $TestTargets) {
            try {
                $pingResult = Test-Connection -ComputerName $target -Count 2 -ErrorAction Stop
                if ($pingResult) {
                    $latency = [math]::Round(($pingResult.ResponseTime | Measure-Object -Average).Average, 2)
                    $InternetTestResults += [PSCustomObject]@{
                        Target = $target
                        Reachable = $true
                        Latency = $latency
                    }
                    $HasInternet = $true
                    
                    if (-not $LowestLatency -or $latency -lt $LowestLatency) {
                        $LowestLatency = $latency
                    }
                }
            }
            catch {
                $InternetTestResults += [PSCustomObject]@{
                    Target = $target
                    Reachable = $false
                    Latency = "N/A"
                }
            }
        }

        # 确定活动互联网适配器
        $ActiveInternetAdapter = $null
        
        if ($ActiveInternetRoute) {
            $ActiveInternetAdapter = $CoreAdapters | Where-Object { 
                $_.InterfaceIndex -eq $ActiveInternetRoute.InterfaceIndex -and
                $_.Status -eq 'Up'
            } | Select-Object -First 1
            
            if ($ActiveInternetAdapter) {
                $ActiveInternetAdapter | Add-Member -NotePropertyName ActiveRouteMetric -NotePropertyValue $ActiveInternetRoute.RouteMetric -Force
            }
        }
        
        if (-not $ActiveInternetAdapter -and $HasInternet) {
            $ActiveInternetAdapter = $CoreAdapters | Where-Object { 
                $_.Status -eq 'Up' -and 
                $_.IPAddress -notlike "169.254.*" -and 
                $_.IPAddress -ne "No IP" -and
                $_.Type -ne "OPENVPN"
            } | Select-Object -First 1
        }

        # 标记活动适配器
        if ($ActiveInternetAdapter -and $ActiveInternetAdapter.Status -eq 'Up') {
            foreach ($adapter in $CoreAdapters) {
                $adapter.IsActiveInternet = ($adapter.InterfaceIndex -eq $ActiveInternetAdapter.InterfaceIndex)
            }
        }

        # 检查OpenVPN连接状态
        $VPNSubnets = @("10.8.0.0/24", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
        $VPNRouteFound = $false
        $VPNSubnetDetected = ""
        $VPNAdapterInfo = $null
        
        foreach ($subnet in $VPNSubnets) {
            $VPNRoute = Get-NetRoute -DestinationPrefix $subnet -ErrorAction SilentlyContinue
            if ($VPNRoute) {
                $VPNRouteFound = $true
                $VPNSubnetDetected = $subnet
                
                $VPNAdapter = $CoreAdapters | Where-Object { $_.Type -eq "OPENVPN" }
                if ($VPNAdapter) {
                    $VPNAdapterInfo = [PSCustomObject]@{
                        Name = $VPNAdapter.Name
                        Description = $VPNAdapter.Description
                        Status = $VPNAdapter.Status
                        IPAddress = $VPNAdapter.IPAddress
                        DNSServers = $VPNAdapter.DNSServers
                    }
                }
                break
            }
        }

        if (-not $VPNRouteFound) {
            $VPNAdapter = $CoreAdapters | Where-Object { $_.Type -eq "OPENVPN" -and $_.Status -eq 'Up' } | Select-Object -First 1
            if ($VPNAdapter -and $VPNAdapter.IPAddress -and $VPNAdapter.IPAddress -ne "No IP" -and $VPNAdapter.IPAddress -notlike "169.254.*") {
                $VPNRouteFound = $true
                $VPNAdapterInfo = [PSCustomObject]@{
                    Name = $VPNAdapter.Name
                    Description = $VPNAdapter.Description
                    Status = $VPNAdapter.Status
                    IPAddress = $VPNAdapter.IPAddress
                    DNSServers = $VPNAdapter.DNSServers
                }
                $VPNSubnetDetected = "detected-by-adapter-ip"
            }
        }

        # 组装详细状态对象
        $DetailedStatus = [PSCustomObject]@{
            Timestamp        = $HKTime.ToString("yyyy-MM-dd HH:mm:ss")
            Device           = $ComputerId
            Location         = $SiteLocation
            CoreAdapters     = $CoreAdapters
            ActiveInternetAdapter = $ActiveInternetAdapter
            InternetConnectivity = [PSCustomObject]@{
                HasInternet = $HasInternet
                TestResults = $InternetTestResults
                LowestLatency = $LowestLatency
            }
            VPNStatus        = [PSCustomObject]@{
                Connected = $VPNRouteFound
                DetectedSubnet = $VPNSubnetDetected
                AdapterInfo = $VPNAdapterInfo
            }
        }

        return $DetailedStatus
    }
    catch {
        Write-Error "Error getting network status: $_"
        return [PSCustomObject]@{
            Timestamp        = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Device           = $ComputerId
            Location         = $SiteLocation
            CoreAdapters     = @()
            ActiveInternetAdapter = $null
            InternetConnectivity = [PSCustomObject]@{
                HasInternet = $false
                TestResults = @()
                LowestLatency = "N/A"
            }
            VPNStatus        = [PSCustomObject]@{
                Connected = $false
                DetectedSubnet = ""
                AdapterInfo = $null
            }
            Error = $_.Exception.Message
        }
    }
}

# 函数：上报状态到Netlify
function Send-HealthReport {
    param(
        [PSCustomObject]$HealthData,
        [string]$EndpointURL
    )

    try {
        $jsonData = $HealthData | ConvertTo-Json -Depth 5 -Compress
        
        $headers = @{
            "Content-Type" = "application/json"
        }

        Write-Host "--- Sending JSON payload to $EndpointURL ---" -ForegroundColor Cyan
        Write-Host $jsonData
        $response = Invoke-RestMethod -Uri $EndpointURL -Method Post -Body $jsonData -Headers $headers -TimeoutSec 30
        
        Write-Host "--- Response from endpoint ---" -ForegroundColor Cyan
        if ($response -is [System.String]) {
            Write-Host $response
        } else {
            $response | ConvertTo-Json -Depth 5
        }
        Write-Host "Status report sent successfully: $($HealthData.Timestamp)" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Failed to send status report: $_"
        return $false
    }
}

# 函数：在控制台显示详细状态
function Show-DetailedStatus {
    param([PSCustomObject]$StatusData)
    
    Write-Host "=== NETWORK STATUS REPORT ===" -ForegroundColor Cyan
    Write-Host "Time: $($StatusData.Timestamp) (Hong Kong Time)"
    Write-Host "Device: $($StatusData.Device)"
    Write-Host "Location: $($StatusData.Location)"
    Write-Host ""
    
    # 显示互联网连通性测试结果
    Write-Host "INTERNET CONNECTIVITY TEST:" -ForegroundColor Yellow
    Write-Host "  Has Internet: $($StatusData.InternetConnectivity.HasInternet)" -ForegroundColor $(if ($StatusData.InternetConnectivity.HasInternet) { "Green" } else { "Red" })
    Write-Host "  Lowest Latency: $(if ($StatusData.InternetConnectivity.LowestLatency) { "$($StatusData.InternetConnectivity.LowestLatency)ms" } else { "N/A" })"
    foreach ($test in $StatusData.InternetConnectivity.TestResults) {
        $color = if ($test.Reachable) { "Green" } else { "Red" }
        Write-Host "  - $($test.Target): " -NoNewline
        Write-Host "$($test.Reachable)" -ForegroundColor $color
        if ($test.Reachable) {
            Write-Host "    Latency: $($test.Latency)ms"
        }
    }
    
    Write-Host ""
    
    # 显示核心网络适配器
    Write-Host "CORE NETWORK ADAPTERS:" -ForegroundColor Yellow
    if ($StatusData.CoreAdapters) {
        foreach ($adapter in $StatusData.CoreAdapters) {
            $statusColor = if ($adapter.Status -eq 'Up') { "Green" } else { "Red" }
            $activeIndicator = if ($adapter.IsActiveInternet) { " [ACTIVE INTERNET]" } else { "" }
            
            Write-Host "  - $($adapter.Type)$activeIndicator" -ForegroundColor $(if ($adapter.IsActiveInternet) { "Green" } else { "White" })
            Write-Host "    Interface: $($adapter.Name)"
            Write-Host "    Status: " -NoNewline
            Write-Host "$($adapter.Status)" -ForegroundColor $statusColor
            Write-Host "    Link Speed: $($adapter.LinkSpeed)"
            Write-Host "    IP Address: $($adapter.IPAddress)"
            Write-Host "    Route Metric: $($adapter.RouteMetric)" -ForegroundColor $(if ($adapter.IsActiveInternet) { "Green" } else { "Gray" })
            Write-Host "    DNS Servers: $($adapter.DNSServers)"
            Write-Host ""
        }
    } else {
        Write-Host "  No core network adapters found" -ForegroundColor Red
    }
    
    # 如果检测到活动适配器，显示确认信息
    if ($StatusData.ActiveInternetAdapter -and $StatusData.ActiveInternetAdapter.Status -eq 'Up') {
        Write-Host "ACTIVE INTERNET CONNECTION DETECTED:" -ForegroundColor Green
        Write-Host "  Using: $($StatusData.ActiveInternetAdapter.Type) - $($StatusData.ActiveInternetAdapter.Name)"
        Write-Host "  IP: $($StatusData.ActiveInternetAdapter.IPAddress)"
        Write-Host "  Route Metric: $($StatusData.ActiveInternetAdapter.ActiveRouteMetric) (Lowest)"
        Write-Host ""
    } elseif ($StatusData.InternetConnectivity.HasInternet) {
        Write-Host "ACTIVE INTERNET CONNECTION:" -ForegroundColor Yellow
        Write-Host "  Internet is available but active adapter could not be determined"
        Write-Host ""
    }
    
    if ($StatusData.Error) {
        Write-Host ""
        Write-Host "ERROR: $($StatusData.Error)" -ForegroundColor Red
    }
    
    Write-Host "=================================" -ForegroundColor Cyan
}

# 主执行逻辑
try {
    Write-Host "Starting Kiosk Network Health Monitor..." -ForegroundColor Yellow
    
    # 获取详细网络状态
    $networkStatus = Get-DetailedNetworkStatus -ComputerId $KioskId -SiteLocation $Location
    
    # 在控制台显示状态
    Show-DetailedStatus -StatusData $networkStatus
    
    # 上报状态到 Netlify（如果提供了 URL）
    if ($NetlifyURL -and $NetlifyURL.Trim() -ne "") {
        Write-Host "Sending report to Netlify..." -ForegroundColor Yellow
        $reportSuccess = Send-HealthReport -HealthData $networkStatus -EndpointURL $NetlifyURL
        if ($reportSuccess) {
            Write-Host "Health report sent to Netlify successfully" -ForegroundColor Green
        } else {
            Write-Warning "Failed to send health report to Netlify"
        }
    } else {
        Write-Warning "Netlify URL not configured, skipping report"
    }
    
    # 返回退出代码
    $isHealthy = $networkStatus.InternetConnectivity.HasInternet -and $networkStatus.VPNStatus.Connected
    Write-Host "Overall Health Status: $(if ($isHealthy) { 'HEALTHY' } else { 'UNHEALTHY' })" -ForegroundColor $(if ($isHealthy) { 'Green' } else { 'Red' })
    exit $(if ($isHealthy) { 0 } else { 1 })
}
catch {
    Write-Error "Script execution failed: $_"
    exit 2
}