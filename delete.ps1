#####################################################
# HelloID-Conn-Prov-Target-Sibi-Delete
#
# Version: 1.0.1
#####################################################
# Initialize default values
$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false # Set to false at start, at the end, only when no error occurs it is set to true
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# The accountReference object contains the Identification object provided in the create account call
$aRef = $accountReference | ConvertFrom-Json

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Wait for 0,301 seconds - Sibi API allows a maximum of 200 requests a minute (https://app.sibi.nl/api).
Start-Sleep -Milliseconds 301

# Used to connect to Azure AD Graph API
$BaseUrl = $c.BaseUrl
$Token = $c.Token

#region Change mapping here
$account = [PSCustomObject]@{
    # Since we want to be able to grant the access to persons who might not have an active contract, we specify the date of today plus/minus a threshold
    # Make sure to match this to the moment of revoking the account entitlement in the BR, e.g. the start of contract
    'employment_end' = ((Get-Date).AddDays(-30)).ToString('yyyy-MM-dd')
}
#endregion Change mapping here

#region functions
function Resolve-SibiError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = ''
            FriendlyMessage  = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
            $httpErrorObj.FriendlyMessage = ($ErrorObject.ErrorDetails.Message | ConvertFrom-Json).Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -eq $ErrorObject.Exception.Response) {
                $httpErrorObj.ErrorDetails = $ErrorObject.Exception.Message
                $httpErrorObj.FriendlyMessage = $ErrorObject.Exception.Message
            }
            else {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                $httpErrorObj.ErrorDetails = $streamReaderResponse
                $httpErrorObj.FriendlyMessage = ($streamReaderResponse | ConvertFrom-Json).Message
            }
        }
        Write-Output $httpErrorObj
    }
}
#endregion

# Begin
try {
    Write-Verbose 'Adding authorization headers'
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Authorization", "Bearer $($Token)")
    $headers.Add("Accept", "application/json")

    # Verify if Sibi account exists
    try {
        Write-Verbose "Verifying if Sibi account for [$($p.DisplayName)] exists"
        $splatParams = @{
            Uri         = "$($BaseUrl)/api/employees/get/by-en/$aRef"
            Method      = 'GET'
            Headers     = $headers
            ContentType = 'application/json'
        }
        $responseUser = Invoke-RestMethod @splatParams
        if ($responseUser) {
            $action = 'Found'
            $dryRunMessage = "Delete Sibi account for: [$($p.DisplayName)] will be executed during enforcement"
            Write-Verbose $dryRunMessage
        }
    }
    catch {
        $ex = $PSItem
        $errorObj = Resolve-SibiError -ErrorObject $ex
        Write-Verbose $errorObj.ErrorDetails
        if ($ex.Exception.Response.StatusCode -eq 'NotFound') {
            $action = 'NotFound'
            $dryRunMessage = "Sibi account for: [$($p.DisplayName)] not found. Possibily already deleted. Skipping action."
            Write-Verbose $dryRunMessage
        }
        else {
            throw
        }
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning = "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Found' {
                Write-Verbose "Deleting Sibi account with accountReference: [$aRef]"
                $splatParams = @{
                    Uri         = "$($config.BaseUrl)/api/employees/update/by-en/$aRef"
                    Method      = 'PATCH'
                    Headers     = $headers
                    Body        = $account | ConvertTo-Json
                    ContentType = 'application/json'
                }
                $null = Invoke-RestMethod @splatParams
                $auditLogs.Add([PSCustomObject]@{
                        Message = 'Delete account was successful'
                        IsError = $false
                    })
            }

            'NotFound' {
                $auditLogs.Add([PSCustomObject]@{
                        Message = "Sibi account for: [$($p.DisplayName)] not found. Possibily already deleted. Skipping action."
                        IsError = $false
                    })
            }
        }
    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-SibiError -ErrorObject $ex
        $auditMessage = "Could not delete Sibi account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not delete Sibi account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
    # End
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($auditLogs.IsError -contains $true)) {
        $success = $true
    }
    
    # Send results
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $aRef
        AuditLogs        = $auditLogs
        Account          = $account
    }
    Write-Output ($result | ConvertTo-Json -Depth 10)
}