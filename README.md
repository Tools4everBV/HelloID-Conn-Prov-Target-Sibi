# HelloID-Conn-Prov-Target-Sibi

> [!IMPORTANT]  
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Sibi/refs/heads/main/Logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Sibi](#helloid-conn-prov-target-sibi)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Available lifecycle actions](#available-lifecycle-actions)
    - [Field mapping](#field-mapping)
  - [Remarks](#remarks)
    - [Sibi API](#sibi-api)
    - [User Management Limitations](#user-management-limitations)
    - [Best Practice for Setting Start and End Dates](#best-practice-for-setting-start-and-end-dates)
    - [Departments and Job Positions](#departments-and-job-positions)
    - [Handling Null Values in Field Mapping](#handling-null-values-in-field-mapping)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Sibi_ is a _target_ connector. Sibi provides a set of REST API's that allow you to programmatically interact with its data. The HelloID connector uses the API endpoints listed in the table below.

## Getting started

### Requirements

- A valid **API key** to authenticate with the Sibi API.
- A **custom field** called `originalHireDate` in the HelloID person model, mapped to the employee’s original hire date from the source system (e.g. an HR system).  
  _This field is required, as the connector expects it in the fieldMapping. It’s used to populate the `employment_start` field in Sibi, which determines tenure and work anniversaries._
- A **custom field** called `originalDischargeDate` in the HelloID person model, mapped to the employee’s latest end date from the source system.  
  _This field is required, as the connector expects it in the fieldMapping. It’s used to populate the `employment_end` field in Sibi, which controls account deactivation._

### Connection settings

The following settings are required to connect to the API.

| Setting | Description                                    | Mandatory |
| ------- | ---------------------------------------------- | --------- |
| Token   | The authentication token to connect to the API | Yes       |
| BaseUrl | The URL to the API                             | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Sibi_ to a person in _HelloID_.

| Setting                   | Value             |
| ------------------------- | ----------------- |
| Enable correlation        | `True`            |
| Person correlation field  | `ExternalId`      |
| Account correlation field | `employee_number` |

> [!TIP]  
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Available lifecycle actions

The following lifecycle actions are available:

| Action             | Description                                                                                                                                                |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| create.ps1         | Creates a new account.                                                                                                                                     |
| disable.ps1        | Updates an existing account, specifically the `employment_start` and `employment_start` fields, as Sibi uses those to activate or disable accounts itself. |
| enable.ps1         | Updates an existing account, specifically the `employment_start` and `employment_start` fields, as Sibi uses those to activate or disable accounts itself. |
| update.ps1         | Updates the attributes of an account.                                                                                                                      |
| configuration.json | Contains the connection settings and general configuration for the connector.                                                                              |
| fieldMapping.json  | Defines mappings between person fields and target system person account fields.                                                                            |

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

## Remarks

### Sibi API

- The Sibi API enforces [Rate Limiting](https://app.sibi.nl/api#:~:text=valid%20Authorization%20header.-,Rate%20Limiting,-With%20an%20API) with a maximum of 200 requests per minute. To ensure compliance, each action is delayed by 301 milliseconds.
  > This rate limiting mechanism will only function correctly if `concurrent actions` are set to 1.

- The `Active` field is currently not supported by the API.
  > Enabling or disabling users cannot be done via the API. Sibi manages this based on the `employment_start` and `employment_end` fields.

### User Management Limitations

- This connector can only manage users created via the API. It cannot manage accounts created manually. For manually created users, Sibi must first take an action (such as activating or updating the user) before they can be managed via the API. Until Sibi performs this action, the connector cannot handle those accounts.

### Best Practice for Setting Start and End Dates

- The **employment_start** field is best set using a **custom field** that maps to the `originalHireDate` from the source system (HR). This is important because it is used for **tenure tracking**, **work anniversaries**, and **internal Sibi onboarding processes**.
- The **employment_end** field is equally critical, as it is used for **internal Sibi offboarding processes**.
- Ensuring these fields are correctly mapped prevents issues with employment history, recognition programs, and automated onboarding/offboarding workflows within Sibi.
- Setting both values via custom fields mapped from the source system (typically HR) ensures reliable onboarding and offboarding flows within Sibi.

### Departments and Job Positions

The `departments` and `job_positions` fields in the Sibi API are represented as arrays of objects, which HelloID’s field mapping doesn’t currently support. Therefore, these fields are populated through PowerShell scripts.

- The script determines which contracts are "in scope".
- By default, only active contracts are used. If there are no active contracts, and the employee has either already left or is yet to join, the following rules apply:
  - **For employees who are yet to join**: Contracts are used that fall within the Business Rule, where the end date has not been reached yet.
  - **For employees who have already left**: Contracts are used that fall within the Business Rule, with a start date in the past.
- **If the list is empty, nothing will be updated.**
- In dry-run mode, all contracts are considered “in conditions”, allowing for previewing of the data without actual changes.

### Handling Null Values in Field Mapping

- The script automatically filters out any field mappings that are set to `$null`. If a value in the HelloID person model is `$null`, it will also be excluded. If you wish to preserve these values, change the field mapping to complex and return an empty string or a space for `$null` values. This ensures that the script handles the data correctly.

## Development resources

### API endpoints

The following endpoints are used by the connector:

| Endpoint                                     | Description                                  |
| -------------------------------------------- | -------------------------------------------- |
| /api/employees/get/by-en/{employeeNumber}    | Retrieve user information by employee number |
| /api/employees/create                        | Create user                                  |
| /api/employees/get/{id}                      | Retrieve user information by id              |
| /api/employees/update/by-en/{employeeNumber} | Update user                                  |

### API documentation

The API documentation can be found on: [Documentation](https://app.sibi.nl/api)

## Getting help

> [!TIP]  
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]  
> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/1145-helloid-provisioning-helloid-conn-prov-target-sibi)_. 

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
