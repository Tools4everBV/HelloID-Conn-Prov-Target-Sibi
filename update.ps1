#################################################
# HelloID-Conn-Prov-Target-Sibi-Update
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
    $account = [PSCustomObject]$actionContext.Data.PsObject.Copy()

    # Remove properties of account object with null-values
    $account.PsObject.Properties | ForEach-Object {
        # Remove properties with null-values
        if ($_.Value -eq $null) {
            $account.PsObject.Properties.Remove("$($_.Name)")
        }
    }

    # Convert properties of account object with empty string to null-value
    $account.PsObject.Properties | ForEach-Object {
        # Convert properties with empty string to null-value
        if ($_.Value -eq "") {
            $_.Value = $null
        }
    }

    # Verify if [aRef] has a value
    $actionMessage = "verifying account reference"

    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    # Calculate contracts in scope
    $actionMessage = "Calculating contracts in scope"

    $contractsInScope = [System.Collections.ArrayList]@()
    $currentDate = Get-Date

    # Use active contracts
    $contractsInScope = $personContext.Person.Contracts | Where-Object {
        ($_.StartDate -as [datetime]) -le $currentDate -and (($_.EndDate -as [datetime]) -ge $currentDate -or -not $_.EndDate)
    }

    # No active contracts
    if (-not $contractsInScope) {
        if ($personContext.Person.PrimaryContract.StartDate -as [datetime] -gt $currentDate) {
            # Primary contract is in the future, use contracts that are in conditions and not expired
            Write-Information "Primary contract is in the future. Checking contracts in conditions and not expired."
            $contractsInScope = $personContext.Person.Contracts | Where-Object {
                (($actionContext.DryRun -eq $true -or $_.Context.InConditions -eq $true)) -and ($_.EndDate -as [datetime] -ge $currentDate -or -not $_.EndDate)
            }
        }
        elseif ($personContext.Person.PrimaryContract.StartDate -as [datetime] -lt $currentDate) {
            # Primary contract is in the past, use contracts that are in conditions and not started yet
            Write-Information "Primary contract is in the past. Checking contracts in conditions and not started yet."
            $contractsInScope = $personContext.Person.Contracts | Where-Object {
                (($actionContext.DryRun -eq $true -or $_.Context.InConditions -eq $true)) -and $_.StartDate -as [datetime] -le $currentDate
            }
        }
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

    try {
        $actionMessage = "querying account with ID: $($actionContext.References.Account)"

        $splatParams = @{
            Uri         = "$($actionContext.Configuration.BaseUrl)/api/employees/get/$($actionContext.References.Account)"
            Method      = 'GET'
            Headers     = $headers
            ContentType = 'application/json'
        }
        $correlatedAccount = (Invoke-RestMethod @splatParams).employee | Select-Object $account.PsObject.Properties.Name
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

    $actionMessage = "calculating action"

    # Always compare the account against the current account in target system
    if (($correlatedAccount | Measure-Object).count -eq 1) {
        $actionMessage = "comparing current account to mapped properties"

        # Set Previous data (if there are no changes between PreviousData and Data, HelloID will log "update finished with no changes")
        $outputContext.PreviousData = $correlatedAccount.PsObject.Copy()

        $accountSplatCompareProperties = @{
            ReferenceObject  = @($correlatedAccount.PSObject.Properties | Where-Object { $_.Name -in ($account).PSObject.Properties.Name })
            DifferenceObject = @(($account).PSObject.Properties)
        }

        if ($null -ne $accountSplatCompareProperties.ReferenceObject -and $null -ne $accountSplatCompareProperties.DifferenceObject) {
            $accountPropertiesChanged = Compare-Object @accountSplatCompareProperties -PassThru
            $accountOldProperties = $accountPropertiesChanged | Where-Object { $_.SideIndicator -eq "<=" }
            $accountNewProperties = $accountPropertiesChanged | Where-Object { $_.SideIndicator -eq "=>" }
        }

        # Separate compare for departments property
        $departmentsChanged = $false
        $oldDepartments = $correlatedAccount.departments | Where-Object { ($_.code -notIn $account.departments.code) -or ($_.name -notin $account.departments.name) }
        $newDepartments = $account.departments | Where-Object { $_.code -notin $correlatedAccount.departments.code -or $_.name -notin $correlatedAccount.departments.name }
        if ($oldDepartments.Count -gt 0 -or $newDepartments.Count -gt 0) {
            # Ensure we do not entirely clear the departments if no new departments are provided
            if ($newDepartments.Count -eq 0) {
                Write-Warning "Skipping update of departments field. Reason: No new departments provided. Per request, departments should never be entirely cleared."
            }
            else {
                $departmentsChanged = $true
            }
        }

        # Separate compare for job_positions property
        $jobPositionsChanged = $false
        $oldJobPositions = $correlatedAccount.job_positions | Where-Object { ($_.code -notIn $account.job_positions.code) -or ($_.name -notin $account.job_positions.name) }
        $newJobPositions = $account.job_positions | Where-Object { $_.code -notin $correlatedAccount.job_positions.code -or $_.name -notin $correlatedAccount.job_positions.name }
        if ($oldJobPositions.Count -gt 0 -or $newJobPositions.Count -gt 0) {
            # Ensure we do not entirely clear the departments if no new departments are provided
            if ($newJobPositions.Count -eq 0) {
                Write-Warning "Skipping update of departments field. Reason: No new departments provided. Per request, departments should never be entirely cleared."
            }
            else {
                $jobPositionsChanged = $true
            }
        }

        if (@($accountNewProperties).Count -gt 0 -or $departmentsChanged -eq $true -or $jobPositionsChanged -eq $true) {
            # Create custom object with old and new values
            $accountChangedPropertiesObject = [PSCustomObject]@{
                OldValues = @{}
                NewValues = @{}
            }

            # Add the old properties to the custom object with old and new values
            foreach ($accountOldProperty in $accountOldProperties) {
                $accountChangedPropertiesObject.OldValues.$($accountOldProperty.Name) = $accountOldProperty.Value
            }

            # Add the new properties to the custom object with old and new values
            foreach ($accountNewProperty in $accountNewProperties) {
                $accountChangedPropertiesObject.NewValues.$($accountNewProperty.Name) = $accountNewProperty.Value
            }

            # Separate action for departments
            if ($departmentsChanged -eq $true) {
                $accountChangedPropertiesObject.OldValues.departments = $correlatedAccount.departments | Select-Object -Property code, name
                $accountChangedPropertiesObject.NewValues.departments = $account.departments
            }

            # Separate action for job_positions
            if ($jobPositionsChanged -eq $true) {
                $accountChangedPropertiesObject.OldValues.job_positions = $correlatedAccount.job_positions | Select-Object -Property code, name
                $accountChangedPropertiesObject.NewValues.job_positions = $account.job_positions
            }

            Write-Information "Changed properties: $($accountChangedPropertiesObject | ConvertTo-Json)"

            $action = 'UpdateAccount'
        }
        else {
            $action = 'NoChanges'
        }            

        Write-Information "Compared current account to mapped properties. Result: $action"
    }
    elseif (($correlatedAccount | Measure-Object).count -eq 0) {
        $action = 'NotFound'
    }
    elseif (($correlatedAccount | Measure-Object).count -gt 1) {
        $action = 'MultipleFound'
    }

    # Process
    switch ($action) {
        'UpdateAccount' {
            $actionMessage = "updating account with AccountReference: $($actionContext.References.Account | ConvertTo-Json)"

            # Set $outputContext.Data with correlated account (to support getting data for 'None' mapped fields)
            $outputContext.Data = $correlatedAccount.PsObject.Copy()

            # Update $outputContext.Data with updated fields
            foreach ($newValue in $accountChangedPropertiesObject.NewValues.Keys) {
                # Update $outputContext.Data with updated field
                $outputContext.Data | Add-Member -MemberType NoteProperty -Name $newValue -Value $accountChangedPropertiesObject.NewValues.$newValue -Force
            }

            $updateAccountSplatParams = @{
                Uri         = "$($actionContext.Configuration.BaseUrl)/api/employees/update/by-en/$($correlatedAccount.employee_number)"
                Method      = "PATCH"
                Body        = ($accountChangedPropertiesObject.NewValues | ConvertTo-Json -Depth 10)
                Headers     = $headers
                ContentType = 'application/json; charset=utf-8'
                Verbose     = $false
                ErrorAction = "Stop"
            }

            if (-Not($actionContext.DryRun -eq $true)) {
                $updateAccountResponse = Invoke-RestMethod @updateAccountSplatParams

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        # Action  = "" # Optional
                        Message = "Updated account with AccountReference: $($actionContext.References.Account | ConvertTo-Json)."
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would update account with AccountReference: $($actionContext.References.Account | ConvertTo-Json)."
            }

            break
        }

        'NoChanges' {
            $actionMessage = "skipping updating account with AccountReference: $($actionContext.References.Account | ConvertTo-Json)"

            $outputContext.Data = $correlatedAccount.PsObject.Copy()

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    # Action  = "" # Optional
                    Message = "Skipped updating account with AccountReference: $($actionContext.References.Account | ConvertTo-Json). Reason: No changes."
                    IsError = $false
                })

            break
        }

        'NotFound' {
            $actionMessage = "updating account with AccountReference: $($actionContext.References.Account | ConvertTo-Json)"

            # Throw terminal error
            throw "No account found with ID: $($actionContext.References.Account)."

            break
        }

        'MultipleFound' {
            $actionMessage = "updating account with AccountReference: $($actionContext.References.Account | ConvertTo-Json)"

            # Throw terminal error
            throw "Multiple accounts found with ID: $($actionContext.References.Account). Please correct this to ensure the correlation results in a single unique account."

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
}