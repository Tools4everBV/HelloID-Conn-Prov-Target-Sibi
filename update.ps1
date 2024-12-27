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
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
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
        } catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($actionContext.Configuration.Token)")
    $headers.Add('Accept', 'application/json')

    Write-Information 'Verifying if a Sibi account exists'

    try {
        $splatParams = @{
            Uri         = "$($actionContext.Configuration.BaseUrl)/api/employees/get/$($actionContext.References.Account)"
            Method      = 'GET'
            Headers     = $headers
            ContentType = 'application/json'
        }
        $correlatedAccount = (Invoke-RestMethod @splatParams).employee
    } catch {
        $ex = $PSItem
        $errorObj = Resolve-SibiError -ErrorObject $ex
        Write-Information $errorObj.ErrorDetails
        if ($ex.Exception.Response.StatusCode -eq 'NotFound') {
            $correlatedAccount = $null
        } else {
            throw
        }
    }

    $outputContext.PreviousData = $correlatedAccount

    # Always compare the account against the current account in target system
    if ($null -ne $correlatedAccount) {
        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedAccount.PSObject.Properties)
            DifferenceObject = @(($actionContext.Data | Select-Object * -ExcludeProperty department_name, department_code, job_position_name, job_position_code).PSObject.Properties)
        }
        $propertiesChangedObject = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }

        $propertiesChanged = @{}
        $propertiesChangedObject | ForEach-Object { $propertiesChanged[$_.Name] = $_.Value }


        # Separate compare for department property
        if (($correlatedAccount.department.code -ne $actionContext.Data.department_code) -or ($correlatedAccount.department.name -ne $actionContext.Data.department_name)) {
            $propertiesChanged | Add-Member -NotePropertyMembers @{department_code = $actionContext.Data.department_code; department_name = $actionContext.Data.department_name } -PassThru
        }

        # Separate compare for department property
        if (($correlatedAccount.job_position.code -ne $actionContext.Data.job_position_code) -or ($correlatedAccount.job_position.name -ne $actionContext.Data.job_position_name)) {
            $propertiesChanged | Add-Member -NotePropertyMembers @{job_position_code = $actionContext.Data.job_position_code; job_position_name = $actionContext.Data.job_position_name } -PassThru
        }

        if ($propertiesChanged.Count -gt 0) {
            $action = 'UpdateAccount'
        } else {
            $action = 'NoChanges'
        }
    } else {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'UpdateAccount' {
            Write-Information "Account property(s) required to update: $($propertiesChanged.Keys -join ', ')"
            $splatUpdateParams = @{
                Uri         = "$($actionContext.Configuration.BaseUrl)/api/employees/update/by-en/$($correlatedAccount.employee_number)"
                Method      = 'PATCH'
                Headers     = $headers
                Body        =  ($propertiesChanged | ConvertTo-Json -Depth 10)
                ContentType = 'application/json'
            }

            # Make sure to test with special characters and if needed; add utf8 encoding.
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Updating Sibi account with accountReference: [$($actionContext.References.Account)]"
                $null = Invoke-RestMethod @splatUpdateParams

            } else {
                Write-Information "[DryRun] Update Sibi account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.Keys -join ', ')]"
                    IsError = $false
                })
            break
        }

        'NoChanges' {
            Write-Information "No changes to Sibi account with accountReference: [$($actionContext.References.Account)]"

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'No changes will be made to the account during enforcement'
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "Sibi account: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Sibi account with accountReference: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted"
                    IsError = $true
                })
            break
        }
    }
} catch {
    $outputContext.Success  = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-SibiError -ErrorObject $ex
        $auditMessage = "Could not update Sibi account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not update Sibi account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
