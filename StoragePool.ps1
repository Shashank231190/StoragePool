<#
Script will capture:

1. VDS trace
2. SMPHost trace
3. Mispace
4. PNP trace
5. SpacePort Trace
6. Storport Trace


#>


#region LogsDir
$Dir = "C:\"
$LogsFolder = "Logs" 
$DirLogFolder = $dir + $LogsFolder 
$FullPath = $DirLogFolder + "\"

if (-not(test-path -Path $DirLogFolder)) {
    new-item -Path $Dir -Name $LogsFolder -ItemType Directory
}

$XperfDir = "c:\ToolKit"

#endregion


#region Xperf
[scriptBlock]$xperfStart = {


    "Xperf start"
    $timeStamp = get-date -Format HH_mm_ss
    $XperfKernelETL = "Start_Xperf_" + $timeStamp + "_kernel.etl"
    $XperfKernelETL = $FullPath + $XperfKernelETL
    Set-location -Path $xperfDir
    .\xperf -on PROC_THREAD+LOADER+FLT_IO_INIT+FLT_IO+FLT_FASTIO+FLT_IO_FAILURE+FILENAME+FILE_IO+FILE_IO_INIT+DISK_IO+HARD_FAULTS+DPC+INTERRUPT+CSWITCH+PROFILE+DRIVERS+Latency+DISPATCHER  -stackwalk MiniFilterPreOpInit+MiniFilterPostOpInit+CSwitch+ReadyThread+ThreadCreate+Profile+DiskReadInit+DiskWriteInit+DiskFlushInit+FileCreate+FileCleanup+FileClose+FileRead+FileWrite+FileFlush -BufferSize 4096 -MaxBuffers 4096 -MaxFile 4096 -FileMode Circular -f $XperfKernelETL

    
    


}

[ScriptBlock]$xperfStop = {
    
    $XperfDir = "c:\ToolKit"
    Set-location -Path $xperfDir

    "Stopping Xperf"
    .\Xperf -d $FullPath"Xperf_WaitAnalysis.ETL"
    
}



#endregion

#region Traces

[scriptBlock]$TraceStart = {



    "VDS Trace"
    logman create trace "base_stor_VDS" -ow -o $FullPath"base_stor_VDS.etl" -p `{012F855E-CC34-4DA0-895F-07AF2826C03E`} 0xffffffffffffffff 0xff -nb 16 16 -bs 512 -mode Circular -f bincirc -max 512 -ets
   
    "SMPHost Trace"
    logman create trace "os_smpHost" -ow -o $FullPath"os_smpHost.etl" -p `{6D09BA4F-D4D0-49DD-8BDD-DEB59A33DFA8`} 0xffffffffffffffff 0xff -nb 16 16 -bs 512 -mode Circular -f bincirc -max 512 -ets
    
    "Mispace Trace"
    logman create trace "base_stor_MiSpace" -ow -o $FullPath"base_stor_MiSpace.etl" -p `{9282168F-2432-45F0-B91C-3AF363C149DD`} 0xffffffffffffffff 0xff -nb 16 16 -bs 512 -mode Circular -f bincirc -max 512 -ets

    "SpacePort Trace"
    logman create trace "drivers_storage_SpacePort" -ow -o $FullPath"drivers_storage.etl" -p `{929C083B-4C64-410A-BFD4-8CA1B6FCE362`} 0xffffffffffffffff 0xff -nb 16 16 -bs 512 -mode Circular -f bincirc -max 512 -ets
    
    "PNP Trace"
    logman create trace "minkernel_manifests" -ow -o $FullPath"minkernel_manifests.etl" -p "Microsoft-Windows-Kernel-PnP" 0xffffffffffffffff 0xff -nb 16 16 -bs 512 -mode Circular -f bincirc -max 512 -ets
    logman update trace "minkernel_manifests" -p "Microsoft-Windows-Kernel-PnPConfig" 0xffffffffffffffff 0xff -ets
    
    "Storport Trace"
    logman create trace "storport" -ow -o $FullPath"storport.etl" -p "Microsoft-Windows-StorPort" 0xffffffffffffffff 0xff -nb 16 16 -bs 1024 -mode Circular -f bincirc -max 1024 -ets

}

[scriptBlock]$TraceStop = {


    "Stopping VDS Trace"
    logman stop "base_stor_VDS" -ets
    
    "Stopping SMPHost Trace"
    logman stop "os_smpHost" -ets
    
    "Stopping Mispace"
    logman stop "base_stor_MiSpace" -ets

    "Stopping SpacePort Trace"
    logman stop "drivers_storage_SpacePort" -ets
    
    "Stopping PNP Trace"
    logman stop minkernel_manifests -ets


    "Stopping Storport Trace"
    logman.exe stop storport -ets

}




