Import-Module -Name ActiveDirectory
$ad_groups = @('<your-ad-group>')

Start-PodeServer {
################### start
    Add-PodeEndpoint -Address * -Port 8080 -Protocol Http
################### settings
    #enable http views
    Set-PodeViewEngine -Type Pode
    
    #auth
    Enable-PodeSessionMiddleware -Duration 120 -Extend
    New-PodeAuthScheme -Form | Add-PodeAuthWindowsAd -Name 'WinAuth' -Groups $ad_groups -FailureUrl 'login' -SuccessUrl '/admin' 
    #logging
    New-PodeLoggingMethod -File -Name 'requests' -Path "$PSScriptRoot\logs" -MaxDays 30 -MaxSize 10MB | Enable-PodeRequestLogging
    New-PodeLoggingMethod -File -Name 'error' -Path "$PSScriptRoot\logs" -MaxDays 30 -MaxSize 10MB | Enable-PodeErrorLogging
    #limits
    Add-PodeLimitRule -Type IP -Values all -Limit 10 -Seconds 60
    
################### endpoints

    Set-PodeState -Name '1cdata' -Value @{ } | Out-Null

    # ping
    Add-PodeRoute -Method Get -Path '/ping' -ScriptBlock {Write-PodeJsonResponse -Value @{'value' = 'pong'}}
    
    # main page
    Add-PodeRoute -Method Get -Path '/admin' -Authentication 'WinAuth' -ScriptBlock {Write-PodeViewResponse -Path 'admin'}
    
    # 1c-restart page
    Add-PodeRoute -Method Get -Path '/restart-1c' -Authentication 'WinAuth' -ScriptBlock {
        $value = ""
        Lock-PodeObject -ScriptBlock {Restore-PodeState -Path './1cstate.json'}
        $value = (Get-PodeState -Name '1cdata')

        $services = $value."SERVICE_1C_NAME", $value."SERVICE_RAS_NAME"
        $sdata = Get-Service $services
                       
        Write-PodeViewResponse -Path 'restart-1c' -Data @{ "LOG_FILE" = $value."LOG_FILE"; "TEMP_PATH" = $value."TEMP_PATH"; "SERVICE_RAS_NAME" = $value."SERVICE_RAS_NAME";
         "SERVICE_1C_NAME" = $value."SERVICE_1C_NAME"; "CNTX_PATH" = $value."CNTX_PATH"; "PFL_PATH" = $value."PFL_PATH"; "message" = $message; "services" = $sdata}
    }

    # route to restart 1c with clean tmp
    Add-PodeRoute -Method Get -Path '/restart' -Authentication 'WinAuth' -ScriptBlock {
        #get settings from web
        $LOG_FILE = $WebEvent.Query["LOG_FILE"]
        $SERVICE_1C_NAME = $WebEvent.Query["SERVICE_1C_NAME"]
        $SERVICE_RAS_NAME = $WebEvent.Query["SERVICE_RAS_NAME"]
        $TEMP_PATH = $WebEvent.Query["TEMP_PATH"]
        $CNTX_PATH = $WebEvent.Query["CNTX_PATH"]
        $PFL_PATH = $WebEvent.Query["PFL_PATH"]
        # save to json
        Lock-PodeObject -ScriptBlock {
            $value = (Get-PodeState -Name '1cdata')
            $state:1cdata = @{'LOG_FILE' = $LOG_FILE; 'SERVICE_1C_NAME' = $SERVICE_1C_NAME;
                               'SERVICE_RAS_NAME' = $SERVICE_RAS_NAME; 'TEMP_PATH' = $TEMP_PATH;
                               'CNTX_PATH' = $CNTX_PATH; 'PFL_PATH' = $PFL_PATH}
            Save-PodeState -Path './1cstate.json'
        }
        
        #start restarting
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
        #Complete restarting
        Move-PodeResponseUrl -Url '/restart-1c'
    }
    # login page
    Add-PodeRoute -Method Get -Path '/login' -Authentication 'WinAuth' -Login -ScriptBlock {
        Write-PodeViewResponse -Path 'auth-login' -FlashMessages
    }
    # loginning
    Add-PodeRoute -Method Post -Path '/login' -Authentication 'WinAuth' -Login

    Add-PodeRoute -Method Get -Path '/' -Authentication 'WinAuth' -Login -ScriptBlock {
        Write-PodeViewResponse -Path 'admin' -FlashMessages
    }

}


