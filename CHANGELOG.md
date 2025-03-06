# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com), and this project adheres to [Semantic Versioning](https://semver.org).

## [1.1.0] - 06-03-2025

### Added

- **New Field Mappings**:
  - `departments`: Set to 'None' mapping and populated via script due to the requirement of an array of objects, which HelloID field mapping does not support.
  - `employment_end`: Set to 'Complex' mapping, using a script to calculate the latest end date from active contracts in conditions.
  - `employment_start`: Set to 'Field' mapping, using `PrimaryContract.Custom.OriginalHireDate`.
  - `job_positions`: Set to 'None' mapping and populated via script, as HelloID field mapping cannot handle an array of objects.
  - `phone`: Mapped to the `Contact.Business.Phone.Fixed` field.
  - `phone_mobile`: Set to 'Complex' mapping, converting '06' to '+316' and removing spaces, using `Person.Contact.Business.Phone.Mobile`.
  - `phone_mobile_private`: Set to 'Complex' mapping, converting '06' to '+316' and removing spaces, using `Person.Contact.Personal.Phone.Mobile`.

- **Custom Contract Handling and Field Population departments and job_positions**:
  - Added logic to calculate "contracts in scope" based on the current date and primary contract, handling active contracts as well as contracts from the future or past.
  - Extracted department and job position details from contracts in scope, ensuring unique entries. This data is populated as `departments` and `job_positions`, which is necessary because Sibi requires an array of objects.
  - Implemented logic to skip updates for `departments` and `job_positions` if their values are empty, as per Sibi’s request to never fully clear these fields.

- **Error Logging Enhancements**:
  - Introduced `$actionMessage` for logging script execution steps, improving troubleshooting and error tracking during the script execution.

### Changed

- **Field Mapping Updates**:
  - `first_name`: Now mapped to `nickname` instead of `givenname`.
  - `last_name`: Complex mapping now calculates the last name with prefixes, following naming conventions, rather than using `familyname`.
  - `email`: Now mapped from Active Directory's `mail` field, replacing the HR business email.
  - `birthdate`: Refined the date formatting logic for clarity and accuracy.

- **Logging Improvements**:
  - Replaced all `Write-Verbose` statements with `Write-Information` or `Write-Warning` to ensure consistent and useful log outputs.

### Removed

- **Field Mappings**:
  - `department_code`
  - `department_name`
  - `job_position_code`
  - `job_position_name`

- **Code Cleanup**:
  - Removed debug toggle from configuration files.

### Fixed

- **Dry-Run Mode**:
  - Enhanced dry-run functionality to treat all contracts as "in conditions," with clear warning messages during dry-run scenarios.

- **Code Refinements**:
  - Fixed inconsistencies in log messages across lifecycle actions, ensuring more clarity and uniformity.

## [1.0.0] - 10-12-2024

This is the first official release of _HelloID-Conn-Prov-Target-Sibi_. This release is based on template version _2.0.1_.

### Added

### Changed

### Deprecated

### Removed
