-- ============================================================
-- LAB 1 : EXTERNAL ACCESS INTEGRATION FOUNDATION
-- Run everything in a Snowsight worksheet. No external tools.
-- ============================================================
 
-- Use an admin role that can create integrations
USE ROLE ACCOUNTADMIN;
 
-- Dedicated warehouse for the lab (auto-suspend to save credits)
CREATE WAREHOUSE IF NOT EXISTS API_LAB_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;
 
-- Dedicated database and schema
CREATE DATABASE IF NOT EXISTS API_LAB_DB;
CREATE SCHEMA   IF NOT EXISTS API_LAB_DB.INTEGRATIONS;
 
-- Set context for the rest of the lab
USE WAREHOUSE API_LAB_WH;
USE DATABASE  API_LAB_DB;
USE SCHEMA    INTEGRATIONS;

-- A NETWORK RULE of MODE = EGRESS lists exactly which external
-- hosts Snowflake code may reach. Nothing else is reachable.
CREATE OR REPLACE NETWORK RULE owm_api_network_rule
    MODE      = EGRESS
    TYPE      = HOST_PORT
    VALUE_LIST = ('api.openweathermap.org');

-- Store the API key as a Snowflake SECRET so it never appears
-- in code, query history, or logs. Replace the placeholder with
-- your real OpenWeather API key (free tier at openweathermap.org).
CREATE OR REPLACE SECRET owm_api_key
    TYPE          = GENERIC_STRING
    SECRET_STRING = '<openweathermap api key>';

-- The integration ties the allowlist and the credential together
-- and can be switched off instantly via ENABLED = FALSE.
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION owm_access_integration
    ALLOWED_NETWORK_RULES         = (owm_api_network_rule)
    ALLOWED_AUTHENTICATION_SECRETS = (owm_api_key)
    ENABLED                        = TRUE;

-- Create a developer role and grant only what it needs.
CREATE ROLE IF NOT EXISTS API_DEVELOPER;
 
-- Let the role use the warehouse and work in the schema
GRANT USAGE ON WAREHOUSE API_LAB_WH      TO ROLE API_DEVELOPER;
GRANT USAGE ON DATABASE  API_LAB_DB      TO ROLE API_DEVELOPER;
GRANT USAGE ON SCHEMA    API_LAB_DB.INTEGRATIONS TO ROLE API_DEVELOPER;
 
-- Allow the role to use (not alter) the integration and read the secret
GRANT USAGE ON INTEGRATION owm_access_integration TO ROLE API_DEVELOPER;
GRANT READ   ON SECRET      owm_api_key            TO ROLE API_DEVELOPER;
 
-- Let the role create functions/procedures in the schema
GRANT CREATE FUNCTION  ON SCHEMA API_LAB_DB.INTEGRATIONS TO ROLE API_DEVELOPER;
GRANT CREATE PROCEDURE ON SCHEMA API_LAB_DB.INTEGRATIONS TO ROLE API_DEVELOPER;
GRANT CREATE TABLE     ON SCHEMA API_LAB_DB.INTEGRATIONS TO ROLE API_DEVELOPER;
 
-- Assign the role to yourself for testing (replace with your user)
GRANT ROLE API_DEVELOPER TO USER ANALYTICSWITHANAND;

SHOW NETWORK RULES LIKE 'owm_api_network_rule';
SHOW SECRETS LIKE 'owm_api_key';
SHOW EXTERNAL ACCESS INTEGRATIONS LIKE 'owm_access_integration';


-- Developer role provisioned in Lab 1
USE ROLE API_DEVELOPER;
USE WAREHOUSE API_LAB_WH;
USE DATABASE  API_LAB_DB;
USE SCHEMA    INTEGRATIONS;
 
CREATE OR REPLACE FUNCTION get_weather(city STRING)
    RETURNS VARIANT
    LANGUAGE PYTHON
    RUNTIME_VERSION = '3.11'
    HANDLER = 'get_weather'
    EXTERNAL_ACCESS_INTEGRATIONS = (owm_access_integration)
    PACKAGES = ('requests')
    SECRETS  = ('cred' = owm_api_key)
AS
$$
import _snowflake
import requests
 
def get_weather(city):
    # Read the API key from the Snowflake SECRET (never hard-coded)
    api_key = _snowflake.get_generic_secret_string('cred')
 
    url = "https://api.openweathermap.org/data/2.5/weather"
    params = {"q": city, "appid": api_key, "units": "metric"}
 
    try:
        resp = requests.get(url, params=params, timeout=30)
    except requests.exceptions.RequestException as e:
        return {"error": "request_failed", "detail": str(e)}
 
    if resp.status_code != 200:
        return {"error": "http_error",
                "status_code": resp.status_code,
                "body": resp.text[:500]}
 
    return resp.json()
