# HelloID-Conn-Prov-Target-Sibi

> [!IMPORTANT]  
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/sibi-logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Sibi](#helloid-conn-prov-target-sibi)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Available lifecycle actions](#available-lifecycle-actions)
    - [Field mapping](#field-mapping)
  - [Remarks](#remarks)
    - [Sibi API](#sibi-api)
    - [User Management Limitations](#user-management-limitations)
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

### Prerequisites

Before using this connector, make sure you have the appropriate API key to connect to the API.

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

### Departments and Job Positions

The `departments` and `job_positions` fields in the Sibi API are represented as arrays of objects, which HelloID’s field mapping doesn’t currently support. Therefore, these fields are populated through PowerShell scripts.

- The script determines which contracts are “in scope” by evaluating active contracts and the start date of the primary contract. It processes contracts from both past and future, depending on the current date.
- It then generates department and job position objects from these contracts, ensuring uniqueness, and assigns them to the corresponding user account.
- For each contract, the relevant department and job position details are extracted and stored in arrays, which are then added to the `departments` and `job_positions` fields of the user.
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
