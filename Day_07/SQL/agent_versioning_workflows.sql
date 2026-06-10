-- =============================================================================
-- AGENT VERSIONING WORKFLOW
-- Agent: <Your Agent Name>
-- =============================================================================
--
-- VERSION HISTORY
-- ---------------
-- VERSION$1  | 2026-05-27 | Initial agent creation (original spec)
-- VERSION$2  | 2026-06-10 | First production commit (alias: PRODUCTION, default)
--
-- ALIAS STRATEGY
-- --------------
-- PRODUCTION  -> Points to the stable, tested version serving live traffic.
--                API consumers use ?version=production for routing.
--
-- When no version is specified in API calls, the DEFAULT version is used.
-- Currently: VERSION$2 = PRODUCTION = DEFAULT
--

-- =============================================================================
-- 1. VIEW CURRENT VERSIONS
-- =============================================================================

SHOW VERSIONS IN AGENT database.schema.agent_name;


-- =============================================================================
-- 2. DEVELOPMENT: CREATE A NEW LIVE VERSION
-- =============================================================================
-- Start iterating on a new live version based on the current production snapshot.

ALTER AGENT database.schema.agent_name;
  CREATE LIVE VERSION FROM VERSION$2;


-- =============================================================================
-- 3. DEVELOPMENT: MODIFY THE LIVE VERSION
-- =============================================================================
-- Make changes to instructions, tools, skills, or model on the live version.
-- Example: update the orchestration model

-- ALTER AGENT database.schema.agent_name;
--   MODIFY LIVE VERSION
--   SET MODEL = 'claude-sonnet-4-6';


-- =============================================================================
-- 4. TESTING: SEND REQUESTS TO THE LIVE VERSION
-- =============================================================================
-- Test the live version before committing by targeting it explicitly in API calls:
--   POST /api/v2/cortex/agents/database.schema.agent_name;:run?version=LIVE


-- =============================================================================
-- 5. COMMIT: PROMOTE LIVE TO A NAMED VERSION
-- =============================================================================
-- Once testing passes, commit the live version. This creates the next VERSION$N.

ALTER AGENT database.schema.agent_name;
  COMMIT;

-- The live version is now gone. A new VERSION$N (e.g., VERSION$3) is created.


-- =============================================================================
-- 6. DEPLOY: ASSIGN THE PRODUCTION ALIAS
-- =============================================================================
-- Move the PRODUCTION alias to the newly committed version.
-- Replace VERSION$3 with the actual version name returned by COMMIT.

ALTER AGENT database.schema.agent_name;
  MODIFY VERSION VERSION$3 SET ALIAS = production;


-- =============================================================================
-- 7. DEPLOY: UPDATE THE DEFAULT VERSION
-- =============================================================================
-- Set the new version as the default so unversioned API calls use it.

ALTER AGENT database.schema.agent_name;
  SET DEFAULT_VERSION = 'VERSION$3';


-- =============================================================================
-- 8. ROLLBACK: REVERT TO A PREVIOUS VERSION
-- =============================================================================
-- If issues arise, point the PRODUCTION alias back to the previous version.

-- ALTER AGENT database.schema.agent_name;
--   MODIFY VERSION VERSION$2 SET ALIAS = production;

-- ALTER AGENT database.schema.agent_name;
--   SET DEFAULT_VERSION = 'VERSION$2';


-- =============================================================================
-- QUICK REFERENCE
-- =============================================================================
--
-- | Action                  | Command                                         |
-- |-------------------------|-------------------------------------------------|
-- | List versions           | SHOW VERSIONS IN AGENT <name>                   |
-- | Create live from ver    | ALTER AGENT <name> CREATE LIVE VERSION FROM <V>  |
-- | Commit live             | ALTER AGENT <name> COMMIT                        |
-- | Set alias               | ALTER AGENT <name> MODIFY VERSION <V> SET ALIAS = <alias> |
-- | Set default             | ALTER AGENT <name> SET DEFAULT_VERSION = '<V>'   |
-- | Remove alias            | ALTER AGENT <name> MODIFY VERSION <V> UNSET ALIAS |
-- | Drop a version          | ALTER AGENT <name> DROP VERSION <V>              |
--
-- API ROUTING:
--   ?version=production   -> Routes to whichever version holds the alias
--   ?version=VERSION$2    -> Routes to a specific named version
--   ?version=LIVE         -> Routes to the mutable development version
--   (no version param)    -> Routes to the DEFAULT version
--
