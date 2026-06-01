-- ######################################################################
-- SNOWFLAKE INTELLIGENCE ARTIFACTS — ECommerce Analytics
-- Database : ECOM_DB  |  Schema : RAW
-- ######################################################################

-- ============================================================
-- SECTION 0: SETUP — ROLES & PRIVILEGES
-- Run as ACCOUNTADMIN
-- ============================================================

USE ROLE ACCOUNTADMIN;

-- Enable cross-region inference (needed for best model quality)
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

-- Grant privileges to your working role (replace SYSADMIN if needed)
GRANT USAGE ON DATABASE ECOM_DB TO ROLE SYSADMIN;
GRANT USAGE ON SCHEMA ECOM_DB.RAW TO ROLE SYSADMIN;
GRANT CREATE AGENT ON SCHEMA ECOM_DB.RAW TO ROLE SYSADMIN;
GRANT CREATE SEMANTIC VIEW ON SCHEMA ECOM_DB.RAW TO ROLE SYSADMIN;

USE ROLE SYSADMIN;
USE DATABASE ECOM_DB;
USE SCHEMA RAW;
USE WAREHOUSE WAREHOUSE_SNOWPRO;


-- ============================================================
-- SECTION 1: SEMANTIC VIEW
-- This is what powers Cortex Analyst (Text-to-SQL) inside
-- the Intelligence Agent — the brain of your Artifact queries
-- ============================================================


