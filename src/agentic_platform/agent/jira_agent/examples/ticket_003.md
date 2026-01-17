# SUPPORT-4525: API rate limit errors after platform upgrade

**Status:** Open  
**Priority:** Critical  
**Created:** 2024-01-18T11:20:00Z  
**Updated:** 2024-01-18T15:45:00Z  
**Assignee:** Unassigned  
**Reporter:** Alex Thompson  

## Summary

After deploying version 2.15.0, API clients are receiving 429 (Too Many Requests) errors at normal usage levels. Rate limit thresholds appear to have changed unexpectedly, breaking existing integrations.

## Description

Customers report that their API integrations—which worked without issue before the upgrade—are now hitting rate limits and receiving 429 errors. The issue appears system-wide and is affecting multiple integration partners.

**Customer Impact:**
- 8 enterprise customers affected
- ~12,000 failed API requests in the last 4 hours
- Integrations with CRM systems, ticketing systems, and data pipelines are failing

**Observed Patterns:**
- Rate limit errors occur at 40-50% of documented limits
- Errors increase in frequency over time
- Issue persists after client restart

## Environment

- **Service Version:** 2.15.0 (just deployed)
- **Previous Version:** 2.14.3 (working)
- **API Endpoint:** api.support-platform.com
- **Affected Endpoints:** /v2/tickets, /v2/customers, /v2/analytics

## Preliminary Investigation

Rate limiter middleware was modified in 2.15.0 to use a new distributed Redis cache. Configuration appears to have incompatible parameters causing premature throttling.

## Blockers

- Need to determine if this is a configuration issue or code defect
- May need to rollback if unable to fix quickly
- Customer satisfaction at risk

## Labels

`api`, `rate-limiting`, `critical`, `regression`, `post-deployment`

## Related Issues

- DEV-2156: Rate limiter refactoring work
- INFRA-2891: Redis cluster upgrade

---

**Internal Notes:**
> Escalated to on-call engineering lead. Considering immediate rollback to 2.14.3 if root cause not identified within 1 hour.