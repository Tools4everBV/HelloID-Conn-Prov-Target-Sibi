#####################################################
# HelloID-Conn-Prov-Target-Sibi-Update
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

# Wait for 0,301 seconds - Sibi API allows a maximum of 100 requests a minute (https://app.sibi.nl/api).
Start-Sleep -Milliseconds 301

# Used to connect to Azure AD Graph API
$BaseUrl = $c.BaseUrl
$Token = $c.Token

#region Change mapping here
# only convert birthdate if it has a value
if (-NOT[String]::IsNullOrEmpty($p.Details.BirthDate)) {
    $birthDate = ([DateTime]$p.Details.BirthDate).ToString('yyyy-MM-dd')
}
else {
    $birthDate = ''
}
$account = [PSCustomObject]@{
    'first_name' = $p.Name.Nickname
    'last_name'  = $p.Name.FamilyName
    'email'      = $p.Contact.Business.Email
    # 'email_private' = $p.Contact.Personal.Email
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

    # Verify if Sibi account exists
    try {
        Write-Verbose "Verifying if Sibi account for [$($p.DisplayName)] exists"
        $splatParams = @{
            Uri         = "$($BaseUrl)/api/employees/get/by-en/$aRef"
            Method      = 'GET'
            Headers     = $headers
            ContentType = 'application/json'
        }
        $currentAccount = Invoke-RestMethod @splatParams
    }
    catch {
        $ex = $PSItem
        $errorObj = Resolve-SibiError -ErrorObject $ex
        Write-Verbose $errorObj.ErrorDetails
        if ($ex.Exception.Response.StatusCode -eq 'NotFound') {
            $currentAccount = $null
        }
        else {
            throw
        }
    }

    # Verify if the account must be updated
    # Always compare the account against the current account in target system
    if ($null -ne $currentAccount) {
        # Because the id is not part of the account object, we need
        # to extract the id value from the currentAccount and set it on the account object.
        $account.department.id = $currentAccount.employee.department.id
        $account.job_position.id = $currentAccount.employee.job_position.id
        $splatCompareProperties = @{
            ReferenceObject  = @($currentAccount.employee.PSObject.Properties)
            DifferenceObject = @($account.PSObject.Properties)
        }
        $propertiesChanged = (Compare-Object @splatCompareProperties -PassThru).Where({ $_.SideIndicator -eq '=>' })
        if ($propertiesChanged) {
            $action = 'Update'
            $dryRunMessage = "Account property(s) required to update: [$($propertiesChanged.name -join ",")]"
        }
        elseif (-not($propertiesChanged)) {
            $action = 'NoChanges'
            $mesdryRunMessageage = 'No changes will be made to the account during enforcement'
        }
    }
    elseif ($null -eq $currentAccount) {
        $action = 'NotFound'
        $dryRunMessage = "Sibi account for: [$($p.DisplayName)] not found. Possibily deleted."
    }
    Write-Verbose $dryRunMessage

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Update' {
                Write-Verbose "Updating Sibi account with accountReference: [$aRef]"
                $body = ($account | ConvertTo-Json)
                $splatParams = @{
                    Uri         = "$($BaseUrl)/api/employees/update/by-en/$aRef"
                    Method      = 'PATCH'
                    Headers     = $headers
                    Body        = ([System.Text.Encoding]::UTF8.GetBytes($body))
                    ContentType = 'application/json'
                }
                # The API only returns 'ok{true}' when an employee is updated
                $null = Invoke-RestMethod @splatParams
                $auditLogs.Add([PSCustomObject]@{
                        Message = 'Update account was successful'
                        IsError = $false
                    })
                break
            }

            'NoChanges' {
                Write-Verbose "No changes to Sibi account with accountReference: [$aRef]"
                $auditLogs.Add([PSCustomObject]@{
                        Message = 'No changes will be made to the account during enforcement'
                        IsError = $false
                    })
                break
            }

            'NotFound' {
                $auditLogs.Add([PSCustomObject]@{
                        Message = "Sibi account for: [$($p.DisplayName)] not found. Possibily deleted."
                        IsError = $true
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
        $auditMessage = "Could not update Sibi account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not update Sibi account. Error: $($ex.Exception.Message)"
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