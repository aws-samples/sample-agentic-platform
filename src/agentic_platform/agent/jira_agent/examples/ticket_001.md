# SUPPORT-4521: Email notifications not sending to distribution lists

**Status:** In Progress  
**Priority:** High  
**Created:** 2024-01-15T10:30:00Z  
**Updated:** 2024-01-18T14:22:00Z  
**Assignee:** Sarah Chen  
**Reporter:** Marcus Johnson  

## Summary

Customers report that email notifications are not being delivered to distribution lists, though individual email addresses work correctly. Issue affects approximately 340 accounts.

## Description

Starting January 12, 2024, email notifications configured to go to distribution lists (e.g., team@company.com) fail silently. No error messages are generated, and the notifications do not appear in logs.

**Steps to Reproduce:**
1. Create a distribution list in Active Directory
2. Configure a support ticket notification rule to use the distribution list
3. Trigger the notification event
4. Observe that distribution list members do not receive the email

**Expected Behavior:** All members of the distribution list receive the notification email

**Actual Behavior:** No emails are delivered to any distribution list members

## Environment

- **Service Version:** 2.14.3
- **Database:** PostgreSQL 13.2
- **Email Service:** SendGrid API v3
- **Affected Regions:** US-East, EU-West

## Root Cause Analysis

Distribution list expansion is failing due to an incompatibility with the updated Active Directory connector module (version 1.8.2).

## Resolution

Update the AD connector to version 1.8.3, which includes a patch for DL expansion.

## Related Issues

- SUPPORT-4489: AD connector upgrade failures
- INFRA-2134: SendGrid rate limiting investigation

## Labels

`email`, `notifications`, `active-directory`, `customer-impacting`

## Attachments

- error_logs_2024-01-12.zip
- distribution_list_test_results.csv