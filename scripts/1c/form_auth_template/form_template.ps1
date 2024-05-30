$ad_groups = @('1c_admins')
$ad_users = @('bobs')
Import-Module -Name ActiveDirectory

Start-PodeServer {
    Add-PodeEndpoint -Address * -Port 8080 -Protocol Http
    Set-PodeViewEngine -Type Pode

    Enable-PodeSessionMiddleware -Duration 120 -Extend
    New-PodeAuthScheme -Form | Add-PodeAuthWindowsAd -Name 'WinAuth' -Users $ad_users -Groups $ad_groups -FailureUrl 'login' -SuccessUrl '/getuserinfo' 

    New-PodeLoggingMethod -File -Name 'requests' -Path "$PSScriptRoot\logs" -MaxDays 30 -MaxSize 10MB | Enable-PodeRequestLogging
    New-PodeLoggingMethod -File -Name 'error' -Path "$PSScriptRoot\logs" -MaxDays 30 -MaxSize 10MB | Enable-PodeErrorLogging
    
    Add-PodeLimitRule -Type IP -Values all -Limit 10 -Seconds 60

    Add-PodeRoute -Method Get -Path '/getuserinfo' -Authentication 'WinAuth' -ScriptBlock {
        Write-Host "$($WebEvent.Auth.User.Username) has logged in."
        Write-PodeJsonResponse -Value ($WebEvent.Auth.User)
    }
    
    Add-PodeRoute -Method Get -Path '/login' -Authentication 'WinAuth' -Login -ScriptBlock {
        Write-PodeViewResponse -Path 'auth-login' -FlashMessages
    }
    
    Add-PodeRoute -Method Post -Path '/login' -Authentication 'WinAuth' -Login

}