$$;

SELECT get_weather('Mumbai') AS raw; 
-- Pull specific fields out of the VARIANT
SELECT
    get_weather('Bengaluru'):name::STRING            AS city,
    get_weather('Bengaluru'):main.temp::FLOAT        AS temp_c,
    get_weather('Bengaluru'):weather[0].main::STRING AS condition;

-- Raw landing table keeps the full API response (audit/replay)
CREATE OR REPLACE TABLE weather_raw (
    city           STRING,
    response       VARIANT,
    loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
 
-- Curated table holds the parsed, typed columns
CREATE OR REPLACE TABLE weather_curated (
    city        STRING,
    temp_c      FLOAT,
    humidity    NUMBER,
    pressure    NUMBER,
    condition   STRING,
    observed_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE PROCEDURE load_weather(cities ARRAY)
    RETURNS STRING
    LANGUAGE PYTHON
    RUNTIME_VERSION = '3.11'
    HANDLER = 'run'
    EXTERNAL_ACCESS_INTEGRATIONS = (owm_access_integration)
    PACKAGES = ('snowflake-snowpark-python', 'requests')
    SECRETS  = ('cred' = owm_api_key)
AS
$$
import _snowflake
import json
import requests
from snowflake.snowpark import Session
 
def run(session: Session, cities):
    api_key = _snowflake.get_generic_secret_string('cred')
    url = "https://api.openweathermap.org/data/2.5/weather"
 
    raw_rows = []        # for weather_raw  (city, response VARIANT)
    curated_rows = []    # for weather_curated (typed columns)
    errors = []
 
    for city in cities:
        try:
            resp = requests.get(
                url,
                params={"q": city, "appid": api_key, "units": "metric"},
                timeout=30,
            )
        except requests.exceptions.RequestException as e:
            errors.append(f"{city}: {e}")
            continue
 
        if resp.status_code != 200:
            errors.append(f"{city}: HTTP {resp.status_code}")
            continue
 
        body = resp.json()
        raw_rows.append([city, body])
        curated_rows.append([
            body.get("name"),
            float(body["main"]["temp"]),
            int(body["main"]["humidity"]),
            int(body["main"]["pressure"]),
            body["weather"][0]["main"] if body.get("weather") else None,
        ])
 
    # --- Load raw landing table ---
    if raw_rows:
        for row in raw_rows:
            session.sql(
                "INSERT INTO WEATHER_RAW (CITY, RESPONSE) "
                "SELECT ?, PARSE_JSON(?)",
                params=[row[0], json.dumps(row[1])]
            ).collect()
 
    # --- Load curated table ---
    if curated_rows:
        for row in curated_rows:
            session.sql(
                "INSERT INTO WEATHER_CURATED (CITY, TEMP_C, HUMIDITY, PRESSURE, CONDITION) "
                "SELECT ?, ?, ?, ?, ?",
                params=[row[0], row[1], row[2], row[3], row[4]]
            ).collect()
 
    msg = f"Loaded {len(curated_rows)} cities."
    if errors:
        msg += " Errors: " + "; ".join(errors)
    return msg
$$;

-- Call the procedure with an ARRAY of cities
CALL load_weather(ARRAY_CONSTRUCT('Mumbai', 'Bengaluru', 'Delhi', 'Chennai'));
 
-- Inspect the raw landing table
SELECT city, response, loaded_at
FROM weather_raw
ORDER BY loaded_at DESC;
 
-- Query the curated, typed table
SELECT city, temp_c, humidity, pressure, condition, observed_at
FROM weather_curated
ORDER BY temp_c DESC;
 
-- Flatten a field straight from raw if needed
SELECT
    city,
    response:wind.speed::FLOAT AS wind_speed,
    response:coord.lat::FLOAT  AS lat,
    response:coord.lon::FLOAT  AS lon
FROM weather_raw;

-- After creating the Streamlit app, grant it egress via the EAI.
-- Replace <APP_NAME> with the name shown in Snowsight.
-- Replace YOUR_APP_NAME below with the actual Streamlit app name shown in Snowsight
-- Requires ACCOUNTADMIN role (the app is owned by ACCOUNTADMIN):
USE ROLE ACCOUNTADMIN;
GRANT USAGE ON FUNCTION API_LAB_DB.INTEGRATIONS.GET_WEATHER(VARCHAR)
    TO ROLE ACCOUNTADMIN;
    
ALTER STREAMLIT API_LAB_DB.INTEGRATIONS.MBU85ZJI_EOY21NP
    SET EXTERNAL_ACCESS_INTEGRATIONS = (owm_access_integration);