CREATE OR REPLACE SEMANTIC VIEW ECOM_DB.RAW.SV_ECOM_ANALYTICS
  TABLES (
    -- ── FACT: ORDERS ──────────────────────────────────────
    orders AS ECOM_DB.RAW.FCT_ORDERS
      PRIMARY KEY (ORDER_ID)
      WITH SYNONYMS ('transactions', 'sales', 'purchases')
      COMMENT = 'Core fact table containing all customer orders. Each row is one order line with product, pricing, delivery, and channel details.',

    -- ── FACT: INVENTORY ───────────────────────────────────
    inventory AS ECOM_DB.RAW.FCT_INVENTORY
      PRIMARY KEY (INVENTORY_DATE, STORE_ID, PRODUCT_ID)
      WITH SYNONYMS ('stock', 'warehouse')
      COMMENT = 'Daily inventory snapshot per product per store. Tracks opening stock, purchases, sales, closing stock, shrinkage, and reorder triggers.',

    -- ── FACT: RETURNS ─────────────────────────────────────
    returns AS ECOM_DB.RAW.FCT_RETURNS
      PRIMARY KEY (RETURN_ID)
      WITH SYNONYMS ('refunds', 'complaints')
      COMMENT = 'All customer return transactions with reason, refund amount, status and channel.',

    -- ── DIM: CUSTOMERS ────────────────────────────────────
    customers AS ECOM_DB.RAW.CUSTOMERS
      PRIMARY KEY (CUSTOMER_ID)
      WITH SYNONYMS ('buyers', 'users', 'clients')
      COMMENT = 'Customer master with demographics, location, loyalty tier, and registration date.',

    -- ── DIM: PRODUCTS ─────────────────────────────────────
    products AS ECOM_DB.RAW.PRODUCTS
      PRIMARY KEY (PRODUCT_ID)
      WITH SYNONYMS ('items', 'SKUs', 'goods')
      COMMENT = 'Product catalog with category, brand, price, rating, and stock quantity.',

    -- ── DIM: STORES ───────────────────────────────────────
    stores AS ECOM_DB.RAW.STORES
      PRIMARY KEY (STORE_ID)
      WITH SYNONYMS ('outlets', 'locations')
      COMMENT = 'Store master covering region, city, channel type, and floor area.',

    -- ── DIM: SALES CHANNELS ───────────────────────────────
    channels AS ECOM_DB.RAW.SALES_CHANNELS
      PRIMARY KEY (CHANNEL_ID)
      WITH SYNONYMS ('platform', 'medium')
      COMMENT = 'Sales channel reference: Online, Retail, Marketplace with commission rates.'
  )

  RELATIONSHIPS (
    orders (CUSTOMER_ID) REFERENCES customers (CUSTOMER_ID),
    orders (STORE_ID)    REFERENCES stores    (STORE_ID),
    orders (CHANNEL_ID)  REFERENCES channels  (CHANNEL_ID),
    returns (ORDER_ID)   REFERENCES orders    (ORDER_ID),
    returns (CHANNEL_ID) REFERENCES channels  (CHANNEL_ID)
  )

  -- ── DIMENSIONS (columns the agent can filter/group by) ──
  DIMENSIONS (
    orders.order_id         AS ORDER_ID         WITH SYNONYMS = ('transaction id', 'order number'),
    orders.order_date       AS ORDER_DATE       WITH SYNONYMS = ('purchase date', 'sale date'),
    orders.product_name     AS PRODUCT_NAME     WITH SYNONYMS = ('item name', 'product'),
    orders.brand            AS BRAND            WITH SYNONYMS = ('manufacturer'),
    orders.category         AS CATEGORY         WITH SYNONYMS = ('product category', 'segment'),
    orders.channel_id       AS CHANNEL_ID       WITH SYNONYMS = ('channel', 'platform'),
    orders.order_status     AS ORDER_STATUS     WITH SYNONYMS = ('status', 'fulfillment status')
                            COMMENT = 'Values: Delivered, Shipped, Pending, Cancelled, Returned',
    orders.payment_method   AS PAYMENT_METHOD   WITH SYNONYMS = ('payment type')
                            COMMENT = 'Values: UPI, Credit Card, Debit Card, Net Banking, COD, Wallet',
    orders.city             AS CITY             WITH SYNONYMS = ('customer city'),
    orders.state            AS STATE            WITH SYNONYMS = ('customer state'),
    orders.region_id        AS REGION_ID        WITH SYNONYMS = ('region'),
    orders.delivery_days    AS DELIVERY_DAYS    WITH SYNONYMS = ('days to deliver', 'lead time'),

    customers.loyalty_tier  AS LOYALTY_TIER     WITH SYNONYMS = ('tier', 'membership level')
                            COMMENT = 'Values: Bronze, Silver, Gold, Platinum',
    customers.gender        AS GENDER,
    customers.cust_state    AS customers.STATE,

    returns.return_reason   AS RETURN_REASON    WITH SYNONYMS = ('reason for return')
                            COMMENT = 'Values: Defective Product, Wrong Item, Size Mismatch, Not as Described, Changed Mind, Late Delivery',
    returns.return_status   AS RETURN_STATUS    WITH SYNONYMS = ('refund status')
                            COMMENT = 'Values: Approved, Rejected, Processing',

    inventory.inv_region    AS inventory.REGION_ID,
    inventory.inv_product_id AS inventory.PRODUCT_ID,

    channels.channel_name   AS CHANNEL_NAME     WITH SYNONYMS = ('channel name'),
    products.subcategory    AS SUBCATEGORY
  )

  -- ── METRICS (pre-defined KPIs the agent calculates) ─────
  METRICS (
    -- Revenue
    orders.total_revenue    AS SUM(orders.TOTAL_SALES)
      WITH SYNONYMS = ('revenue', 'sales amount', 'GMV', 'gross merchandise value')
      COMMENT = 'Total revenue = sum of TOTAL_SALES across all orders',

    -- Order Count
    orders.total_orders     AS COUNT(DISTINCT orders.ORDER_ID)
      WITH SYNONYMS = ('number of orders', 'order volume', 'transaction count')
      COMMENT = 'Count of unique orders',

    -- Average Order Value
    orders.avg_order_value  AS AVG(orders.TOTAL_SALES)
      WITH SYNONYMS = ('AOV', 'average basket size', 'average transaction value')
      COMMENT = 'Average revenue per order',

    -- Unique Customers
    orders.unique_customers AS COUNT(DISTINCT orders.CUSTOMER_ID)
      WITH SYNONYMS = ('active customers', 'buyer count'),

    -- Average Delivery Days
    orders.avg_delivery_days AS AVG(orders.DELIVERY_DAYS)
      WITH SYNONYMS = ('average lead time', 'avg delivery time'),

    -- Total Returns Count
    returns.total_returns   AS COUNT(DISTINCT returns.RETURN_ID)
      WITH SYNONYMS = ('number of returns', 'return volume'),

    -- Total Refund Amount
    returns.total_refunds   AS SUM(returns.REFUND_AMOUNT)
      WITH SYNONYMS = ('refund value', 'money refunded'),

    -- Return Rate (%)
    returns.return_rate_pct AS
      ROUND(COUNT(DISTINCT returns.RETURN_ID) * 100.0 / NULLIF(COUNT(DISTINCT orders.ORDER_ID), 0), 2)
      WITH SYNONYMS = ('return rate', '% returns', 'return percentage')
      COMMENT = 'Percentage of orders that were returned. Industry benchmark ~8%.',

    -- Closing Stock
    inventory.total_closing_stock AS SUM(inventory.CLOSING_STOCK)
      WITH SYNONYMS = ('closing stock', 'stock on hand', 'ending inventory'),

    -- Reorder Alerts
    inventory.reorder_alerts AS SUM(inventory.REORDER_TRIGGERED)
      WITH SYNONYMS = ('reorder count', 'stockout alerts'),

    -- Avg Shrinkage
    inventory.avg_shrinkage_pct AS AVG(inventory.SHRINKAGE)
      WITH SYNONYMS = ('shrinkage', 'inventory loss percentage'),

    -- Customer LTV proxy
    orders.avg_customer_ltv AS
      SUM(orders.TOTAL_SALES) / NULLIF(COUNT(DISTINCT orders.CUSTOMER_ID), 0)
      WITH SYNONYMS = ('customer lifetime value', 'CLV', 'LTV')
      COMMENT = 'Average total spend per unique customer in the selected period'
  )

  COMMENT = 'Semantic view for ANALYTICSWITHANAND ECommerce Analytics project. Covers Orders, Inventory, Returns, Customers, Products, Stores and Sales Channels in ECOM_DB.RAW.'

  -- ── VERIFIED QUERIES (boosts accuracy & speed) ──────────
  AI_VERIFIED_QUERIES (
    vq_total_revenue_2024 AS (
      QUESTION 'What is the total revenue for 2024?'
      SQL 'SELECT SUM(TOTAL_SALES) AS TOTAL_REVENUE FROM ECOM_DB.RAW.FCT_ORDERS WHERE ORDER_DATE BETWEEN ''2024-01-01'' AND ''2024-12-31'''
    ),
    vq_monthly_revenue_2024 AS (
      QUESTION 'Show monthly revenue trend for 2024'
      SQL 'SELECT DATE_TRUNC(''MONTH'', ORDER_DATE)::DATE AS MONTH, SUM(TOTAL_SALES) AS REVENUE FROM ECOM_DB.RAW.FCT_ORDERS WHERE ORDER_DATE BETWEEN ''2024-01-01'' AND ''2024-12-31'' GROUP BY 1 ORDER BY 1'
    ),
    vq_category_revenue AS (
      QUESTION 'Which category has the highest revenue?'
      SQL 'SELECT CATEGORY, SUM(TOTAL_SALES) AS REVENUE FROM ECOM_DB.RAW.FCT_ORDERS GROUP BY 1 ORDER BY 2 DESC LIMIT 10'
    ),
    vq_return_rate_by_category AS (
      QUESTION 'What is the return rate by category?'
      SQL 'SELECT o.CATEGORY, COUNT(DISTINCT r.RETURN_ID) AS RETURNS, COUNT(DISTINCT o.ORDER_ID) AS ORDERS, ROUND(COUNT(DISTINCT r.RETURN_ID)*100.0/NULLIF(COUNT(DISTINCT o.ORDER_ID),0),2) AS RETURN_RATE_PCT FROM ECOM_DB.RAW.FCT_ORDERS o LEFT JOIN ECOM_DB.RAW.FCT_RETURNS r ON o.ORDER_ID = r.ORDER_ID GROUP BY 1 ORDER BY 4 DESC'
    ),
    vq_top_10_products AS (
      QUESTION 'Show top 10 products by revenue'
      SQL 'SELECT PRODUCT_NAME, SUM(TOTAL_SALES) AS REVENUE FROM ECOM_DB.RAW.FCT_ORDERS GROUP BY 1 ORDER BY 2 DESC LIMIT 10'
    ),
    vq_top_return_reasons AS (
      QUESTION 'What are the top return reasons?'
      SQL 'SELECT RETURN_REASON, COUNT(*) AS RETURN_COUNT FROM ECOM_DB.RAW.FCT_RETURNS GROUP BY 1 ORDER BY 2 DESC'
    ),
    vq_revenue_by_channel AS (
      QUESTION 'Show revenue by sales channel'
      SQL 'SELECT sc.CHANNEL_NAME, SUM(o.TOTAL_SALES) AS REVENUE, COUNT(DISTINCT o.ORDER_ID) AS ORDERS FROM ECOM_DB.RAW.FCT_ORDERS o LEFT JOIN ECOM_DB.RAW.SALES_CHANNELS sc ON o.CHANNEL_ID = sc.CHANNEL_ID GROUP BY 1 ORDER BY 2 DESC'
    ),
    vq_revenue_by_state AS (
      QUESTION 'Which states have the highest revenue?'
      SQL 'SELECT STATE, SUM(TOTAL_SALES) AS REVENUE FROM ECOM_DB.RAW.FCT_ORDERS GROUP BY 1 ORDER BY 2 DESC LIMIT 15'
    ),
    vq_loyalty_distribution AS (
      QUESTION 'Show loyalty tier distribution of customers'
      SQL 'SELECT LOYALTY_TIER, COUNT(*) AS CUSTOMERS FROM ECOM_DB.RAW.CUSTOMERS GROUP BY 1 ORDER BY 2 DESC'
    ),
    vq_delivery_by_channel AS (
      QUESTION 'What is the average delivery time by channel?'
      SQL 'SELECT sc.CHANNEL_NAME, ROUND(AVG(o.DELIVERY_DAYS),1) AS AVG_DELIVERY_DAYS FROM ECOM_DB.RAW.FCT_ORDERS o LEFT JOIN ECOM_DB.RAW.SALES_CHANNELS sc ON o.CHANNEL_ID = sc.CHANNEL_ID GROUP BY 1 ORDER BY 2'
    ),
    vq_reorder_alerts AS (
      QUESTION 'Show inventory reorder alerts by region'
      SQL 'SELECT REGION_ID, SUM(REORDER_TRIGGERED) AS REORDER_ALERTS FROM ECOM_DB.RAW.FCT_INVENTORY GROUP BY 1 ORDER BY 2 DESC'
    ),
    vq_revenue_by_payment AS (
      QUESTION 'What is revenue by payment method?'
      SQL 'SELECT PAYMENT_METHOD, SUM(TOTAL_SALES) AS REVENUE, COUNT(*) AS ORDERS FROM ECOM_DB.RAW.FCT_ORDERS GROUP BY 1 ORDER BY 2 DESC'
    ),
    vq_order_status AS (
      QUESTION 'Show order status breakdown'
      SQL 'SELECT ORDER_STATUS, COUNT(*) AS ORDERS, SUM(TOTAL_SALES) AS REVENUE FROM ECOM_DB.RAW.FCT_ORDERS GROUP BY 1 ORDER BY 2 DESC'
    ),
    vq_mom_growth AS (
      QUESTION 'What is the month over month revenue growth?'
      SQL 'WITH monthly AS (SELECT DATE_TRUNC(''MONTH'', ORDER_DATE)::DATE AS MONTH, SUM(TOTAL_SALES) AS REVENUE FROM ECOM_DB.RAW.FCT_ORDERS GROUP BY 1) SELECT MONTH, REVENUE, LAG(REVENUE) OVER (ORDER BY MONTH) AS PREV_MONTH, ROUND((REVENUE - LAG(REVENUE) OVER (ORDER BY MONTH))*100.0/NULLIF(LAG(REVENUE) OVER (ORDER BY MONTH),0),2) AS MOM_GROWTH_PCT FROM monthly ORDER BY 1'
    ),
    vq_top_customers_ltv AS (
      QUESTION 'Who are the top 10 customers by lifetime value?'
      SQL 'SELECT c.CUSTOMER_ID, c.FIRST_NAME||'' ''||c.LAST_NAME AS NAME, c.LOYALTY_TIER, SUM(o.TOTAL_SALES) AS LIFETIME_VALUE, COUNT(DISTINCT o.ORDER_ID) AS TOTAL_ORDERS FROM ECOM_DB.RAW.CUSTOMERS c JOIN ECOM_DB.RAW.FCT_ORDERS o ON c.CUSTOMER_ID = o.CUSTOMER_ID GROUP BY 1,2,3 ORDER BY 4 DESC LIMIT 10'
    )
  )
