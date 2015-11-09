# accountfacts

#### Table of Contents

1. [Overview](#overview)
2. [Module Description - What the module does and why it is useful](#module-description)
3. [Setup - The basics of getting started with accountfacts](#setup)
    * [What accountfacts affects](#what-accountfacts-affects)
    * [Beginning with accountfacts](#beginning-with-accountfacts)
4. [Reference - An under-the-hood peek at what the module is doing and how](#reference)
5. [Limitations - OS compatibility, etc.](#limitations)

## Overview

This puppet 4 module adds structured facts for all user/group information on a linux node (excluding passwords).
This is to aid in a brownfield deployment of a local account management module such as identity or pe_accounts.
Additionally, it could be used as an auditing tool.

## Module Description

This module utilizes the ruby 'etc' library from stdlib to retrieve user & group data rather than system commands.
This hopefully provides a greater breadth of availability across linux platforms.
By creating custom facts, you should be able to identify consistency errors across nodes and better plan for future structured rollout.

## Setup

### What accountfacts affects

It should also be noted that while passwords are not reported, this information could be considered sensetive.
Please use your best judgement and security policies.
This is a read-only module and cannot alter account information.

### Beginning with accountfacts

Add this puppet module to your catalog and you should get the facts on your next puppet run.
Since this module only uses standard ruby libraries, no other steps are needed.

## Reference

This adds the two following structured facts:

- accountfacts_groups
  - Name
  - Gid
- accountfacts_users
  - Name
  - Description
  - Uid
  - Primary Gid
  - Homedir
  - Shell

## Limitations

The user running your puppet agent should have sufficient access.

## Development

1. Fork it
2. Submit a pull request
