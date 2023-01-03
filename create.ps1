#####################################################
# HelloID-Conn-Prov-Target-Sibi-Create
#
# Version: 1.0.1
#####################################################
# Initialize default values
$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false # Set to false at start, at the end, only when no error occurs it is set to true
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Wait for 0,301 seconds - Sibi API allows a maximum of 100 requests a minute (https://app.sibi.nl/api).
Start-Sleep -Milliseconds 301

# Used to connect to Azure AD Graph API
$BaseUrl = $c.BaseUrl
$Token = $c.Token
$updateUserOnCorrelate = $c.updateUserOnCorrelate

#region Change mapping here
# only convert birthdate if it has a value
if (-NOT[String]::IsNullOrEmpty($p.Details.BirthDate)) {
    $birthDate = ([DateTime]$p.Details.BirthDate).ToString('yyyy-MM-dd')
}
else {
    $birthDate = ''
}
$account = [PSCustomObject]@{
    # Mandatory fields
    'employee_number'   = $p.ExternalId
    'first_name'        = $p.Name.Nickname
    'last_name'         = $p.Name.FamilyName
    'email'             = $p.Contact.Personal.Email
    # 'email_private'     = $p.Contact.Personal.Email
    'birthdate'         = $birthDate
    
    # Since we want to be able to grant the access to persons who might not have an active contract, we specify the date of today plus/minus a threshold
    # Make sure to match this to the moment of granting the account entitlement in the BR, e.g. 14 days before start of contract
    'employment_start'  = ((Get-Date).AddDays(14)).ToString('yyyy-MM-dd')

    # The fields below are required when creating a new employee in Sibi
    'department_code'   = "$($p.PrimaryContract.Department.DisplayName)"
    'department_name'   = $p.PrimaryContract.Department.DisplayName
    'job_position_code' = "$($p.primaryContract.Title.Name)"
    'job_position_name' = $p.primaryContract.Title.Name
}

$updateAccount = [PSCustomObject]@{
    'first_name' = $p.Name.Nickname
    'last_name'  = $p.Name.FamilyName
    'email'      = $p.Contact.Personal.Email
    # 'email_private'     = $p.Contact.Personal.Email
    'birthdate'  = $birthDate

    department   = [PSCustomObject]@{
        id       = $null
        code     = "$($p.PrimaryContract.Department.DisplayName)"
        name     = $p.PrimaryContract.Department.DisplayName
        location = $null
    }
    job_position = [PSCustomObject]@{
        id             = $null
        code           = "$($p.primaryContract.Title.Name)"
        name           = $p.primaryContract.Title.Name
        function_group = $null
    }
}
#endregion Change mapping here

# Troubleshooting
# $dryRun = $false

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

    # Verify if a user must be either [created and correlated], [updated and correlated] or just [correlated]
    try {
        Write-Verbose "Verifying if Sibi account for [$($p.DisplayName)] must be created or correlated"
        $splatParams = @{
            Uri         = "$($BaseUrl)/api/employees/get/by-en/$($account.employee_number)"
            Method      = 'GET'
            Headers     = $headers
            ContentType = 'application/json'
        }
        $responseUser = Invoke-RestMethod @splatParams
    }
    catch {
        $ex = $PSItem
        $errorObj = Resolve-SibiError -ErrorObject $ex
        Write-Verbose $errorObj.ErrorDetails
        if ($ex.Exception.Response.StatusCode -eq 'NotFound') {
            $responseUser = $null
        }
        else {
            throw
        }
    }

    if (-not($responseUser)) {
        $action = 'Create-Correlate'
    }
    elseif ($updateUserOnCorrelate -eq $true) {
        $action = 'Update-Correlate'
    }
    else {
        $action = 'Correlate'
    }

    # Add a warning message showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $action Sibi account for: [$($p.DisplayName)], will be executed during enforcement"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Create-Correlate' {
                Write-Verbose "Creating and correlating Sibi account"
                $body = ($account | ConvertTo-Json)
                $splatParams = @{
                    Uri         = "$($BaseUrl)/api/employees/create"
                    Method      = 'POST'
                    Headers     = $headers
                    Body        = ([System.Text.Encoding]::UTF8.GetBytes($body))
                    ContentType = 'application/json'
                }
                # The API only returns 'ok{true}' when an employee is created
                $null = Invoke-RestMethod @splatParams
                $accountReference = $account.employee_number
                break
            }

            'Update-Correlate' {
                Write-Verbose "Updating and correlating Sibi account"
                $body = $updateAccount | ConvertTo-Json
                $splatParams = @{
                    Uri         = "$($BaseUrl)/api/employees/update/by-en/$($responseUser.employee.employee_number)"
                    Method      = 'PATCH'
                    Headers     = $headers
                    Body        = ([System.Text.Encoding]::UTF8.GetBytes($body))
                    ContentType = 'application/json'
                }
                # The API only returns 'ok{true}' when an employee is updated
                $null = Invoke-RestMethod @splatParams
                $accountReference = $responseUser.employee.employee_number
                break
            }

            'Correlate' {
                Write-Verbose "Correlating Sibi account"
                $accountReference = $responseUser.employee.employee_number
                break
            }
        }

        $auditLogs.Add([PSCustomObject]@{
                Message = "$action account was successful. AccountReference is: [$accountReference]"
                IsError = $false
            })
    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-SibiError -ErrorObject $ex
        $auditMessage = "Could not $action Sibi account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not $action Sibi account. Error: $($ex.Exception.Message)"
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

        # Optionally return data for use in other systems
        ExportData       = [PSCustomObject]@{
            employee_number = $account.employee_number
            email           = $account.email
        }
    }
    Write-Output ($result | ConvertTo-Json -Depth 10)
}