;

-- Verify semantic view created
SHOW SEMANTIC VIEWS IN SCHEMA ECOM_DB.RAW;
DESCRIBE SEMANTIC VIEW ECOM_DB.RAW.SV_ECOM_ANALYTICS;


-- ============================================================
-- SECTION 2: CREATE THE INTELLIGENCE AGENT
-- This agent will power all your Artifacts
-- ============================================================

CREATE OR REPLACE AGENT ECOM_DB.RAW.ECOM_ANALYTICS_AGENT
  COMMENT = 'ECommerce Analytics Agent for ANALYTICSWITHANAND — powered by Cortex Analyst + data_to_chart tool. Answers questions about Orders, Revenue, Inventory, Returns, and Customer KPIs.'
  PROFILE = '{
    "display_name": "EComm Analytics Agent",
    "color": "blue"
  }'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  orchestration:
    budget:
      seconds: 60
      tokens: 32000

  instructions:
    system: >
      You are an expert ECommerce data analyst for ANALYTICSWITHANAND.
      You have deep knowledge of the ECOM_DB.RAW schema which contains:
      FCT_ORDERS (orders, revenue, delivery), FCT_INVENTORY (stock levels, reorders),
      FCT_RETURNS (return reasons, refunds), CUSTOMERS (loyalty tiers, demographics),
      PRODUCTS (categories, brands), STORES (regions), SALES_CHANNELS (Online, Retail, Marketplace).
      Always provide actionable insights alongside data. When showing revenue use ₹ symbol.
      Default time period is 2024 (2024-01-01 to 2024-12-31) unless the user specifies otherwise.

    response: >
      Always respond with:
      1. A direct answer to the question with the key number/metric upfront
      2. A chart or table visualization (always use data_to_chart)
      3. A brief 2-3 line business insight or recommendation
      Keep answers concise and business-friendly. Use bullet points for lists.

    orchestration: >
      For any question about revenue, orders, customers, delivery, payment methods,
      categories, products, channels, or states — use the ecom_analyst tool.
      For any question about inventory, stock levels, reorder alerts, or shrinkage — use the ecom_analyst tool.
      For any question about returns, refunds, or return reasons — use the ecom_analyst tool.
      ALWAYS use data_to_chart to visualize the results.
      Prefer bar charts for comparisons, line charts for trends over time,
      pie/donut charts for proportions, and horizontal bar charts for rankings.

    sample_questions:
      - question: "What is the total revenue for 2024?"
        answer: "I'll query FCT_ORDERS and show the total revenue with a monthly trend chart."
      - question: "Which product category has the highest return rate?"
        answer: "I'll join FCT_ORDERS and FCT_RETURNS to calculate return rate by category."
      - question: "Show me the top 10 products by revenue"
        answer: "I'll rank products from FCT_ORDERS by total sales and show a horizontal bar chart."
      - question: "What is the loyalty tier distribution of our customers?"
        answer: "I'll query the CUSTOMERS table and show a donut chart of Bronze/Silver/Gold/Platinum tiers."
      - question: "How is inventory health across regions?"
        answer: "I'll summarize FCT_INVENTORY showing closing stock, reorder alerts, and shrinkage by region."
      - question: "Which states drive the most revenue?"
        answer: "I'll rank states from FCT_ORDERS and show a bar chart of top 15 states."
      - question: "What is month over month revenue growth in 2024?"
        answer: "I'll calculate MoM growth from FCT_ORDERS and display a line chart with growth %."
      - question: "Show revenue breakdown by payment method"
        answer: "I'll group FCT_ORDERS by PAYMENT_METHOD and show a bar chart."

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "ecom_analyst"
        description: >
          Use this tool for ALL structured data queries about the ECommerce business.
          This tool covers: revenue, orders, GMV, AOV, return rate, return reasons,
          inventory levels, reorder alerts, shrinkage, customer LTV, loyalty tiers,
          sales by channel (Online/Retail/Marketplace), sales by state, sales by category,
          top products, payment method analysis, and delivery performance.
          Data source: ECOM_DB.RAW tables (FCT_ORDERS, FCT_INVENTORY, FCT_RETURNS,
          CUSTOMERS, PRODUCTS, STORES, SALES_CHANNELS).
          Default date range: 2024-01-01 to 2024-12-31.
          Do NOT use this tool for unstructured text search.

    - tool_spec:
        type: "data_to_chart"
        name: "data_to_chart"
        description: >
          ALWAYS use this tool to visualize query results.
          Use bar charts for category/product comparisons,
          line charts for time-series trends (monthly/weekly revenue),
          donut/pie charts for distributions (loyalty tiers, channel mix, category share),
          horizontal bar charts for top-N rankings (top products, top states),
          and grouped bar charts for side-by-side comparisons.

  tool_resources:
    ecom_analyst:
      semantic_view: "ECOM_DB.RAW.SV_ECOM_ANALYTICS"
  $$;

