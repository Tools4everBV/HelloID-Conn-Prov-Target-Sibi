
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

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Prerequisites](#Prerequisites)
- [Getting help](#Getting-help)
- [HelloID Docs](#HelloID-docs)

## Introduction

_HelloID-Conn-Prov-Target-Sibi_ is a _target_ connector. Sibi provides a set of REST API's that allow you to programmatically interact with its data. The HelloID connector uses the API endpoints listed in the table below.

| Endpoint       | Description |
| ------------   | ----------- |
| /api/employees | Actions about employees |

## Getting started


### Connection settings

The following settings are required to connect to the API.

| Setting      | Description | Mandatory   |
| ------------ | ----------- | ----------- |
| Token     | The token needed to authenticate to the API. This must be extracted from the application | Yes |
| BaseUrl      | The Base URL to the API like: __https://{customer}.sibi.nl/api__ | Yes |

### Prerequisites

Before using this connector, make sure you have the appropriate API key to connect to the API.

#### Creation / correlation process

A new functionality is the possibility to update the account in the target system during the correlation process. By default, this behavior is disabled. Meaning, the account will only be created or correlated.

You can change this behavior in the `create.ps1` by setting the boolean `$updatePerson` to the value of `$true`.

> Be aware that this might have unexpected implications.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
