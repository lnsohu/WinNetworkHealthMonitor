param(
    [Parameter(Mandatory=$true)]
    [string]$KioskId,
    
    [Parameter(Mandatory=$true)]
    [string]$Location,
    
    [Parameter(Mandatory=$false)]
    [ValidateRange(1,5)]
    [int]$ServerID = 1
)

# Email configuration
$EmailConfig = @{
    SmtpServer = "smtp.sina.cn"
    Port = 587
    UseSsl = $true
    From = "michael_lou@sina.cn"
    To = "michael.n.lu@lpstech.com"
    SmtpUser = "michael_lou@sina.cn"
    SmtpPassword = "836a98b32fa05e3d"
}

# 函数：根据ServerID获取目标服务器
function Get-TestTargets {
    param([int]$ServerID)
    
    $baseTargets = @("8.8.8.8", "1.1.1.1")
    
    # 根据ServerID添加对应的域名
    $domainTarget = switch ($ServerID) {
        1 { "avatar.sightai.tech" }
        2 { "avatar2.sightai.tech" }
        3 { "avatar3.sightai.tech" }
        4 { "avatar4.sightai.tech" }
        5 { "avatar5.sightai.tech" }
        default { "avatar.sightai.tech" }
    }
    
    return $baseTargets + $domainTarget
}

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
        [string]$SiteLocation,
        [int]$ServerID
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
        $TestTargets = Get-TestTargets -ServerID $ServerID
        $InternetTestResults = @()
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
            ServerID         = $ServerID
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
            ServerID         = $ServerID
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