-- Verify agent created
SHOW AGENTS IN SCHEMA ECOM_DB.RAW;
DESCRIBE AGENT ECOM_DB.RAW.ECOM_ANALYTICS_AGENT;


-- ============================================================
-- SECTION 3: GRANT AGENT ACCESS
-- Allow users to interact with the agent in Snowflake Intelligence
-- ============================================================

-- Grant USAGE on the agent to your role / other roles
GRANT USAGE ON AGENT ECOM_DB.RAW.ECOM_ANALYTICS_AGENT TO ROLE SYSADMIN;

-- If you have other roles/users who need access:
-- GRANT USAGE ON AGENT ECOM_DB.RAW.ECOM_ANALYTICS_AGENT TO ROLE <other_role>;

-- Grant SELECT on all tables so the agent can query them
GRANT SELECT ON ALL TABLES IN SCHEMA ECOM_DB.RAW TO ROLE SYSADMIN;
-- GRANT USAGE ON SEMANTIC VIEW ECOM_DB.RAW.SV_ECOM_ANALYTICS TO ROLE SYSADMIN;
GRANT CREATE SEMANTIC VIEW ON SCHEMA ECOM_DB.RAW TO ROLE SYSADMIN;


-- ============================================================
-- SECTION 4: VALIDATE — TEST QUERIES BEFORE USING IN ARTIFACTS
-- Run these in Snowsight Worksheets to confirm data is correct
-- ============================================================

