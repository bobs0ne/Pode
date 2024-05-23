Start-PodeServer {
################### start
    Add-PodeEndpoint -Address * -Port 8080 -Protocol Http
################### settings
    #enable http views
    Set-PodeViewEngine -Type Pode
    
    Import-Module -Name ActiveDirectory
    #auth
    Enable-PodeSessionMiddleware -Duration 120 -Extend
    New-PodeAuthScheme -Basic | Add-PodeAuthWindowsAd -Name 'WinAuth' -Groups @('1c_admins')
    #logging
    New-PodeLoggingMethod -File -Name 'requests' -Path "$PSScriptRoot\logs" -MaxDays 30 -MaxSize 10MB | Enable-PodeRequestLogging
    New-PodeLoggingMethod -File -Name 'error' -Path "$PSScriptRoot\logs" -MaxDays 30 -MaxSize 10MB | Enable-PodeErrorLogging
    #limits
    Add-PodeLimitRule -Type IP -Values all -Limit 10 -Seconds 60
    
###################


################### endpoints

    #ping
    Add-PodeRoute -Method Get -Path '/ping' -ScriptBlock {Write-PodeJsonResponse -Value @{'value' = 'pong'}}
    #main page
    Add-PodeRoute -Method Get -Path '/admin' -Authentication 'WinAuth' -ScriptBlock {Write-PodeViewResponse -Path 'admin'}

    Add-PodeRoute -Method Get -Path '/restart-1c' -Authentication 'WinAuth' -ScriptBlock {
        $settings = Import-Csv "C:\scripts\Pode\settings.csv" -Delimiter ";"
        $LOG_FILE = $settings.LOG_FILE
        $SERVICE_1C_NAME = $settings.SERVICE_1C_NAME
        $SERVICE_RAS_NAME = $settings.SERVICE_RAS_NAME
        $CNTX_PATH = $settings.CNTX_PATH
        $PFL_PATH = $settings.PFL_PATH 
        $TEMP_PATH = $settings.TEMP_PATH
        
        $services = $SERVICE_1C_NAME, $SERVICE_RAS_NAME
        $sdata = Get-Service $services
                       
        Write-PodeViewResponse -Path 'restart-1c' -Data @{ "LOG_FILE" = $LOG_FILE; "TEMP_PATH" = $TEMP_PATH; "SERVICE_RAS_NAME" = $SERVICE_RAS_NAME;
         "SERVICE_1C_NAME" = $SERVICE_1C_NAME; "CNTX_PATH" = $CNTX_PATH; "PFL_PATH" = $PFL_PATH; "message" = $message; "services" = $sdata}
    }

    Add-PodeRoute -Method Get -Path '/restart' -Authentication 'WinAuth' -ScriptBlock {
        $SERVICE_1C_NAME = $WebEvent.Query["SERVICE_1C_NAME"]
        $SERVICE_RAS_NAME = $WebEvent.Query["SERVICE_RAS_NAME"]
        $LOG_FILE = $WebEvent.Query["LOG_FILE"]
        $TEMP_PATH = $WebEvent.Query["TEMP_PATH"]
        $CNTX_PATH = $WebEvent.Query["CNTX_PATH"]
        $PFL_PATH = $WebEvent.Query["PFL_PATH"]

        $settings = Import-Csv "C:\scripts\Pode\settings.csv" -Delimiter ";"
        $settings.SERVICE_1C_NAME = $SERVICE_1C_NAME
        $settings.SERVICE_RAS_NAME = $SERVICE_RAS_NAME
        $settings.LOG_FILE = $LOG_FILE
        $settings.TEMP_PATH = $TEMP_PATH
        $settings.CNTX_PATH = $CNTX_PATH
        $settings.PFL_PATH = $PFL_PATH
        $settings | Export-Csv "C:\scripts\Pode\settings.csv" -Encoding utf8 -NoTypeInformation -Delimiter ";"
        #Restart
        Add-Content -Path "$TEMP_PATH\$LOG_FILE" "stop  $(Get-Date)"

        Stop-Service -Name $SERVICE_1C_NAME
        Stop-Service -Name $SERVICE_RAS_NAME

        Start-Sleep -Seconds 5

        taskkill /f /im "rphost.exe"
        taskkill /f /im "rmngr.exe"
        taskkill /f /im "ragent.exe"
        taskkill /f /im "ras.exe"

        Start-Sleep -Seconds 5

        Add-Content -Path "$TEMP_PATH\$LOG_FILE" "done stop  $(Get-Date)"
        Add-Content -Path "$TEMP_PATH\$LOG_FILE" "clean temp $(Get-Date)"

        Get-ChildItem $CNTX_PATH -Recurse -Include "snccntx*"  | Remove-Item -Recurse -Force -Confirm:$false
        Get-ChildItem $PFL_PATH -Recurse -Include "*.pfl" | Remove-Item -Force
        Get-ChildItem $TEMP_PATH -Recurse -Include "*.*" -Exclude $LOG_FILE | Remove-Item -Force

        Add-Content -Path "$TEMP_PATH\$LOG_FILE" "done clean temp  $(Get-Date)"
        Add-Content -Path "$TEMP_PATH\$LOG_FILE" "start $(Get-Date)"

        Start-Service -Name $SERVICE_1C_NAME
        Start-Service -Name $SERVICE_RAS_NAME

        Add-Content -Path "$TEMP_PATH\$LOG_FILE" "Service $SERVICE_1C_NAME restarted at $(Get-Date)"
        Write-Host "Restart Complete!"
        #/Restart
        Move-PodeResponseUrl -Url '/restart-1c'
    }
    
    Add-PodeRoute -Method Get -Path '/info' -Authentication 'WinAuth' -ScriptBlock {
        Write-Host $WebEvent.Auth.User.Username
    }
}
