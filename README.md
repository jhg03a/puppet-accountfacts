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

This puppet 4 module adds structured facts for all user/group information on a node (excluding passwords).
This is to aid in a brownfield deployment of a local account management module such as identity or pe_accounts.
Additionally, it could be used as an auditing tool.

## Module Description

This module utilizes the ruby 'etc' library from stdlib to retrieve user & group data rather than system commands.
This hopefully provides a greater breadth of availability across *NIX platforms.
Windows is a beast of a different color however, so a series of system calls are used to resolve most of the information.  Since windows isn't POSIX-based, there are a few differences in availability and meaning.
By creating custom facts, you should be able to identify consistency errors across nodes and better plan for future structured rollout.

## Setup

### What accountfacts affects

It should also be noted that while passwords are not reported, this information could be considered sensetive.
Please use your best judgement and security policies.
This is a read-only module and cannot alter account information.

### Beginning with accountfacts

Add this puppet module to your catalog and you should get the facts on your next puppet run.
Since this module only uses standard ruby libraries or windows system calls, no other steps are needed.

## Reference

This adds the two following structured facts:

- accountfacts_groups
  - Name
  - Gid
    - *not present in windows*
  - Members
- accountfacts_users
  - Name
  - Description
  - Uid
    - *user sid in windows*
  - Primary Gid
    - *not present in windows*
  - Homedir
  - Shell
    - *reflects account active/inactive in windows*

## Limitations

The user running your puppet agent should have sufficient access.  If someone has an AIX or Solaris box to test with, let me know how it turned out.  There is a decent chance it will work, but I can't verify it.

## Development

1. Fork it
2. Submit a pull request