#endRegion

#region StoragePoolJob

$jobStoragePool = {

    param($TraceStop)


    $Dir = "C:\"
    $LogsFolder = "Logs" 
    $DirLogFolder = $dir + $LogsFolder 
    $FullPath = $DirLogFolder + "\"

    [ScriptBlock]$xperfStop = {
    
        $XperfDir = "c:\ToolKit"
        Set-location -Path $xperfDir
        "Stopping Xperf"
        .\Xperf -d   $FullPath"Xperf_WaitAnalysis.ETL"

    }


    try {

        while (1) {
     
            $DiskOffline = get-disk | where-object IsOffline -eq $true
            $vDiskDetached = get-virtualdisk | where-object { $_.OperationalStatus -eq "Detached" }
    
            if ($DiskOffline -or $vDiskDetached) {
    
                .([scriptblock]::create($TraceStop))
                .$xperfStop
                Write-Host "Traces Collected" -ForegroundColor Yellow

                break;
            }
        }

    }
    catch {

        Write-Host "Exception occured jobStoragePool"
        Write-Host $_.Exception.Message -ForegroundColor Green
        Write-Host "Exception occured at line => $($_.InvocationInfo.Line)" -ForegroundColor Red
        .([scriptblock]::create($TraceStop))
        .$xperfStop
    }
    finally {

        

        @{
            disk        = Get-Disk
            virtualDisk = get-virtualdisk
            Job         = get-job -name StoragePoolJob | receive-job -keep
            date        = Get-Date
            TimeZone    = Get-TimeZone
        } | Export-Clixml -Path $FullPath"JobDiag.xml"



    }
}

#endregion

#region main

function get-StoragePoolData($LogPath, $XperfDirPath) {

    try {

        $supressMessage1 = Get-ChildItem -path $LogPath -ErrorAction Stop
        $supressMessage2 = Get-ChildItem -path $XperfDirPath -ErrorAction stop
        
        Write-Host "Starting Traces"
        .$TraceStart
        .$xperfStart

        

        $jobTraces = start-job -ScriptBlock $jobStoragePool -ArgumentList @($TraceStop) -name "StoragePoolJob"
        Write-Host "StoragePoolJob Started.." -ForegroundColor Yellow
       

        do {

            Write-Host "To check status press 1" -ForegroundColor Yellow 
            Write-Host "To stop the traces press 2" -ForegroundColor Yellow 
            $command = read-host "selection option"
            switch ($command) {

                1 { 

                    "Job Name {0} - Job Status {1} " -f $jobTraces.Name, $jobTraces.State
                    Receive-Job -Job $jobTraces -Keep
                    break;

                }

                2 {
                    if ((Get-Job -id $jobTraces.ID).state -eq "Completed") {

                        break;

                    }
                    else {
                        

                        Write-Output "TracesStoppedForceFully" | Out-File -FilePath $FullPath"ForceFullStop.Log"
                        Write-Host "Stopping the traces.." -ForegroundColor yellow

                        .$TraceStop
                        .$xperfStop
                        
                        get-job -name StoragePoolJob | receive-job -Keep
                        get-job -name StoragePoolJob   | Stop-Job
                        break;

                    }
                }

                deafult { "Enter the valid option" }

            }

        }while ($command -ne 2)


        @{
            disk        = Get-Disk
            virtualDisk = get-virtualdisk
            Job         = get-job -name StoragePoolJob | receive-job  
            date        = Get-Date
            TimeZone    = Get-TimeZone
        } | Export-Clixml -Path $FullPath"diag.xml"


        get-job -name StoragePoolJob | remove-job


    }
    catch {
        Write-Host "Exception occured in main function"
        Write-Host $_.Exception.Message -ForegroundColor Green
        Write-Host "Exception occured at line =>  $($_.InvocationInfo.Line)" -ForegroundColor Red
        .$TraceStop
        .$xperfStop
    }
    finally {

        $FinalLogDir = get-date -format "MM_dd_yyyy_HH_mm"
        $nameHost = HOSTNAME.EXE
        $FinalLogDir = $FinalLogDir + "_" + $nameHost
        New-item -Path $FullPath -Name $FinalLogDir -ItemType Directory
        Set-Location -Path $DirLogFolder
        move-item -Path $FullPath"*.*" -Destination $FullPath$FinalLogDir

    }

}


#endregion

get-StoragePoolData -LogPath $DirLogFolder -XperfDirPath $XperfDir
