Agent Versioning Workflow

Agent: <your agent name>
Database: <database name>
Schema: <schema name>
Owner Role: <your role>

Version Lifecycle
Cortex Agent versioning uses a commit-based model:

- A live version is the mutable working copy used for development.
- A committed version (e.g., VERSION$N) is an immutable snapshot.
- An alias (e.g., PRODUCTION) is a pointer to a committed version for stable routing.
- A default version is served when no version is specified in API requests.

Current State
Version	Alias	Default	Description
VERSION$1	—	No	Original agent creation (2026-05-27)
VERSION$2	PRODUCTION	Yes	First production release (2026-06-10)

SQL Reference:
View All Versions
SHOW VERSIONS IN AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE;

Create a New Live Version for Development
-- Start development from a specific committed version
ALTER AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  CREATE LIVE VERSION FROM VERSION$2;

Modify the Live Version
-- Example: update the orchestration model
ALTER AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  MODIFY LIVE VERSION
  SET MODEL = 'claude-sonnet-4-6';

Commit the Live Version
-- Creates the next immutable snapshot (e.g., VERSION$3)
ALTER AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  COMMIT;

Assign the PRODUCTION Alias
-- Move the production alias to the newly committed version
ALTER AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  MODIFY VERSION VERSION$3 SET ALIAS = production;

Set a New Default Version
-- Update which version is served when no version is specified
ALTER AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  SET DEFAULT_VERSION = 'VERSION$3';

Rollback to a Previous Version
-- Point the production alias back to an earlier version
ALTER AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  MODIFY VERSION VERSION$2 SET ALIAS = production;

-- Also update the default if needed
ALTER AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  SET DEFAULT_VERSION = 'VERSION$2';

Alias Strategy
Alias	      |        Purpose	                   |     Routing
PRODUCTION	|    Stable deployment for end users |  ?version=production

Additional aliases can be added for staging or testing:
-- Create a staging alias for pre-production testing
ALTER AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  MODIFY VERSION VERSION$3 SET ALIAS = staging;

Development Workflow
1. CREATE LIVE VERSION FROM <current production version>
        |
2. Iterate on live version (modify tools, instructions, skills)
        |
3. Test the live version via API with ?version=live
        |
4. COMMIT (creates VERSION$N)
        |
5. Assign 'staging' alias -> test with ?version=staging
        |
6. Move 'production' alias to VERSION$N
        |
7. Update DEFAULT_VERSION to VERSION$N

Now do the actual switch test — run the same query against each version and compare:
sql
-- Currently on VERSION$2 (stripped) via production/default — test it first
-- e.g. in the playground: "Give me the Summary of Fedex Corporation."

-- Flip to the full-orchestration version
ALTER AGENT AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
SET DEFAULT_VERSION = 'VERSION$1';
-- run the SAME query again and compare

You can also drive it through the alias instead of the version number, which is the more production-like pattern:
sql-- Move the production alias from the stripped version to the full one
ALTER AGENT AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE
  MODIFY VERSION VERSION$1 SET ALIAS = production;

One thing to confirm before you trust the result: that VERSION$1 and VERSION$2 genuinely differ only in instructions.orchestration. Quickest check:
sqlSHOW VERSIONS IN AGENT AI_ACCOUNT_SUMMARY_CHATHPE_TOOL_AGNT_CLONE;
-- then inspect each version's spec file
LIST snow://agent/DATABASE.SCHEMA.AGENT_NAME
