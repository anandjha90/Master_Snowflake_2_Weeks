## CRITICAL DATA INTEGRITY RULE (applies to ALL IB queries)

A single DISPLAY_ACCOUNT_COUNTRY_ST_ID can map to MULTIPLE EMDM_PARTY_ID_C values in AI_ACCOUNT_SUMMARY_S0_USER_ST_ASSIGNMENT_DTL.

When querying AI_IB_DETAILS, you MUST ALWAYS join through the assignment table to get ALL associated customer IDs. Use this pattern:

```sql
SELECT ...
FROM AI_IB_DETAILS ib
INNER JOIN AI_ACCOUNT_SUMMARY_S0_USER_ST_ASSIGNMENT_DTL a
  ON a.EMDM_PARTY_ID_C = ib.CUSTOMERID
WHERE a.DISPLAY_ACCOUNT_COUNTRY_ST_ID = '<resolved_id>'
```

NEVER resolve to a single EMDM_PARTY_ID_C with LIMIT 1 and then filter AI_IB_DETAILS by that single value. This causes inconsistent counts between queries.

Always use COUNT(DISTINCT SERIALNUMBER) for asset counts, not COUNT(*).

#0 -- Account Identifier Resolution

Determine the correct identifier type from user input:

| User Input Pattern | Identifier Type | Filter Column |
|---|---|---|
| Explicitly says "EMDM Party ID" or "Customer Account ID" | EMDM Party ID | EMDM_PARTY_ID_C |
| Numeric or alphanumeric identifier | Account ID | DISPLAY_ACCOUNT_COUNTRY_ST_ID |
| Customer name (text string) | Customer Name | DISPLAY_ACCOUNT_COUNTRY_ST_NAME |

Do not infer or assume EMDM Party ID unless explicitly stated by the user.

### Special Case -- List All Accounts

If the user asks to list all their accounts with no specific account mentioned, query AI_ACCOUNT_SUMMARY_S0_USER_ST_ASSIGNMENT_DTL using the SQL pattern below. The row access policy automatically filters to only the requesting user's assigned accounts. Skip identifier resolution and validation steps.

Display results as a table with two columns:
- "Originally Assigned Territory ID" (ORIGNALLY_ASSIGNED_SALES_TERRITORY_ID)
- "Originally Assigned Territory Name" (ORIGINALLY_ASSIGNED_SALES_TERRITORY_NAME)

SQL pattern:
```sql
SELECT DISTINCT
    ORIGNALLY_ASSIGNED_SALES_TERRITORY_ID AS "Originally Assigned Territory ID",
    ORIGINALLY_ASSIGNED_SALES_TERRITORY_NAME AS "Originally Assigned Territory Name"
FROM AI_ACCOUNT_SUMMARY_S0_USER_ST_ASSIGNMENT_DTL
ORDER BY ORIGINALLY_ASSIGNED_SALES_TERRITORY_NAME ASC;
```

### Name Search Strategy (Optimized)

When searching by DISPLAY_ACCOUNT_COUNTRY_ST_NAME, use a TWO-PASS strategy:

1. FIRST query: Use starts-with match `ILIKE '<name>%'` -- this avoids irrelevant partial matches (e.g., searching "ford" should NOT return "Oxford", "Affordable", "Bedford").
2. ONLY if the first query returns 0 results, fall back to contains match `ILIKE '%<name>%'`.

Never run the contains-match if the starts-with query already returned results.

### Optimized Disambiguation SQL (Single Query)

When a name-based search may return many results, use this single SQL query that combines count, prioritization, and limit:

```sql
SELECT DISTINCT
    display_account_country_st_id AS "Sales Territory ID",
    display_account_country_st_name AS "Account Name",
    COUNT(*) OVER () AS total_matches
FROM AI_ACCOUNT_SUMMARY_S0_USER_ST_ASSIGNMENT_DTL
WHERE display_account_country_st_name ILIKE '<name>%'
ORDER BY
    CASE
        WHEN display_account_country_st_name ILIKE '<name> - %' THEN 0
        WHEN display_account_country_st_name ILIKE '<name> %' THEN 1
        ELSE 2
    END ASC,
    display_account_country_st_name ASC
LIMIT 10
```

This single query:
- Counts total matches via window function (total_matches column)
- Prioritizes exact matches (e.g., "FORD - US") first
- Then direct parent companies (e.g., "FORD MOTOR COMPANY - US") second
- Then other starts-with matches last
- Limits to 10 rows for disambiguation display

Do NOT run separate COUNT and SELECT queries. Use this one query for everything.

### Disambiguation Rules

When the query returns total_matches > 10:
- State: "There are {total_matches} accounts whose names start with '{name}'."
- Display the 10 rows returned as a table with columns: Sales Territory ID | Account Name
- Do NOT include the total_matches column in the displayed table.
- Ask the user to provide the country, Sales Territory ID, or a more specific name.

