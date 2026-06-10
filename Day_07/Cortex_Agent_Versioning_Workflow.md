# Agent Versioning Workflow

## Agent: AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE

**Database:** SNOWFLAKE_INTELLIGENCE  
**Schema:** AGENTS  
**Owner Role:** CHATHPE_AISOLN_REQ_TABLE_CUSTOM_FR

---

## Version Lifecycle

Cortex Agent versioning uses a commit-based model:

1. A **live version** is the mutable working copy used for development.
2. A **committed version** (e.g., `VERSION$N`) is an immutable snapshot.
3. An **alias** (e.g., `PRODUCTION`) is a pointer to a committed version for stable routing.
4. A **default version** is served when no version is specified in API requests.

---

## Current State

| Version | Alias | Default | Description |
|---------|-------|---------|-------------|
| VERSION$1 | — | No | Original agent creation (2026-05-27) |
| VERSION$2 | PRODUCTION | Yes | First production release (2026-06-10) |

---

## SQL Reference

### View All Versions

```sql
SHOW VERSIONS IN AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE;
```

### Create a New Live Version for Development

```sql
-- Start development from a specific committed version
ALTER AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  CREATE LIVE VERSION FROM VERSION$2;
```

### Modify the Live Version

```sql
-- Example: update the orchestration model
ALTER AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  MODIFY LIVE VERSION
  SET MODEL = 'claude-sonnet-4-6';
```

### Commit the Live Version

```sql
-- Creates the next immutable snapshot (e.g., VERSION$3)
ALTER AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  COMMIT;
```

### Assign the PRODUCTION Alias

```sql
-- Move the production alias to the newly committed version
ALTER AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  MODIFY VERSION VERSION$3 SET ALIAS = production;
```

### Set a New Default Version

```sql
-- Update which version is served when no version is specified
ALTER AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  SET DEFAULT_VERSION = 'VERSION$3';
```

### Rollback to a Previous Version

```sql
-- Point the production alias back to an earlier version
ALTER AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  MODIFY VERSION VERSION$2 SET ALIAS = production;

-- Also update the default if needed
ALTER AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  SET DEFAULT_VERSION = 'VERSION$2';
```

---

## Alias Strategy

| Alias | Purpose | Routing |
|-------|---------|---------|
| `PRODUCTION` | Stable deployment for end users | `?version=production` |

Additional aliases can be added for staging or testing:

```sql
-- Create a staging alias for pre-production testing
ALTER AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  MODIFY VERSION VERSION$3 SET ALIAS = staging;
```

---

## Development Workflow

> **CRITICAL:** The Snowsight UI chat targets the `LIVE` version by default.
> After every COMMIT, you MUST recreate the live version or the UI will error
> with "Version 'live' not found for agent."

```
1. ADD LIVE VERSION FROM LAST
        |
2. Iterate on live version (modify tools, instructions, skills)
        |
3. Test the live version via Snowsight UI or API with ?version=live
        |
4. COMMIT (creates VERSION$N) -- live version is consumed!
        |
5. ADD LIVE VERSION FROM LAST  <-- required to restore UI access
        |
6. Assign 'staging' alias -> test with ?version=staging
        |
7. Move 'production' alias to VERSION$N
        |
8. Update DEFAULT_VERSION to VERSION$N
```

### Post-Commit Checklist

```sql
-- After every COMMIT, run this immediately to keep the Snowsight UI working:
ALTER AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  ADD LIVE VERSION FROM LAST;
```

---

## API Usage

```
-- Target the production alias (recommended for apps)
POST /api/v2/cortex/agent:run
  { "agent": "SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE",
    "version": "production", ... }

-- Target a specific version (for debugging)
  { "version": "VERSION$2", ... }

-- Target the live version (for development)
  { "version": "live", ... }

-- Omit version to use the default
  { "agent": "SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE", ... }
```