-- KPI Summary
SELECT
    COUNT(DISTINCT ORDER_ID)                    AS TOTAL_ORDERS,
    ROUND(SUM(TOTAL_SALES)/1e6, 2)             AS REVENUE_M,
    ROUND(AVG(TOTAL_SALES), 2)                 AS AVG_ORDER_VALUE,
    COUNT(DISTINCT CUSTOMER_ID)                AS UNIQUE_CUSTOMERS,
    ROUND(AVG(DELIVERY_DAYS), 1)               AS AVG_DELIVERY_DAYS
FROM ECOM_DB.RAW.FCT_ORDERS
WHERE ORDER_DATE BETWEEN '2024-01-01' AND '2024-12-31';

-- Monthly Revenue Trend
SELECT
    DATE_TRUNC('MONTH', ORDER_DATE)::DATE AS MONTH,
    SUM(TOTAL_SALES)                      AS REVENUE
FROM ECOM_DB.RAW.FCT_ORDERS
WHERE ORDER_DATE BETWEEN '2024-01-01' AND '2024-12-31'
GROUP BY 1 ORDER BY 1;

-- Revenue by Category
SELECT CATEGORY, SUM(TOTAL_SALES) AS REVENUE
FROM ECOM_DB.RAW.FCT_ORDERS
GROUP BY 1 ORDER BY 2 DESC;

