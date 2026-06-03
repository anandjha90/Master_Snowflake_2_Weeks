/* ================================================================
   SNOWFLAKE + REST API HANDLING  —  TRIAL-SAFE 
   ----------------------------------------------------------------
   IMPORTANT: Trial accounts CANNOT make outbound API calls
   (External Access Integration is blocked). To do LIVE calls you
   must convert the trial to paid (add a credit card -- you keep
   your free credits) OR ask your Snowflake rep to enable it.

   This script teaches the part of "handling REST APIs" that runs
   on a trial TODAY: parsing responses, flattening JSON into rows,
   typing fields, and building request payloads. The JSON shapes
   below are the REAL responses from jsonplaceholder.typicode.com
   and open.er-api.com -- so when you move to a paid account, you
   swap PARSE_JSON('...') for a live UDF call and NOTHING else
   changes. (The live UDF is shown, commented, at the bottom.)
   ================================================================ */


/* ================================================================
   SECTION 1 — CONTEXT
   ================================================================ */
USE ROLE ACCOUNTADMIN;            -- trial gives you this

CREATE WAREHOUSE IF NOT EXISTS DEMO_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND   = 60
    AUTO_RESUME    = TRUE
    INITIALLY_SUSPENDED = TRUE;

CREATE DATABASE IF NOT EXISTS API_DEMO_DB;
CREATE SCHEMA   IF NOT EXISTS API_DEMO_DB.DEMO;

USE WAREHOUSE DEMO_WH;
USE DATABASE  API_DEMO_DB;
USE SCHEMA    DEMO;


/* ================================================================
   SECTION 2 — WHAT A REST RESPONSE LOOKS LIKE
   PARSE_JSON turns an API response string into a VARIANT, exactly
   what a live UDF would return. Dot/bracket notation reads fields.
   (Real response shape from jsonplaceholder.typicode.com/todos/1)
   ================================================================ */
SELECT PARSE_JSON($$
{
  "userId": 1,
  "id": 1,
  "title": "delectus aut autem",
  "completed": false
}
$$) AS api_response;

-- Read individual fields out of the VARIANT, with typing
SELECT
    PARSE_JSON($$
    { "userId": 1, "id": 1, "title": "delectus aut autem", "completed": false }
    $$):id::INT           AS todo_id,
    PARSE_JSON($$
    { "userId": 1, "id": 1, "title": "delectus aut autem", "completed": false }
    $$):title::STRING     AS title,
    PARSE_JSON($$
    { "userId": 1, "id": 1, "title": "delectus aut autem", "completed": false }
    $$):completed::BOOLEAN AS done;


/* ================================================================
   SECTION 3 — LAND THE RAW RESPONSE, THEN QUERY IT (the real pattern)
   In production a UDF writes the VARIANT here. On trial we INSERT
   the same JSON. Querying is identical either way.
   ================================================================ */
