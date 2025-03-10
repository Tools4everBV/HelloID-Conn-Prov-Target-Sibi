#################################################
# HelloID-Conn-Prov-Target-Sibi-Enable
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

        if (@($accountNewProperties).Count -gt 0) {
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