-- Return Rate by Category
SELECT
    o.CATEGORY,
    COUNT(DISTINCT o.ORDER_ID)  AS TOTAL_ORDERS,
    COUNT(DISTINCT r.RETURN_ID) AS RETURNS,
    ROUND(COUNT(DISTINCT r.RETURN_ID)*100.0/NULLIF(COUNT(DISTINCT o.ORDER_ID),0),2) AS RETURN_RATE_PCT
FROM ECOM_DB.RAW.FCT_ORDERS o
LEFT JOIN ECOM_DB.RAW.FCT_RETURNS r ON o.ORDER_ID = r.ORDER_ID
GROUP BY 1 ORDER BY 4 DESC;

-- Loyalty Tier Distribution
SELECT LOYALTY_TIER, COUNT(*) AS CUSTOMERS
FROM ECOM_DB.RAW.CUSTOMERS GROUP BY 1 ORDER BY 2 DESC;

-- Top 10 Products
SELECT PRODUCT_NAME, SUM(TOTAL_SALES) AS REVENUE
FROM ECOM_DB.RAW.FCT_ORDERS GROUP BY 1 ORDER BY 2 DESC LIMIT 10;

-- Revenue by State
SELECT STATE, SUM(TOTAL_SALES) AS REVENUE
FROM ECOM_DB.RAW.FCT_ORDERS GROUP BY 1 ORDER BY 2 DESC LIMIT 15;

