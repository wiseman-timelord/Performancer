# utility.ps1

function Invoke-CPUMonitoring {
    while ($true) {
        $cpuStats = Get-CpuStatistics 

        Clear-Host
        PrintProgramTitle
        
        Write-Host "CPU Name: $($cpuStats.Name)"
        Write-Host "Maximum Threads: $($cpuStats.Threads)"  # Display the number of threads
        Write-Host "Maximum Clock Speed: $($cpuStats.MaxSpeed)MHz"
        Write-Host "Current Clock Speed: $($cpuStats.CurrentSpeed)MHz"
        Write-Host "CPU Usage: $($cpuStats.Usage)%"
        Write-Host ""
        PrintProgramSeparator
        Write-Host "Select; Back = B"
		Write-Host "Refreshing In 5 Seconds..."

        if ([console]::KeyAvailable) {
            $key = [console]::ReadKey($true)
            if ($key.Key -eq "B") {
                break
            }
        }

        Start-Sleep -Seconds 5
    }
    Show-PerformanceMonitorMenu
}

function Get-CpuStatistics {
    $cpuInfo = Get-CimInstance -ClassName Win32_Processor
    $cpuUsage = (Get-Counter -Counter "\Processor(_Total)\% Processor Time").CounterSamples.CookedValue
    $cpuUsageRounded = [math]::Round($cpuUsage, 1)

    return @{
        Name = $cpuInfo.Name
        MaxSpeed = $cpuInfo.MaxClockSpeed
        CurrentSpeed = $cpuInfo.CurrentClockSpeed
        Usage = $cpuUsageRounded
        Threads = $cpuInfo.ThreadCount
    }
}


function Invoke-NETMonitoring {
    while ($true) {
        # Fetch stats before clearing the screen
        $networkStats = Get-NetworkStatistics
        $netAdapters = Get-NetAdapter | Where-Object Status -eq 'Up'

        Clear-Host
        PrintProgramTitle

        foreach ($adapter in $netAdapters) {
            Write-Host "NIC Name: $($adapter.InterfaceDescription)"
            Write-Host "Status: Up"
            Write-Host "Speed: $($adapter.LinkSpeed)"
            Write-Host "IPv4 Address: $(($adapter | Get-NetIPAddress -AddressFamily IPv4).IPAddress)"
            Write-Host "Download Rate: $($networkStats.InRate) KB/s"
            Write-Host "Upload Rate: $($networkStats.OutRate) KB/s"
            Write-Host "Discards Total: $($networkStats.Discards)"
            Write-Host "Errors Total: $($networkStats.Errors)"
            Write-Host ""
        }

        if (-not $netAdapters) {
            Write-Host "No active network adapters found."
        }

        PrintProgramSeparator
        Write-Host "Select; Back = B"
		Write-Host "Refreshing In 5 Seconds..."

        if ([console]::KeyAvailable -and ([console]::ReadKey().Key -eq "B")) {
            [console]::ReadKey($true)
            break
        }

        Start-Sleep -Seconds 5
    }
    Show-PerformanceMonitorMenu
}

function Get-NetworkStatistics {
    $networkInterface = Get-NetAdapterStatistics | Select-Object -First 1
    if ($networkInterface -eq $null) {
        return @{
            InRate = 0
            OutRate = 0
            Discards = 0
            Errors = 0
        }
    }

    $currentInbound = $networkInterface.ReceivedBytes
    $currentOutbound = $networkInterface.SentBytes
    $inRate = (($currentInbound - $Global:LastInboundBytes_f8m) * 8 / 1024) / 5
    $outRate = (($currentOutbound - $Global:LastOutboundBytes_u4x) * 8 / 1024) / 5
    $Global:LastInboundBytes_f8m = $currentInbound
    $Global:LastOutboundBytes_u4x = $currentOutbound
    $discardsTotal = if ($networkInterface.PacketsReceivedDiscarded) {$networkInterface.PacketsReceivedDiscarded} else {0}
    $errorsTotal = if ($networkInterface.PacketsReceivedErrors) {$networkInterface.PacketsReceivedErrors} else {0}

    return @{
        InRate = [math]::Round($inRate, 1)
        OutRate = [math]::Round($outRate, 1)
        Discards = $discardsTotal
        Errors = $errorsTotal
    }
}

function Get-EventsReport {
    param (
        [ValidateSet("Application", "System")]
        [string]$EventType
    )
    Clear-Host
    PrintProgramTitle
    $eventTypeName = if ($EventType -eq "Application") { "Program" } else { "System" }
    Write-Host "Requesting $eventTypeName Events.."

    $logName = "$EventType"
    $events = Get-WinEvent -LogName $logName -MaxEvents 20 | Select-Object TimeCreated, Id, LevelDisplayName, Message
    Write-Host "..$eventTypeName Events Received.`n"
    Start-Sleep -Seconds 1

    $fileName = if ($EventType -eq "Application") { "ProgramEvents.Log" } else { "SystemEvents.Log" }
    Write-Host "Exporting Report to $fileName.."
    $report = @()
    foreach ($event in $events) {
        $report += "Time: $($event.TimeCreated), ID: $($event.Id), Level: $($event.LevelDisplayName), Message: $($event.Message.split("`n")[0])"
    }
    $report | Out-File -FilePath $fileName -Force
    Write-Host "..$fileName Report Exported.`n"
    Start-Sleep -Seconds 1
    Write-Host "Check Event Report File; Returning To Menu...`n"
    Start-Sleep -Seconds 2
    Show-RecentEventsMenu
}






function Show-Information {
    param ([string]$Type)
    Clear-Host
    PrintProgramTitle
    
    # Start the report check/generation process
    CheckAndGenerateDirectXReport
    
    # Retrieve and populate information from the report
    RetrieveDataFromReportAndPopulateLists

    # Display the information
    Write-Host "$Type Information:"
    if ($Global:infoKeys_5f4.ContainsKey($Type)) {
        foreach ($key in $Global:infoKeys_5f4[$Type]) {
            if ($Global:FetchedInfo_9vb.ContainsKey($key)) {
                Write-Host "${key}: $($Global:FetchedInfo_9vb[$key])"
            }
        }
    } else {
        Write-Host "Error Retrieving $Type Info!"
    }

    Shorter-FunctionsPromptHelper
}

function CheckAndGenerateDirectXReport {
    $reportPath = $Global:reportPath_s9v
    Write-Host "Checking For Report.."
    if (-not (Test-RecentReport -ReportPath $reportPath)) {
        Write-Host "..Retrieving New Report.."
        Invoke-GenerateReport -ReportPath $reportPath
    } else {
        Write-Host "..Using Existing Report.`n"
    }
}

function RetrieveDataFromReportAndPopulateLists {
    $reportPath = $Global:reportPath_s9v
    $content = Get-Content -Path $reportPath -Raw
    $Global:FetchedInfo_9vb.Clear()
    foreach ($type in $Global:infoKeys_5f4.Keys)
        $pattern = GetPatternForType -Type $type
        if ($content -match $pattern) {
            foreach ($key in $Global:infoKeys_5f4[$type]) {
                if ($content -match "${key}: (.*?)`r?`n") {
                    $Global:FetchedInfo_9vb[$key] = $matches[1].Trim()
                }
            }
        }
    }
}