When the query returns 10 or fewer total results:
- Display all matches in a table with columns: Sales Territory ID | Account Name
- Ask the user to confirm which account they mean.

When the query returns exactly 1 result:
- Resolve directly. No disambiguation needed.

### After Resolution

Once an account is resolved, retrieve and store:
- DISPLAY_ACCOUNT_COUNTRY_ST_ID
- DISPLAY_ACCOUNT_COUNTRY_ST_NAME
- EMDM_PARTY_ID_C

If no matching record is found, inform the user that no data was found for the requested account.
Render the account header per Response Instruction R2 before presenting any other data.
Use the resolved identifiers for all subsequent queries in the session.

#2 -- Installed Base Data Retrieval

Use the following semantic relationship for all installed base queries:
EMDM_PARTY_ID_C (AI_ACCOUNT_SUMMARY_S0_USER_ST_ASSIGNMENT_DTL) -> CUSTOMERID (AI_IB_DETAILS)

Always join through this relationship when retrieving IB data.

#3 -- Installed Base Summary

When the user requests an account summary or installed base overview, execute all four sub-steps and present the results together.

3a -- Business Unit Breakdown
Query AI_IB_DETAILS for serial numbers linked to the resolved EMDM_PARTY_ID_C.
Group by BUSINESSUNIT.
Compute:
- Total asset count (COUNT(DISTINCT SERIALNUMBER)) across all business units.
- Asset count per BUSINESSUNIT.
- Percentage share of each BUSINESSUNIT relative to the total.
- Identify the BUSINESSUNIT with the highest count as the primary concentration area.
Pass computed values to Response Instruction R3.

3b -- Compelling Events (Next 180 Days)
Query AI_IB_DETAILS for the resolved account.
Compute the following three counts for events falling between today and today + 180 days:
- Assets eligible for refresh: REFRESH_RENEW_GUIDANCE = 'Refresh' AND SUPPORTENDDATE within next 180 days.
- Contracts up for renewal: CONTRACT_END_DATE within next 180 days. Also retrieve CONTRACTID and CONTRACT_END_DATE for each matching record.
- Assets reaching end of support: SUPPORTENDDATE within next 180 days.
Pass computed values to Response Instruction R3b.

3c -- Actionable Insight
Query AI_ACCOUNT_SUMMARY_S12_ACTIONABLE_INSIGHT filtered by STID = resolved DISPLAY_ACCOUNT_COUNTRY_ST_ID.
Retrieve: COMPELLING_EVENT, ACTION, INSIGHT, GBU, ENABLEMENT_LABEL, ENABLEMENT_HYPERLINK.
For each record, synthesize a concise recommendation by combining ACTION and INSIGHT.
Pass to Response Instruction R10.

3d -- Sales Programs (as part of account summary)
Query AI_ACCOUNT_SUMMARY_S7_SALES_PROGRAM_DETAILS joined with AI_IB_PROGRAM_SUMMARY on SFDC_CAMPAIGN_CODE = CAMPAIGN_ID.
Filter by ST_ID = resolved DISPLAY_ACCOUNT_COUNTRY_ST_ID.
Retrieve all columns except ST_ID, plus IB_ANALYTICS_PROGRAM_SUMMARY_SHORT.
Pass to Response Instruction R4.

#4 -- Marketing and Digital Summary

4a -- IT Spend
Query AI_ACCOUNT_SUMMARY_S8_MKT_HG_IT_SPEND_ST_CE_COMBINED filtered by SLS_TTY_ID = resolved DISPLAY_ACCOUNT_COUNTRY_ST_ID.
Select the most granular non-overlapping budget fields available (e.g., server computing, network infrastructure, storage, security, software, services).
Do not include a parent total field alongside the subcategory fields that compose it -- this causes double counting.
Pass to Response Instruction R11.

4b -- Propensity to Buy (PTB)
Query AI_ACCOUNT_SUMMARY_S6_PROPENSITY_TO_BUY_ST_CE_COMBINED.
Match DISPLAY_ACCOUNT_COUNTRY_ST_ID against COUNTRY_ENTITY_ID.
Note: COUNTRY_ENTITY_ID is NOT related to CUSTOMERID.
Retrieve: COUNTRY_ENTITY_ID, GROWTH_AREA, RECOMMENDED_PRIORITY.
Pass to Response Instruction R5.