-- Channel Mix
SELECT sc.CHANNEL_NAME, SUM(o.TOTAL_SALES) AS REVENUE, COUNT(DISTINCT o.ORDER_ID) AS ORDERS
FROM ECOM_DB.RAW.FCT_ORDERS o
LEFT JOIN ECOM_DB.RAW.SALES_CHANNELS sc ON o.CHANNEL_ID = sc.CHANNEL_ID
GROUP BY 1 ORDER BY 2 DESC;

-- Inventory Health
SELECT REGION_ID, SUM(CLOSING_STOCK) AS STOCK, SUM(REORDER_TRIGGERED) AS ALERTS, ROUND(AVG(SHRINKAGE),2) AS AVG_SHRINKAGE
FROM ECOM_DB.RAW.FCT_INVENTORY GROUP BY 1 ORDER BY 3 DESC;

-- MoM Revenue Growth
WITH monthly AS (
    SELECT DATE_TRUNC('MONTH', ORDER_DATE)::DATE AS MONTH,
           SUM(TOTAL_SALES) AS REVENUE
    FROM ECOM_DB.RAW.FCT_ORDERS
    WHERE ORDER_DATE BETWEEN '2024-01-01' AND '2024-12-31'
    GROUP BY 1
)
SELECT MONTH, REVENUE,
       LAG(REVENUE) OVER (ORDER BY MONTH)  AS PREV_MONTH,
       ROUND((REVENUE - LAG(REVENUE) OVER (ORDER BY MONTH))*100.0
             /NULLIF(LAG(REVENUE) OVER (ORDER BY MONTH),0), 2) AS MOM_GROWTH_PCT
FROM monthly ORDER BY 1;


