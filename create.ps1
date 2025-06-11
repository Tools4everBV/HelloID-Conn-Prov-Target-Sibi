#################################################
# HelloID-Conn-Prov-Target-Sibi-Create
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

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
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            $httpErrorObj.FriendlyMessage = $errorDetailsObject.message
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Define account object
    $account = [PSCustomObject]$actionContext.Data

    # Define properties to query
    $accountPropertiesToQuery = @("id") + $outputContext.Data.PsObject.Properties.Name | Select-Object -Unique

    # Calculate contracts in scope
    $actionMessage = "Calculating contracts in scope"

    $contractsInScope = [System.Collections.ArrayList]@()
    $currentDate = Get-Date

    # Use contracts in conditions
    $contractsInScope = $personContext.Person.Contracts | Where-Object {
        (($actionContext.DryRun -eq $true -or $_.Context.InConditions -eq $true))
    }

    if (-Not($actionContext.DryRun -eq $true)) {
        Write-Information "Contracts in scope: $($contractsInScope.ExternalId -Join ',')"
    }
    else {
        Write-Warning "DryRun: All contracts are treated as being in conditions. Contracts in scope: $($contractsInScope.ExternalId -Join ',')"
    }

    # Create departments and job_positions object containing department and job title details from contracts in scope
    # This is required as the HelloID fieldmapping currently does not support an array with objects
    $actionMessage = "calculating and creating departments and job_positions from contracts in scope"

    $departmentsObject = [System.Collections.ArrayList]@()
    $jobPositionsObject = [System.Collections.ArrayList]@()
    foreach ($contract in $contractsInScope) {
        $departmentObject = @{
            'code' = $contract.Department.ExternalId
            'name' = $contract.Department.DisplayName
        }

        [void]$departmentsObject.Add($departmentObject)

        $jobPositionObject = @{
            'code' = $contract.Title.ExternalId
            'name' = $contract.Title.Name
        }
        
        [void]$jobPositionsObject.Add($jobPositionObject)
    }
    $departmentsObject = $departmentsObject | Select-Object -Unique -Property code, name
    $account | Add-Member -MemberType NoteProperty -Name departments -Value @($departmentsObject) -Force

    $jobPositionsObject = $jobPositionsObject | Select-Object -Unique -Property code, name
    $account | Add-Member -MemberType NoteProperty -Name job_positions -Value @($jobPositionsObject) -Force
    
    $actionMessage = "creating headers"
    
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($actionContext.Configuration.Token)")
    $headers.Add('Accept', 'application/json')

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $actionMessage = "verifying correlation configuration and properties"

        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        $actionMessage = "querying account where [$($correlationField)] = [$($correlationValue)]"

        try {
            $splatParams = @{
                Uri         = "$($actionContext.Configuration.BaseUrl)/api/employees/get/by-en/$($correlationValue)"
                Method      = 'GET'
                Headers     = $headers
                ContentType = 'application/json'
            }
            $correlatedAccount = (Invoke-RestMethod @splatParams).employee | Select-Object $accountPropertiesToQuery
        }
        catch {
            $ex = $PSItem
            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorObj = Resolve-SibiError -ErrorObject $ex
                $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
            }
            else {
                $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
            }
    
            if ($auditMessage -like '*No query results*') {
                $correlatedAccount = $null
            }
            else {
                throw $ex
            }
        }
    }

    $actionMessage = 'calculating action'
    
    if (($correlatedAccount | Measure-Object).count -eq 1) {
        $action = 'CorrelateAccount'
    }
    elseif (($correlatedAccount | Measure-Object).count -eq 0) {
        $action = 'CreateAccount'
    }
    elseif (($correlatedAccount | Measure-Object).count -gt 1) {
        $action = 'MultipleFound'
    }

    # Process
    switch ($action) {
        'CreateAccount' {
            $actionMessage = "creating account with employee_number [$($account.employee_number)]"

            $createAccountSplatParams = @{
                Uri         = "$($actionContext.Configuration.BaseUrl)/api/employees/create"
                Method      = "POST"
                Body        = ($account | ConvertTo-Json -Depth 10)
                Headers     = $headers
                ContentType = 'application/json; charset=utf-8'
                Verbose     = $false
                ErrorAction = "Stop"
            }

            if (-Not($actionContext.DryRun -eq $true)) {
                # The API only returns 'ok{true}' when an employee is created, Another get call is required because of that.
                $createAccountResponse = Invoke-RestMethod @createAccountSplatParams

                $splatParams = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/api/employees/get/by-en/$($correlationValue)"
                    Method      = 'GET'
                    Headers     = $headers
                    ContentType = 'application/json'
                }
                $createdAccount = (Invoke-RestMethod @splatParams).employee

                $outputContext.Data = $createdAccount | Select-Object $accountPropertiesToQuery
                $outputContext.AccountReference = "$($createdAccount.id)"

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        # Action  = "" # Optional
                        Message = "Created account with employee_number [$($account.employee_number)] with AccountReference: $($outputContext.AccountReference | ConvertTo-Json)."
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would create account with employee_number [$($account.employee_number)]."
            }

            break
        }

        'CorrelateAccount' {
            $actionMessage = "correlating to account with AccountReference: $($correlatedAccount.id) on [$($correlationField)] = [$($correlationValue)]"

            $outputContext.AccountReference = "$($correlatedAccount.id)"
            $outputContext.Data = $correlatedAccount | Select-Object $accountPropertiesToQuery

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CorrelateAccount" # Optionally specify a different action for this audit log
                    Message = "Correlated to account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json) on [$($correlationField)] = [$($correlationValue)]."
                    IsError = $false
                })

            $outputContext.AccountCorrelated = $true
        
            break
        }

        'MultipleFound' {
            #region Multiple accounts found
            $actionMessage = "correlating to account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json) on [$($correlationField)] = [$($correlationValue)]"

            # Throw terminal error
            throw "Multiple accounts found where [$($correlationField)] = [$($correlationValue)]. Please correct this so the persons are unique."
        
            break
        }
    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-SibiError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    Write-Warning $warningMessage

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            # Action  = "" # Optional
            Message = $auditMessage
            IsError = $true
        })
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($outputContext.AuditLogs.IsError -contains $true)) {
        $outputContext.Success = $true
    }

    # Check if accountreference is set, if not set, set this with default value as this must contain a value
    if ([String]::IsNullOrEmpty($outputContext.AccountReference) -and $actionContext.DryRun -eq $true) {
        $outputContext.AccountReference = "DryRun: Currently not available"
    }
}