# 函数：发送邮件报告
function Send-EmailReport {
    param(
        [PSCustomObject]$NetworkStatus
    )

    try {
        # 创建邮件主题
        $emailSubject = "[$($NetworkStatus.Device)][$($NetworkStatus.Location)] - Network Status Report"
        
        # 获取香港时间用于页脚
        $HKTimeFooter = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId(
            [DateTime]::UtcNow, 
            "China Standard Time"
        ).ToString("yyyy-MM-dd HH:mm:ss")
        
        # 确定活动接口显示文本
        $activeInterfaceText = "No Active Interface"
        if ($NetworkStatus.ActiveInternetAdapter -and $NetworkStatus.ActiveInternetAdapter.Status -eq 'Up') {
            $interfaceType = $NetworkStatus.ActiveInternetAdapter.Type
            if ($interfaceType -eq "WIRED") {
                $activeInterfaceText = "Wired"
            } elseif ($interfaceType -eq "WIFI") {
                $activeInterfaceText = "Wi-Fi"
            } else {
                $activeInterfaceText = $interfaceType
            }
        }

        # 创建纯英文的HTML邮件内容，避免编码问题
        $htmlBody = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Network Status Report</title>
    <style>
        * { 
            margin: 0; 
            padding: 0; 
            box-sizing: border-box; 
        }
        body { 
            font-family: Arial, sans-serif; 
            line-height: 1.6;
            color: #333;
            background: #f5f5f5;
            padding: 10px;
        }
        .container {
            max-width: 100%;
            background: white;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        .header {
            background: #2c3e50;
            color: white;
            padding: 20px 15px;
            text-align: center;
        }
        .header h1 {
            font-size: 18px;
            margin: 0;
            font-weight: 600;
        }
        .header .subtitle {
            font-size: 12px;
            opacity: 0.8;
            margin-top: 5px;
        }
        .content {
            padding: 15px;
        }
        .section {
            margin-bottom: 20px;
            border: 1px solid #e0e0e0;
            border-radius: 8px;
            overflow: hidden;
        }
        .section-header {
            background: #f8f9fa;
            padding: 12px 15px;
            border-bottom: 1px solid #e0e0e0;
            font-weight: 600;
            color: #2c3e50;
            font-size: 14px;
        }
        .section-content {
            padding: 15px;
        }
        .status-badge {
            display: inline-block;
            padding: 4px 10px;
            border-radius: 12px;
            font-size: 11px;
            font-weight: 600;
            margin: 2px;
        }
        .status-up { background: #d4edda; color: #155724; }
        .status-down { background: #f8d7da; color: #721c24; }
        .status-warning { background: #fff3cd; color: #856404; }
        .metric-grid {
            display: flex;
            flex-direction: column;
            gap: 10px;
        }
        .metric-card {
            background: #f8f9fa;
            padding: 12px;
            border-radius: 6px;
            border-left: 4px solid #3498db;
        }
        .metric-value {
            font-size: 16px;
            font-weight: bold;
            color: #2c3e50;
            margin: 5px 0;
        }
        .metric-label {
            font-size: 11px;
            color: #6c757d;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .test-result {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 8px 0;
            border-bottom: 1px solid #f1f3f4;
        }
        .test-result:last-child {
            border-bottom: none;
        }
        .adapter-item {
            background: #f8f9fa;
            padding: 12px;
            margin: 8px 0;
            border-radius: 6px;
            border-left: 4px solid #95a5a6;
        }
        .adapter-active {
            border-left-color: #27ae60;
            background: #e8f5e8;
        }
        .adapter-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 8px;
        }
        .adapter-type {
            font-weight: bold;
            color: #2c3e50;
        }
        .adapter-details {
            font-size: 12px;
            color: #666;
        }
        .adapter-detail-row {
            display: flex;
            justify-content: space-between;
            margin: 3px 0;
        }
        .health-summary {
            display: flex;
            justify-content: space-between;
            text-align: center;
            margin: 15px 0;
            gap: 8px;
        }
        .health-item {
            flex: 1;
            padding: 12px 8px;
            background: #f8f9fa;
            border-radius: 8px;
        }
        .health-value {
            font-size: 16px;
            font-weight: bold;
            margin: 5px 0;
        }
        .health-good { color: #27ae60; }
        .health-bad { color: #e74c3c; }
        .health-warning { color: #f39c12; }
        .footer {
            background: #f8f9fa;
            padding: 12px 15px;
            text-align: center;
            color: #6c757d;
            font-size: 11px;
            border-top: 1px solid #e0e0e0;
        }
        @media (max-width: 480px) {
            .health-summary {
                flex-direction: column;
                gap: 8px;
            }
            .health-item {
                margin-bottom: 0;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Network Status Report</h1>
            <div class="subtitle">$($NetworkStatus.Timestamp) | Device: $($NetworkStatus.Device) | Location: $($NetworkStatus.Location)</div>
        </div>
        
        <div class="content">
            <!-- Health Summary -->
            <div class="health-summary">
                <div class="health-item">
                    <div class="metric-label">Internet</div>
                    <div class="health-value $(if($NetworkStatus.InternetConnectivity.HasInternet) { 'health-good' } else { 'health-bad' })">
                        $(if($NetworkStatus.InternetConnectivity.HasInternet) { 'ONLINE' } else { 'OFFLINE' })
                    </div>
                </div>
                <div class="health-item">
                    <div class="metric-label">VPN</div>
                    <div class="health-value $(if($NetworkStatus.VPNStatus.Connected) { 'health-good' } else { 'health-warning' })">
                        $(if($NetworkStatus.VPNStatus.Connected) { 'CONNECTED' } else { 'DISCONNECTED' })
                    </div>
                </div>
                <div class="health-item">
                    <div class="metric-label">Active Interface</div>
                    <div class="health-value $(if($NetworkStatus.ActiveInternetAdapter) { 'health-good' } else { 'health-warning' })">
                        $activeInterfaceText
                    </div>
                </div>
            </div>

            <!-- Internet Connectivity -->
            <div class="section">
                <div class="section-header">Connectivity Test (Server ID: $($NetworkStatus.ServerID))</div>
                <div class="section-content">
"@

        # 添加互联网测试结果
        foreach ($test in $NetworkStatus.InternetConnectivity.TestResults) {
            $statusIcon = if ($test.Reachable) { "✅" } else { "❌" }
            $latencyDisplay = if ($test.Reachable) { "$($test.Latency)ms" } else { "Timeout" }
            $htmlBody += @"
                    <div class="test-result">
                        <div>
                            <strong>$($test.Target)</strong>
                            <span class="status-badge $(if($test.Reachable) { 'status-up' } else { 'status-down' })">$statusIcon $($test.Reachable)</span>
                        </div>
                        <div>$latencyDisplay</div>
                    </div>
"@
        }

        $htmlBody += @"
                </div>
            </div>

            <!-- Network Adapters -->
            <div class="section">
                <div class="section-header">Network Adapters</div>
                <div class="section-content">
"@

        # 添加网络适配器信息（移动端友好），包含跃点数和DNS信息
        foreach ($adapter in $NetworkStatus.CoreAdapters) {
            $statusClass = if ($adapter.Status -eq 'Up') { 'status-up' } else { 'status-down' }
            $statusText = if ($adapter.Status -eq 'Up') { 'UP' } else { 'DOWN' }
            $adapterClass = if ($adapter.IsActiveInternet) { 'adapter-item adapter-active' } else { 'adapter-item' }
            $activeIndicator = if ($adapter.IsActiveInternet) { ' ★' } else { '' }
            
            $htmlBody += @"
                    <div class="$adapterClass">
                        <div class="adapter-header">
                            <span class="adapter-type">$($adapter.Type)$activeIndicator</span>
                            <span class="status-badge $statusClass">$statusText</span>
                        </div>
                        <div class="adapter-details">
                            <div class="adapter-detail-row">
                                <span>Name:</span>
                                <span>$($adapter.Name)</span>
                            </div>
                            <div class="adapter-detail-row">
                                <span>IP Address:</span>
                                <span>$($adapter.IPAddress)</span>
                            </div>
                            <div class="adapter-detail-row">
                                <span>Link Speed:</span>
                                <span>$($adapter.LinkSpeed)</span>
                            </div>
                            <div class="adapter-detail-row">
                                <span>Route Metric:</span>
                                <span>$($adapter.RouteMetric)</span>
                            </div>
                            <div class="adapter-detail-row">
                                <span>DNS Servers:</span>
                                <span>$($adapter.DNSServers)</span>
                            </div>
                        </div>
                    </div>
"@
        }

        $htmlBody += @"
                </div>
            </div>

            <!-- VPN Status -->
            <div class="section">
                <div class="section-header">VPN Connection</div>
                <div class="section-content">
                    <div class="metric-grid">
                        <div class="metric-card">
                            <div class="metric-label">VPN Status</div>
                            <div class="metric-value $(if($NetworkStatus.VPNStatus.Connected) { 'health-good' } else { 'health-warning' })">
                                $(if($NetworkStatus.VPNStatus.Connected) { 'CONNECTED' } else { 'DISCONNECTED' })
                            </div>
                        </div>
"@

        if ($NetworkStatus.VPNStatus.Connected -and $NetworkStatus.VPNStatus.AdapterInfo) {
            $htmlBody += @"
                        <div class="metric-card">
                            <div class="metric-label">VPN Adapter</div>
                            <div class="metric-value">$($NetworkStatus.VPNStatus.AdapterInfo.Name)</div>
                        </div>
                        <div class="metric-card">
                            <div class="metric-label">VPN IP</div>
                            <div class="metric-value">$($NetworkStatus.VPNStatus.AdapterInfo.IPAddress)</div>
                        </div>
"@
        }

        $htmlBody += @"
                    </div>
                </div>
            </div>
        </div>

        <div class="footer">
            Generated by Network Health Monitor | $HKTimeFooter Hong Kong Time
        </div>
    </div>
</body>
</html>
"@

        # 发送邮件
        $mailParams = @{
            From = $EmailConfig.From
            To = $EmailConfig.To
            Subject = $emailSubject
            Body = $htmlBody
            SmtpServer = $EmailConfig.SmtpServer
            Port = $EmailConfig.Port
            UseSsl = $EmailConfig.UseSsl
            Credential = New-Object System.Management.Automation.PSCredential(
                $EmailConfig.SmtpUser, 
                (ConvertTo-SecureString $EmailConfig.SmtpPassword -AsPlainText -Force)
            )
            BodyAsHtml = $true
            Encoding = [System.Text.Encoding]::UTF8
        }
        
        Send-MailMessage @mailParams
        Write-Host "Email report sent successfully to $($EmailConfig.To)" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to send email report: $($_.Exception.Message)"
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
    Write-Host "Server ID: $($StatusData.ServerID)"
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
    Write-Host "Server ID: $ServerID" -ForegroundColor Yellow
    
    # 获取详细网络状态
    $networkStatus = Get-DetailedNetworkStatus -ComputerId $KioskId -SiteLocation $Location -ServerID $ServerID
    
    # 在控制台显示状态
    Show-DetailedStatus -StatusData $networkStatus
    
    # 发送邮件报告
    Write-Host "Sending email report..." -ForegroundColor Yellow
    $emailSuccess = Send-EmailReport -NetworkStatus $networkStatus
    if ($emailSuccess) {
        Write-Host "Email report sent successfully" -ForegroundColor Green
    } else {
        Write-Warning "Failed to send email report"
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