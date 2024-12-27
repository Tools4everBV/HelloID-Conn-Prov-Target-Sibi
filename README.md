# HelloID-Conn-Prov-Target-Sibi

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/sibi-logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Sibi](#helloid-conn-prov-target-connectorname)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Available lifecycle actions](#available-lifecycle-actions)
    - [Field mapping](#field-mapping)
  - [Remarks](#remarks)
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

| Setting  | Description                                    | Mandatory |
| -------- | ---------------------------------------------- | --------- |
| Token    | The authentication token to connect to the API | Yes       |
| BaseUrl  | The URL to the API                             | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Sibi_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `employee_number`                 |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Available lifecycle actions

The following lifecycle actions are available:

| Action                                  | Description                                                                                |
| --------------------------------------- | ------------------------------------------------------------------------------------------ |
| create.ps1                              | Creates a new account.                                                                     |
| disable.ps1                             | Disables an account, preventing access without permanent removal.                          |
| enable.ps1                              | Enables an account, granting access.                                                       |
| update.ps1                              | Updates the attributes of an account.                                                      |
| configuration.json                      | Contains the connection settings and general configuration for the connector.              |
| fieldMapping.json                       | Defines mappings between person fields and target system person account fields.            |

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

## Remarks

### Sibi API 
- Since the Sibi API [Rate Limiting](https://app.sibi.nl/api#:~:text=valid%20Authorization%20header.-,Rate%20Limiting,-With%20an%20API) allows a maximum of 200 requests a minute, we delay each action by 301 miliseconds.
  > This will only work as correct way to limit the API calls per minute if the `concurrent actions are set to 1`

- The `Active` field is currently not being used in the API.
> We enable or disable users by setting the `employment_start` or `employment_end` field

### Departments and Job positions
- When a new user is created, the fields: `department_code department_name job_position_code job_position_name` are mandatory. 
Typically, this data comes from an external system and will be used within Sibi to connector these fields to groups. 

- The API has multiple ways to set the departments and job positions properties one way is to user the fields: `department_code department_name job_position_code job_position_name` This can be used when you have one department and one job position. The connector is currently based on this.

The other way departments and job positions can be implemented is by using the departments and job_positions arrays. This will likely be used when you have multiple departments or job positions for each person. This can also be implemented in the connector but to get this working you should change the fieldmapping, the create and the update scripts.

when using the array variant The fields `department.location`, `department.id`, `job_position.function_group` and `job_position.id` can be ignored and set to a `null` value. These fields are only used when an external system is integrated with Sibi. 


## Development resources

### API endpoints

The following endpoints are used by the connector

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
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/1145-helloid-provisioning-helloid-conn-prov-target-sibi)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