-- ============================================================
-- SECTION 5: PROMPT LIBRARY
-- Copy-paste these exact questions into Snowflake Intelligence
-- chat to generate charts you can SAVE AS ARTIFACTS
-- ============================================================

/*
===== DASHBOARD ARTIFACTS =====

1. "Show me monthly revenue trend for 2024 as a line chart"
   → Save as Artifact: "Monthly Revenue Trend 2024"

2. "What is the revenue breakdown by product category for 2024? Show as a donut chart"
   → Save as Artifact: "Revenue by Category"

3. "Show total orders, revenue, average order value, unique customers,
    total returns, and average delivery days for 2024 as a summary table"
   → Save as Artifact: "Executive KPI Summary 2024"

===== ORDERS ARTIFACTS =====

4. "Show top 10 products by total revenue in 2024 as a horizontal bar chart"
   → Save as Artifact: "Top 10 Products by Revenue"

5. "What is revenue by sales channel for 2024? Show as a bar chart"
   → Save as Artifact: "Revenue by Sales Channel"

6. "Show revenue by payment method for 2024 as a bar chart"
   → Save as Artifact: "Revenue by Payment Method"

7. "Show order status breakdown for 2024 as a pie chart"
   → Save as Artifact: "Order Status Distribution"

8. "Which states have the highest revenue in 2024? Show top 15 as a horizontal bar chart"
   → Save as Artifact: "Revenue by State - Top 15"

===== INVENTORY ARTIFACTS =====

9. "Show reorder alerts by region from FCT_INVENTORY as a bar chart"
   → Save as Artifact: "Reorder Alerts by Region"

10. "What is the monthly opening vs closing stock trend in 2024?
     Show as a dual-line chart"
    → Save as Artifact: "Inventory Stock Trend 2024"

===== RETURNS ARTIFACTS =====

11. "What are the top return reasons in 2024? Show as a horizontal bar chart"
    → Save as Artifact: "Top Return Reasons"

12. "Show return rate by product category in 2024 as a bar chart"
    → Save as Artifact: "Return Rate by Category"

13. "Show returns breakdown by channel as a pie chart"
    → Save as Artifact: "Returns by Sales Channel"

===== CUSTOMERS ARTIFACTS =====

14. "Show customer loyalty tier distribution as a donut chart"
    → Save as Artifact: "Customer Loyalty Tier Mix"

15. "Which states have the most customers? Show top 12 as a bar chart"
    → Save as Artifact: "Customers by State"

16. "Who are the top 10 customers by lifetime value in 2024? Show as a table"
    → Save as Artifact: "Top 10 Customers by LTV"

===== AI INSIGHTS ARTIFACTS =====

17. "What is the month over month revenue growth rate in 2024? Show as a line chart"
    → Save as Artifact: "MoM Revenue Growth 2024"

18. "Compare revenue, order count and return rate side by side by category"
    → Save as Artifact: "Category Performance Scorecard"

19. "Show average delivery days by channel and state for 2024"
    → Save as Artifact: "Delivery Performance Analysis"

20. "What is the weekly revenue trend for Q4 2024?"
    → Save as Artifact: "Q4 Weekly Revenue Trend"
*/


-- ============================================================
-- SECTION 6: QUICK REFERENCE — AGENT MANAGEMENT COMMANDS
-- ============================================================

-- View your agent
SHOW AGENTS IN SCHEMA ECOM_DB.RAW;
DESCRIBE AGENT ECOM_DB.RAW.ECOM_ANALYTICS_AGENT;

-- Update agent instructions if needed
ALTER AGENT ECOM_DB.RAW.ECOM_ANALYTICS_AGENT
  SET FROM SPECIFICATION $$
  -- paste updated YAML spec here
  $$;

-- Drop agent (if needed)
-- DROP AGENT ECOM_DB.RAW.ECOM_ANALYTICS_AGENT;

-- View semantic view
DESCRIBE SEMANTIC VIEW ECOM_DB.RAW.SV_ECOM_ANALYTICS;

-- ############################################################
-- END OF SCRIPT
-- ############################################################