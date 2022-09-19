#####################################################
# HelloID-Conn-Prov-Target-Sibi-Update
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
$account = [PSCustomObject]@{
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

    # Verify if Sibi account exists
    try {
        Write-Verbose "Verifying if Sibi account for [$($p.DisplayName)] exists"
        $splatParams = @{
            Uri         = "$($config.BaseUrl)/api/employees/get/by-en/$aRef"
            Method      = 'GET'
            Headers     = $headers
            ContentType = 'application/json'
        }
        $currentAccount = Invoke-RestMethod @splatParams
    } catch {
        $ex = $PSItem
        $errorObj = Resolve-SibiError -ErrorObject $ex
        Write-Verbose $errorObj.ErrorDetails
        if ($ex.Exception.Response.StatusCode -eq 'NotFound'){
            $currentAccount = $null
        } else {
            throw
        }
    }

    # Verify if the account must be updated
    # Always compare the account against the current account in target system
    if ($null -ne $currentAccount){
        # Because the id is not part of the account object, we need
        # to extract the id value from the currentAccount and set it on the account object.
        $account.department.id = $currentAccount.employee.department.id
        $account.job_position.id = $currentAccount.employee.job_position.id
        $splatCompareProperties = @{
            ReferenceObject  = @($currentAccount.employee.PSObject.Properties)
            DifferenceObject = @($account.PSObject.Properties)
        }
        $propertiesChanged = (Compare-Object @splatCompareProperties -PassThru).Where({$_.SideIndicator -eq '=>'})
        if ($propertiesChanged) {
            $action = 'Update'
            $dryRunMessage = "Account property(s) required to update: [$($propertiesChanged.name -join ",")]"
        } elseif (-not($propertiesChanged)){
            $action = 'NoChanges'
            $mesdryRunMessageage = 'No changes will be made to the account during enforcement'
        }
    } elseif ($null -eq $currentAccount) {
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
                $splatParams = @{
                    Uri         = "$($config.BaseUrl)/api/employees/update/by-en/$aRef"
                    Method      = 'PATCH'
                    Headers     = $headers
                    Body        = $account | ConvertTo-Json
                    ContentType = 'application/json'
                }
                # The API only returns 'ok{true}' when an employee is updated
                $null = Invoke-RestMethod @splatParams
                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                        Message = 'Update account was successful'
                        IsError = $false
                    })
                break
            }

            'NoChanges' {
                Write-Verbose "No changes to Sibi account with accountReference: [$aRef]"
                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                        Message = 'No changes will be made to the account during enforcement'
                        IsError = $false
                    })
                break
            }

            'NotFound'{
                $success = $false
                $auditLogs.Add([PSCustomObject]@{
                    Message = "Sibi account for: [$($p.DisplayName)] not found. Possibily deleted."
                    IsError = $true
                })
            }
        }
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-SibiError -ErrorObject $ex
        $auditMessage = "Could not update Sibi account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not update Sibi account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
# End
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Account   = $account
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