4c -- Top Priority Workloads
Query AI_ACCOUNT_SUMMARY_S13_MKT_WORKLOAD_ST_CE_COMBINED joined to the assignment table on DISPLAY_ACCOUNT_COUNTRY_ST_ID = SLS_TTY_ID.
MKT_UPDATE_DATE is mandatory and must always be retrieved.
Derive WORKLOAD from the first non-null, non-'Null' workload column per record.
Derive WORKLOAD_PRIORITY:
- 'High' if any workload column = 'High'
- 'Mid' if any workload column = 'Mid' (and none = 'High')
- 'Low' otherwise
Return the top 10 records ranked by WORKLOAD_PRIORITY descending (High first), unless the user specifies a different limit.
Pass to Response Instruction R6.

4d -- Digital Intent Signals -- External Web Searches
Query AI_ACCOUNT_SUMMARY_S11_MKT_EXTERNAL_WEB_SEARCH_ST_CE_COMBINED.
Filter by ST_COUNTRY_ID = resolved DISPLAY_ACCOUNT_COUNTRY_ST_ID.
Retrieve the top 10 records ranked by TOPIC_RANK ascending.
Use only the TOPIC column value.
Pass to Response Instruction R7.

4e -- Digital Intent Signals -- Internal Web Searches
Query AI_ACCOUNT_SUMMARY_S10_MKT_INTERNAL_WEB_SEARCH_ST_CE_COMBINED.
Filter by ST_COUNTRY_ID = resolved DISPLAY_ACCOUNT_COUNTRY_ST_ID.
Retrieve the top 10 records ranked by SCORE_NUM descending.
Use only the BU_CATEGORY column value. If a value appears more than once, include it only once (deduplicate).
Pass to Response Instruction R7.

#5 -- Competitor Analysis

Triggered when the user requests competitor or market intelligence data.
Query AI_ACCOUNT_SUMMARY_S9_MKT_COMPETITIVE_ST_CE_COMBINED.
Filter by SALES_TERRITORY_ID = resolved DISPLAY_ACCOUNT_COUNTRY_ST_ID.
Rank by frequency (count of records per COMPETITOR + PRODUCT + CATEGORY combination).
Return the top 10.
Retrieve fields: COMPETITOR, PRODUCT, CATEGORY.
Pass to Response Instruction R8.

#6 -- Sales Program Details (Standalone)

Triggered when the user explicitly requests "sales programs" or "sales program details" outside of a full account summary.
Query AI_ACCOUNT_SUMMARY_S7_SALES_PROGRAM_DETAILS joined with AI_IB_PROGRAM_SUMMARY on SFDC_CAMPAIGN_CODE = CAMPAIGN_ID.
Filter by ST_ID = resolved DISPLAY_ACCOUNT_COUNTRY_ST_ID.
Retrieve all columns except ST_ID, plus IB_ANALYTICS_PROGRAM_SUMMARY_SHORT.
Pass to Response Instruction R4.

#7 -- Serial Number Level Detail

Triggered when the user requests serial numbers, asset-level detail, or IB records.
Query AI_IB_DETAILS for the resolved account via CUSTOMERID.
Retrieve only: SERIALNUMBER, PRODUCT_DESCRIPTION.
Rank by IB_REFRESH_POTENTIAL descending.
Apply a default limit of 10 records unless the user specifies otherwise.
Display results as a table.

#8 -- Opportunity / Pipeline

Triggered when the user requests "Opportunity", "sales opportunities", or "Pipeline".
Query AI_ACCOUNT_SUMMARY_S14_SALES_PROGRAM_OPPORTUNITY.
Filter to records where COUNTRY_SALES_ENTITY_ID__C matches the resolved DISPLAY_ACCOUNT_COUNTRY_ST_ID.
Return all available fields.

#9 -- End of Service Life (EOSL)

Triggered when the user requests "end of service life" or "EOSL".
Query AI_IB_DETAILS for the resolved account via CUSTOMERID.
Map directly to the EOSL field.
Display results as a table showing: SERIALNUMBER, PRODUCT_DESCRIPTION, BUSINESSUNIT, EOSL.
Order by EOSL ascending (soonest first).

#10 -- Qualified Installed Base (QIB)

Do NOT hardcode or infer the Program ID. Follow all four steps in sequence.

Step 1 -- Identify Program ID
Query AI_IB_PROGRAM_SUMMARY. Identify the relevant Program ID using CAMPAIGN_ID.

Step 2 -- Fetch Associated Accounts
Using the Program ID from Step 1, query AI_ACCOUNT_SUMMARY_S7_SALES_PROGRAM_DETAILS to retrieve all ST_ID values (accounts) linked to that program.

Step 3 -- Retrieve QIB Details
Query AI_IB_DETAILS and filter by:
- CUSTOMERID matching the account(s) from Step 2.
- PROGRAM_ACCOUNT_IDNTFR matching the Program ID from Step 1.

Step 4 -- Apply Both Filters
Always apply BOTH the Program ID filter AND the account identifier filter simultaneously. Do not return results filtered on only one of the two conditions.
