
# HelloID-Conn-Prov-Target-Sibi

| :warning: Warning |
|:---------------------------|
| Note that this connector is "a work in progress" and therefore not ready to use in your production environment. |

| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Sibi](#helloid-conn-prov-target-sibi)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites)
      - [Creation / correlation process](#creation--correlation-process)
    - [Remarks](#remarks)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Sibi_ is a _target_ connector. Sibi provides a set of REST API's that allow you to programmatically interact with its data. The HelloID connector uses the API endpoints listed in the table below.

| Endpoint       | Description |
| ------------   | ----------- |
| /api/employees | Actions about employees |

The API documentation can be found on: https://app.sibi.dev/api

The HelloID connector consists of the template scripts shown in the following table.

| Action                          | Action(s) Performed                           | Comment   | 
| ------------------------------- | --------------------------------------------- | --------- |
| create.ps1                      | Correlate or create Sibi user                |           |
| update.ps1                      | Update Sibi user                             |           |
| enable.ps1                      | Enable Sibi user                             | There is no enable option, we can only set the startdate to the current date (or earlier)           |
| disable.ps1                     | Disable Sibi user                            | There is no disable option, we can only set the enddate to the current date (or earlier)          |
| delete.ps1                      | Delete Sibi user                             | There is no delete option, we can only set the enddate to the past |

## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description | Mandatory   |
| ------------ | ----------- | ----------- |
| Token     | The token needed to authenticate to the API. This must be extracted from the application | Yes |
| BaseUrl      | The Base URL to the API like: __https://{customer}.sibi.nl/api__ | Yes |
| Update User when correlating and mapped data differs from data in Sibi  | When toggled, the mapped properties will be updated in the create action (not just correlate). | No         |

### Prerequisites

Before using this connector, make sure you have the appropriate API key to connect to the API.

#### Creation / correlation process

A new functionality is the possibility to update the account in the target system during the correlation process. By default, this behavior is disabled. Meaning, the account will only be created or correlated.

You can change this behavior in the `configuration` by setting the enabling `Update User when correlating and mapped data differs from data in Sibi` option.

> Be aware that this might have unexpected implications.

### Remarks

- The `Active` field is currently not being used in the API.
  > We enable or disable users by setting the `employment_start` or `employment_end` field

- When a new user is created, the fields: `department_code department_name job_position_code job_position_name` are mandatory. 
Typically, this data comes from an external system and will be used within Sibi to connector these fields to groups. 

For the connector, we provide the values known to us. 

- Different `[Account]` and `[UpdateAccount]` object.

When a new user is created, the JSON payload is a 'flat' object containing the `department_code department_name job_position_code job_position_name` fields.
The response however is that `department` and `job_position` are both hashtables. This means that, in order to update a user, we have to use a slightly different object that incorporates these hashtables.

- The fields `department.location`, `department.id`, `job_position.function_group` and `job_position.id` can be ignored and set to a `null` value. 
These fields are only used when an external system is integrated with Sibi. 

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/