CREATE OR REPLACE TABLE api_raw (
    source     STRING,
    response   VARIANT,
    loaded_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- A LIST response (real shape from jsonplaceholder.typicode.com/users)
INSERT INTO api_raw (source, response)
SELECT 'users', PARSE_JSON($$
[
  { "id": 1, "name": "Leanne Graham", "email": "Sincere@april.biz",
    "address": { "city": "Gwenborough", "zipcode": "92998-3874" },
    "company": { "name": "Romaguera-Crona" } },
  { "id": 2, "name": "Ervin Howell", "email": "Shanna@melissa.tv",
    "address": { "city": "Wisokyburgh", "zipcode": "90566-7771" },
    "company": { "name": "Deckow-Crist" } },
  { "id": 3, "name": "Clementine Bauch", "email": "Nathan@yesenia.net",
    "address": { "city": "McKenziehaven", "zipcode": "59590-4157" },
    "company": { "name": "Romaguera-Jacobson" } }
]
$$);

-- FLATTEN a JSON array into one row per element, reaching nested fields
SELECT
    f.value:id::INT             AS user_id,
    f.value:name::STRING        AS name,
    f.value:email::STRING       AS email,
    f.value:address.city::STRING AS city,
    f.value:company.name::STRING AS company
FROM api_raw,
LATERAL FLATTEN(input => response) f
WHERE source = 'users';


/* ================================================================
   SECTION 4 — FLATTEN AN OBJECT (key/value) INTO ROWS + LOAD A TABLE
   Real shape from open.er-api.com/v6/latest/USD : "rates" is an
   object whose keys are currency codes. This is the classic
   "load API results into a typed table" task.
   ================================================================ */
INSERT INTO api_raw (source, response)
SELECT 'fx_usd', PARSE_JSON($$
{
  "result": "success",
  "base_code": "USD",
  "time_last_update_utc": "Mon, 02 Jun 2025 00:00:01 +0000",
  "rates": { "USD": 1, "INR": 83.42, "EUR": 0.92, "GBP": 0.78,
             "JPY": 157.3, "AUD": 1.51, "CAD": 1.37, "SGD": 1.35 }
}
$$);

CREATE OR REPLACE TABLE fx_rates (
    base        STRING,
    currency    STRING,
    rate        FLOAT,
    as_of       STRING,
    loaded_at   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Parse + flatten the rates object straight into the typed table
INSERT INTO fx_rates (base, currency, rate, as_of)
SELECT
    response:base_code::STRING            AS base,
    f.key::STRING                         AS currency,
    f.value::FLOAT                        AS rate,
    response:time_last_update_utc::STRING AS as_of
FROM api_raw,
LATERAL FLATTEN(input => response:rates) f
WHERE source = 'fx_usd';

-- Query the loaded data
SELECT base, currency, rate, as_of
FROM fx_rates
ORDER BY rate DESC;


/* ================================================================
   SECTION 5 — BUILD A REQUEST PAYLOAD (the POST side)
   You construct request bodies in SQL with OBJECT_CONSTRUCT, then
   serialize with TO_JSON. A live POST UDF would send this string.
   ================================================================ */
SELECT TO_JSON(
    OBJECT_CONSTRUCT(
        'title',  'Hello from Snowflake',
        'body',   'This payload was built in SQL',
        'userId', 1
    )
) AS request_body;

-- Build many payloads from a table (e.g. records to send to an API)
WITH records AS (
    SELECT 1 AS user_id, 'First post'  AS title
    UNION ALL SELECT 2, 'Second post'
)
SELECT
    user_id,
    TO_JSON(OBJECT_CONSTRUCT('userId', user_id, 'title', title)) AS payload
FROM records;


/* ================================================================
   SECTION 6 — HANDLE ERROR RESPONSES & STATUS CODES
   APIs return 4xx/5xx with non-data bodies. Model that here so the
   trainees see defensive parsing before they do it live.
   ================================================================ */
WITH responses AS (
    SELECT 200 AS status, PARSE_JSON($$ { "id": 1, "ok": true } $$) AS body
    UNION ALL
    SELECT 404, PARSE_JSON($$ { "error": "Not Found" } $$)
    UNION ALL
    SELECT 429, PARSE_JSON($$ { "error": "Too Many Requests" } $$)
)
SELECT
    status,
    CASE
        WHEN status = 200 THEN 'OK — parse body'
        WHEN status = 401 THEN 'Auth failure — check key/secret'
        WHEN status = 404 THEN 'Not found — check URL'
        WHEN status = 429 THEN 'Rate limited — back off & retry'
        WHEN status >= 500 THEN 'Server error — retry with backoff'
        ELSE 'Unexpected'
    END                              AS action,
    body:error::STRING               AS error_message
FROM responses;


/* ================================================================
   SECTION 7 — THE LIVE VERSION (paid account only)
   After converting the trial to paid (add a credit card), THIS is
   all you add. Everything in Sections 2-6 stays the same -- you
   just replace PARSE_JSON('...') with get_json('<url>').
   ================================================================ */
-- CREATE OR REPLACE NETWORK RULE demo_api_rule
--     MODE = EGRESS TYPE = HOST_PORT
--     VALUE_LIST = ('jsonplaceholder.typicode.com', 'open.er-api.com');
--
-- CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION demo_api_integration
--     ALLOWED_NETWORK_RULES = (demo_api_rule)
--     ENABLED = TRUE;
--
-- CREATE OR REPLACE FUNCTION get_json(url STRING)
--     RETURNS VARIANT
--     LANGUAGE PYTHON
--     RUNTIME_VERSION = '3.11'
--     HANDLER = 'get_json'
--     EXTERNAL_ACCESS_INTEGRATIONS = (demo_api_integration)
--     PACKAGES = ('requests')
-- AS
-- $$
-- import requests
-- def get_json(url):
--     resp = requests.get(url, timeout=30)
--     if resp.status_code != 200:
--         return {"error": "http_error", "status_code": resp.status_code}
--     return resp.json()
-- $$;
--
-- -- Then the SAME flatten logic, now on LIVE data:
-- SELECT f.key::STRING AS currency, f.value::FLOAT AS rate
-- FROM (SELECT get_json('https://open.er-api.com/v6/latest/USD') AS response),
-- LATERAL FLATTEN(input => response:rates) f;
