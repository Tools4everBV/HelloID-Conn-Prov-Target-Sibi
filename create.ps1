#####################################################
# HelloID-Conn-Prov-Target-Sibi-Create
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$action = 'create'
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
$account = [PSCustomObject]@{
    # Mandatory fields
    'employee_number'   = $p.ExternalId
    'first_name'        = $p.Name.GivenName
    'last_name'         = $p.Name.FamilyName
    'email'             = $p.Contact.Business.Email
    'birthdate'         = ($p.Details.BirthDate).ToString('yyyy-MM-dd')

    # The fields below are required when creating a new employee in Sibi
    'department_code'   = "$($p.PrimaryContract.Department.DisplayName)1"
    'department_name'   = $p.PrimaryContract.Department.DisplayName
    'job_position_code' = "$($p.primaryContract.Title.Name)1"
    'job_position_name' = $p.primaryContract.Title.Name
}

$updateAccount = [PSCustomObject]@{
    'first_name'        = $p.Name.GivenName
    'last_name'         = $p.Name.FamilyName
    'email'             = $p.Contact.Business.Email
    'birthdate'         = ($p.Details.BirthDate).ToString('yyyy-MM-dd')

    department = [PSCustomObject]@{
        id = $null
        code = "$($p.PrimaryContract.Department.DisplayName)1"
        name = $p.PrimaryContract.Department.DisplayName
        location = $null
    }
    job_position = [PSCustomObject]@{
        id = $null
        code = "$($p.primaryContract.Title.Name)1"
        name = $p.primaryContract.Title.Name
        function_group = $null
    }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Set to true if accounts in the target system must be updated
$updatePerson = $false

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
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -eq $ErrorObject.Exception.Response) {
                $httpErrorObj.ErrorDetails = $ErrorObject.Exception.Message
                $httpErrorObj.FriendlyMessage = $ErrorObject.Exception.Message
            } else {
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
    $headers.Add("Authorization", "Bearer $($config.Token)")
    $headers.Add("Accept", "application/json")

    # Verify if a user must be either [created and correlated], [updated and correlated] or just [correlated]
    try {
        Write-Verbose "Verifying if Sibi account for [$($p.DisplayName)] must be created or correlated"
        $splatParams = @{
            Uri         = "$($config.BaseUrl)/api/employees/get/by-en/$($account.employee_number)"
            Method      = 'GET'
            Headers     = $headers
            ContentType = 'application/json'
        }
        $responseUser = Invoke-RestMethod @splatParams
    } catch {
        $ex = $PSItem
        $errorObj = Resolve-SibiError -ErrorObject $ex
        Write-Verbose $errorObj.ErrorDetails
        if ($ex.Exception.Response.StatusCode -eq 'NotFound'){
            $responseUser = $null
        } else {
            throw
        }
    }

    if (-not($responseUser)){
        $action = 'Create-Correlate'
    } elseif ($updatePerson -eq $true) {
        $action = 'Update-Correlate'
    } else {
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
                $splatParams = @{
                    Uri         = "$($config.BaseUrl)/api/employees/create"
                    Method      = 'POST'
                    Headers     = $headers
                    Body        = $account | ConvertTo-Json
                    ContentType = 'application/json'
                }
                # The API only returns 'ok{true}' when an employee is created
                $null = Invoke-RestMethod @splatParams
                $accountReference = $account.employee_number
                break
            }

            'Update-Correlate' {
                Write-Verbose "Updating and correlating Sibi account"
                $splatParams = @{
                    Uri         = "$($config.BaseUrl)/api/employees/update/by-en/$($responseUser.employee.employee_number)"
                    Method      = 'PATCH'
                    Headers     = $headers
                    Body        = $updateAccount | ConvertTo-Json
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

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Message = "$action account was successful. AccountReference is: [$accountReference]"
                IsError = $false
            })
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-SibiError -ErrorObject $ex
        $auditMessage = "Could not $action Sibi account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not $action Sibi account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
# End
} finally {
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
