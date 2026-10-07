# Data Quality Pipeline Orchestrator for Snowflake stage file ingestion
# ============================================================
# main.py  —  Data Quality Pipeline Orchestrator
# ============================================================

import uuid
import traceback
from datetime import datetime, date
from dataclasses import dataclass, field
from typing import List, Optional
from snowflake.snowpark import Session
from snowflake.snowpark.context import get_active_session

# ── DQResult dataclass ─────────────────────────────────────────────────────
@dataclass
class DQResult:
    check_number:    int
    check_name:      str
    check_category:  str           # GATE | THRESHOLD | ADVISORY
    check_status:    str           # PASS | FAIL | WARN | SKIP
    column_name:     Optional[str] = None
    threshold_value: Optional[str] = None
    actual_value:    Optional[str] = None
    severity:        str           = 'HIGH'
    notes:           str           = ''


# ══════════════════════════════════════════════════════════════════════════════
# PIPELINE CONFIGURATION
# All thresholds and pointers are here — change only this section per team.
# ══════════════════════════════════════════════════════════════════════════════
CFG = {
    'stage': {
        'stage_name':          'S3_TRANSACTION_STAGE',
        'file_format_name':    'ANALYTICS_DB.RAW.CSV_FORMAT',
        'header_format_name':  'ANALYTICS_DB.RAW.CSV_FORMAT_NO_SKIP',
    },
    'target': {
        'full_path': 'ANALYTICS_DB.RAW.TRANSACTION'
    },
    'monitoring': {
        'database':                 'ANALYTICS_DB',
        'schema':                   'DQ_MONITORING',
        'file_processing_table':    'FILE_PROCESSING_LOG',
        'dq_metrics_table':         'DQ_METRICS_LOG',
        'email_recipient_table':    'EMAIL_RECIPIENT_LOG',
        'notification_integration': 'EMAIL_NOTIFICATION_INTEGRATION',
    },
    'dq': {
        # ── Gate thresholds (fail-fast checks) ────────────────────────────
        'min_file_size_bytes': 100,           # bytes  ← set 1048576 in production
        'min_column_count':    7,
        'required_columns': [
            'TRANSACTION_ID', 'CUSTOMER_ID', 'PRODUCT_ID',
            'TRANSACTION_DATE', 'AMOUNT', 'QUANTITY',
            'STATUS', 'REGION', 'CURRENCY',
        ],
        # ── Threshold checks ──────────────────────────────────────────────
        'min_row_count': 10,
        'max_null_pct':  30.0,               # % per column
        'column_dtype_map': {
            'TRANSACTION_ID':   'string',
            'CUSTOMER_ID':      'string',
            'PRODUCT_ID':       'string',
            'TRANSACTION_DATE': 'date',
            'AMOUNT':           'float',
            'QUANTITY':         'int',
            'STATUS':           'string',
            'REGION':           'string',
            'CURRENCY':         'string',
        },
        'pk_columns': ['TRANSACTION_ID'],
        'fk_checks': {
            'CUSTOMER_ID': 'ANALYTICS_DB.DIM.CUSTOMERS(CUSTOMER_ID)',
            'PRODUCT_ID':  'ANALYTICS_DB.DIM.PRODUCTS(PRODUCT_ID)',
        },
        # ── Advisory checks (warn only — file still loads) ────────────────
        'max_duplicate_row_pct': 5.0,
        'allowed_values': {
            'STATUS':   ['COMPLETED', 'PENDING', 'CANCELLED', 'REFUNDED'],
            'CURRENCY': ['USD', 'INR', 'EUR', 'GBP', 'AED'],
        },
        'numeric_range_checks': {
            'AMOUNT':   {'min': 0.01,  'max': 1000000.0},
            'QUANTITY': {'min': 1,     'max': 10000},
        },
        'date_range_checks': {
            'TRANSACTION_DATE': {'min': '2000-01-01', 'max': 'today'},
        },
    },
    'notification': {
        'subject_prefix': '[DQ ALERT] Data Quality Failure',
        'send_on':        ['FAILURE'],        # 'FAILURE' | 'ALL' | 'NONE'
        'team_name':      'DATA_ENGINEERING',
    },
}


# ══════════════════════════════════════════════════════════════════════════════
# HELPER — escape single quotes in any string going into SQL
# ══════════════════════════════════════════════════════════════════════════════
def sq(s):
    return str(s or '').replace("'", "''")


# ══════════════════════════════════════════════════════════════════════════════
# STAGE FILE LISTING
# ══════════════════════════════════════════════════════════════════════════════
def list_stage_files(session, stage: str) -> List[dict]:
    rows  = session.sql(f'LIST @{stage}').collect()
    files = []
    for r in rows:
        full_path = r['name']               # e.g. transactions/incoming/file_01.csv
        file_size = r['size']
        name      = full_path.split('/')[-1]
        if name.lower().endswith('.csv'):
            files.append({'name': name, 'size': int(file_size)})
    return files


# ══════════════════════════════════════════════════════════════════════════════
# TEMP TABLE LOADER (load file as all-VARCHAR for content checks)
# ══════════════════════════════════════════════════════════════════════════════
def load_to_temp(session, stage: str, fmt: str, file_name: str) -> str:
    tmp = f'TMP_DQ_{uuid.uuid4().hex[:8].upper()}'
    session.sql(f"""
        CREATE OR REPLACE TEMPORARY TABLE {tmp} AS
        SELECT
            $1::VARCHAR   AS TRANSACTION_ID,
            $2::VARCHAR   AS CUSTOMER_ID,
            $3::VARCHAR   AS PRODUCT_ID,
            $4::VARCHAR   AS TRANSACTION_DATE,
            $5::VARCHAR   AS AMOUNT,
            $6::VARCHAR   AS QUANTITY,
            $7::VARCHAR   AS STATUS,
            $8::VARCHAR   AS REGION,
            $9::VARCHAR   AS CURRENCY,
            $10::VARCHAR  AS CREATED_AT
        FROM @{stage}/{file_name} (FILE_FORMAT => {fmt})
    """).collect()
    return tmp


# ══════════════════════════════════════════════════════════════════════════════
# CHECK 1 — File Size Gate  [GATE | CRITICAL]
# ══════════════════════════════════════════════════════════════════════════════
def check_file_size(file_size: int, cfg: dict) -> List[DQResult]:
    threshold = cfg['dq']['min_file_size_bytes']
    status    = 'PASS' if file_size >= threshold else 'FAIL'
    return [DQResult(
        check_number=1, check_name='FILE_SIZE_CHECK',
        check_category='GATE', check_status=status,
        threshold_value=f'{threshold:,} bytes',
        actual_value=f'{file_size:,} bytes',
        severity='CRITICAL',
        notes=f'File size {file_size:,} bytes vs minimum {threshold:,} bytes',
    )]


# ══════════════════════════════════════════════════════════════════════════════
# CHECK 2 — Column Count Gate  [GATE | CRITICAL]
# ══════════════════════════════════════════════════════════════════════════════
def check_column_count(session, file_name: str, cfg: dict):
    threshold   = cfg['dq']['min_column_count']
    stage_name  = cfg['stage']['stage_name']
    header_fmt  = cfg['stage']['header_format_name']

    header_row = session.sql(f"""
        SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12
        FROM @{stage_name}/{file_name}
        (FILE_FORMAT => {header_fmt})
        LIMIT 1
    """).collect()

    if not header_row:
        col_count, header = 0, ''
    else:
        row   = header_row[0]
        vals  = [row[i] for i in range(12) if row[i] is not None]
        col_count = len(vals)
        header    = ','.join(str(v).strip() for v in vals)

    status = 'PASS' if col_count >= threshold else 'FAIL'
    return [DQResult(
        check_number=2, check_name='COLUMN_COUNT_CHECK',
        check_category='GATE', check_status=status,
        threshold_value=f'>= {threshold} columns',
        actual_value=f'{col_count} columns found',
        severity='CRITICAL',
        notes=f'{col_count} columns detected, need >= {threshold}',
    )], col_count, header


# ══════════════════════════════════════════════════════════════════════════════
# CHECK 3 — Required Column Names Gate  [GATE | CRITICAL]
# ══════════════════════════════════════════════════════════════════════════════
def check_required_columns(header: str, cfg: dict) -> List[DQResult]:
    required = [c.upper() for c in cfg['dq']['required_columns']]
    actual   = [c.strip().upper().strip('"') for c in header.split(',')]
    missing  = [r for r in required if r not in actual]
    status   = 'PASS' if not missing else 'FAIL'
    return [DQResult(
        check_number=3, check_name='REQUIRED_COLUMNS_CHECK',
        check_category='GATE', check_status=status,
        threshold_value=str(required),
        actual_value=str(actual),
        severity='CRITICAL',
        notes=f'Missing columns: {missing}' if missing else 'All required columns present',
    )]


# ══════════════════════════════════════════════════════════════════════════════
# CHECK 4 — Row Count Threshold  [THRESHOLD | HIGH]
# ══════════════════════════════════════════════════════════════════════════════
def check_row_count(session, tmp_table: str, cfg: dict):
    threshold = cfg['dq']['min_row_count']
    cnt       = session.sql(f'SELECT COUNT(*) AS CNT FROM {tmp_table}').collect()[0]['CNT']
    status    = 'PASS' if cnt >= threshold else 'FAIL'
    return [DQResult(
        check_number=4, check_name='ROW_COUNT_CHECK',
        check_category='THRESHOLD', check_status=status,
        threshold_value=f'>= {threshold} rows',
        actual_value=f'{cnt} rows',
        severity='HIGH',
        notes=f'{cnt} rows found, need >= {threshold}',
    )], int(cnt)


# ══════════════════════════════════════════════════════════════════════════════
# CHECK 5 — Null % per Column  [THRESHOLD | HIGH]
# BUG FIX: Renamed alias from NULLS (reserved keyword) to NULL_CNT
# ══════════════════════════════════════════════════════════════════════════════
def check_null_pct(session, tmp_table: str, cfg: dict) -> List[DQResult]:
    threshold = cfg['dq']['max_null_pct']
    columns   = list(cfg['dq']['column_dtype_map'].keys())
    results   = []
    for col_name in columns:
        row = session.sql(f"""
            SELECT
                COUNT(*) AS TOTAL,
                SUM(CASE WHEN {col_name} IS NULL
                              OR TRIM({col_name}) = ''
                         THEN 1 ELSE 0 END) AS NULL_CNT
            FROM {tmp_table}
        """).collect()[0]
        # ── BUG FIX: was row['NULLS'] — NULLS is a reserved keyword ──────
        total  = int(row['TOTAL'])
        nulls  = int(row['NULL_CNT'])
        pct    = round(nulls / total * 100, 1) if total > 0 else 0.0
        status = 'PASS' if pct <= threshold else 'FAIL'
        results.append(DQResult(
            check_number=5, check_name='NULL_COUNT_CHECK',
            check_category='THRESHOLD', check_status=status,
            column_name=col_name,
            threshold_value=f'max {threshold}% null',
            actual_value=f'{pct}% null ({nulls}/{total})',
            severity='CRITICAL' if pct > 50 else 'HIGH',
            notes=f'{nulls} of {total} rows have null/empty {col_name}',
        ))
    return results


# ══════════════════════════════════════════════════════════════════════════════
# CHECK 6 — Data Type Validation  [THRESHOLD | HIGH]
# ══════════════════════════════════════════════════════════════════════════════
def check_data_types(session, tmp_table: str, cfg: dict) -> List[DQResult]:
    dtype_map = cfg['dq']['column_dtype_map']
    cast_fn   = {
        'float':     lambda c: f'TRY_TO_DOUBLE({c})',
        'int':       lambda c: f'TRY_TO_NUMBER({c})',
        'date':      lambda c: f'TRY_TO_DATE({c})',
        'timestamp': lambda c: f'TRY_TO_TIMESTAMP({c})',
    }
    results = []
    for col_name, dtype in dtype_map.items():
        if dtype == 'string':
            results.append(DQResult(
                check_number=6, check_name='DATA_TYPE_CHECK',
                check_category='THRESHOLD', check_status='PASS',
                column_name=col_name, threshold_value='string',
                actual_value='string', severity='LOW',
                notes='String columns are skipped — no cast needed',
            ))
            continue
        cast_expr = cast_fn[dtype](col_name)
        row = session.sql(f"""
            SELECT SUM(
                CASE WHEN {cast_expr} IS NULL
                      AND {col_name} IS NOT NULL
                      AND TRIM({col_name}) != ''
                     THEN 1 ELSE 0 END
            ) AS BAD_CASTS
            FROM {tmp_table}
        """).collect()[0]
        bad    = int(row['BAD_CASTS'] or 0)
        status = 'PASS' if bad == 0 else 'FAIL'
        results.append(DQResult(
            check_number=6, check_name='DATA_TYPE_CHECK',
            check_category='THRESHOLD', check_status=status,
            column_name=col_name,
            threshold_value=f'castable to {dtype}',
            actual_value=f'{bad} non-castable rows',
            severity='HIGH',
            notes=f'{bad} rows in {col_name} cannot be cast to {dtype}',
        ))
    return results


# ══════════════════════════════════════════════════════════════════════════════
# CHECK 7 — Primary Key Uniqueness  [THRESHOLD | CRITICAL]
# ══════════════════════════════════════════════════════════════════════════════
def check_primary_key(session, tmp_table: str, cfg: dict) -> List[DQResult]:
    pk_cols = cfg['dq']['pk_columns']
    pk_expr = ', '.join(pk_cols)
    row  = session.sql(f"""
        SELECT COUNT(*) - COUNT(DISTINCT {pk_expr}) AS DUP_COUNT
        FROM {tmp_table}
    """).collect()[0]
    dups   = int(row['DUP_COUNT'] or 0)
    status = 'PASS' if dups == 0 else 'FAIL'
    return [DQResult(
        check_number=7, check_name='PK_UNIQUENESS_CHECK',
        check_category='THRESHOLD', check_status=status,
        column_name=pk_expr,
        threshold_value='0 duplicates',
        actual_value=f'{dups} duplicate PK values',
        severity='CRITICAL',
        notes=f'{dups} duplicate values found in PK column(s): {pk_cols}',
    )]


# ══════════════════════════════════════════════════════════════════════════════
# CHECK 8 — Foreign Key Constraint  [THRESHOLD | HIGH]
# ══════════════════════════════════════════════════════════════════════════════
def check_foreign_keys(session, tmp_table: str, cfg: dict) -> List[DQResult]:
    results = []
    for fk_col, ref in cfg['dq']['fk_checks'].items():
        ref_table = ref.split('(')[0]
        ref_col   = ref.split('(')[1].rstrip(')')
        row = session.sql(f"""
            SELECT COUNT(*) AS ORPHANS
            FROM {tmp_table} t
            LEFT JOIN {ref_table} d ON t.{fk_col} = d.{ref_col}
            WHERE t.{fk_col} IS NOT NULL
              AND d.{ref_col} IS NULL
        """).collect()[0]
        orphans = int(row['ORPHANS'] or 0)
        status  = 'PASS' if orphans == 0 else 'FAIL'
        results.append(DQResult(
            check_number=8, check_name='FOREIGN_KEY_CHECK',
            check_category='THRESHOLD', check_status=status,
            column_name=fk_col,
            threshold_value='0 orphan keys',
            actual_value=f'{orphans} orphan keys',
            severity='HIGH',
            notes=f'{orphans} {fk_col} values not found in {ref_table}',
        ))
    return results


# ══════════════════════════════════════════════════════════════════════════════
# CHECK 9 — Duplicate Rows  [ADVISORY | MEDIUM]
# ══════════════════════════════════════════════════════════════════════════════
def check_duplicate_rows(session, tmp_table: str, cfg: dict) -> List[DQResult]:
    threshold = cfg['dq']['max_duplicate_row_pct']
    row = session.sql(f"""
        WITH DUP_COUNTS AS (
            SELECT TRANSACTION_ID, COUNT(*) AS CNT
            FROM {tmp_table}
            GROUP BY TRANSACTION_ID
            HAVING COUNT(*) > 1
        ),
        SUMMARY AS (
            SELECT
                COALESCE(SUM(CNT), 0)      AS DUP_ROWS,
                (SELECT COUNT(*) FROM {tmp_table}) AS TOTAL
            FROM DUP_COUNTS
        )
        SELECT
            DUP_ROWS,
            TOTAL,
            ROUND(DUP_ROWS / NULLIF(TOTAL, 0) * 100, 1) AS DUP_PCT
        FROM SUMMARY
    """).collect()[0]
    pct    = float(row['DUP_PCT'] or 0.0)
    status = 'PASS' if pct <= threshold else 'WARN'
    return [DQResult(
        check_number=9, check_name='DUPLICATE_ROW_CHECK',
        check_category='ADVISORY', check_status=status,
        threshold_value=f'max {threshold}% duplicates',
        actual_value=f'{pct}%',
        severity='MEDIUM',
        notes=f'{int(row["DUP_ROWS"])} of {int(row["TOTAL"])} rows are exact duplicates',
    )]


# ══════════════════════════════════════════════════════════════════════════════
# CHECK 10 — Date Range Sanity  [ADVISORY | LOW]
# ══════════════════════════════════════════════════════════════════════════════
def check_date_range(session, tmp_table: str, cfg: dict) -> List[DQResult]:
    results = []
    today   = date.today().isoformat()
    for col_name, rng in cfg['dq']['date_range_checks'].items():
        min_d  = rng['min']
        max_d  = today if rng['max'] == 'today' else rng['max']
        row = session.sql(f"""
            SELECT COUNT(*) AS OUT_OF_RANGE
            FROM {tmp_table}
            WHERE TRY_TO_DATE({col_name}) IS NOT NULL
              AND (TRY_TO_DATE({col_name}) < '{min_d}'
                OR TRY_TO_DATE({col_name}) > '{max_d}')
        """).collect()[0]
        oor    = int(row['OUT_OF_RANGE'] or 0)
        status = 'PASS' if oor == 0 else 'WARN'
        results.append(DQResult(
            check_number=10, check_name='DATE_RANGE_CHECK',
            check_category='ADVISORY', check_status=status,
            column_name=col_name,
            threshold_value=f'{min_d} to {max_d}',
            actual_value=f'{oor} out-of-range rows',
            severity='LOW',
            notes=f'{oor} rows have {col_name} outside [{min_d}, {max_d}]',
        ))
    return results


# ══════════════════════════════════════════════════════════════════════════════
# CHECK 11 — Numeric Range  [ADVISORY | MEDIUM]
# ══════════════════════════════════════════════════════════════════════════════
def check_numeric_range(session, tmp_table: str, cfg: dict) -> List[DQResult]:
    results = []
    for col_name, rng in cfg['dq']['numeric_range_checks'].items():
        min_v, max_v = rng['min'], rng['max']
        row = session.sql(f"""
            SELECT COUNT(*) AS OUT_OF_RANGE
            FROM {tmp_table}
            WHERE TRY_TO_DOUBLE({col_name}) IS NOT NULL
              AND (TRY_TO_DOUBLE({col_name}) < {min_v}
                OR TRY_TO_DOUBLE({col_name}) > {max_v})
        """).collect()[0]
        oor    = int(row['OUT_OF_RANGE'] or 0)
        status = 'PASS' if oor == 0 else 'WARN'
        results.append(DQResult(
            check_number=11, check_name='NUMERIC_RANGE_CHECK',
            check_category='ADVISORY', check_status=status,
            column_name=col_name,
            threshold_value=f'{min_v} to {max_v}',
            actual_value=f'{oor} out-of-range rows',
            severity='MEDIUM',
            notes=f'{oor} {col_name} values outside [{min_v}, {max_v}]',
        ))
    return results


# ══════════════════════════════════════════════════════════════════════════════
# CHECK 12 — Allowed Values  [ADVISORY | LOW]
# ══════════════════════════════════════════════════════════════════════════════
def check_allowed_values(session, tmp_table: str, cfg: dict) -> List[DQResult]:
    results = []
    for col_name, allowed in cfg['dq']['allowed_values'].items():
        allowed_sql = ', '.join(f"'{v}'" for v in allowed)
        row = session.sql(f"""
            SELECT COUNT(*) AS BAD_VALS
            FROM {tmp_table}
            WHERE {col_name} IS NOT NULL
              AND UPPER(TRIM({col_name})) NOT IN ({allowed_sql})
        """).collect()[0]
        bad    = int(row['BAD_VALS'] or 0)
        status = 'PASS' if bad == 0 else 'WARN'
        results.append(DQResult(
            check_number=12, check_name='ALLOWED_VALUES_CHECK',
            check_category='ADVISORY', check_status=status,
            column_name=col_name,
            threshold_value=str(allowed),
            actual_value=f'{bad} invalid value rows',
            severity='LOW',
            notes=f'{bad} rows in {col_name} use values not in allowed list',
        ))
    return results


# ══════════════════════════════════════════════════════════════════════════════
# AUDIT LOGGER — writes to FILE_PROCESSING_LOG and DQ_METRICS_LOG
# ══════════════════════════════════════════════════════════════════════════════
def log_file_result(session, cfg, run_id, file_name, file_size,
                    row_count, col_count, status, reasons, rows_loaded) -> int:
    mon = cfg['monitoring']
    db, sch = mon['database'], mon['schema']
    tbl     = mon['file_processing_table']
    session.sql(f"""
        INSERT INTO {db}.{sch}.{tbl}
            (PIPELINE_RUN_ID, FILE_NAME, FILE_SIZE_BYTES, ROW_COUNT,
             COLUMN_COUNT, PROCESSING_STATUS, REJECTION_REASONS,
             ROWS_LOADED, TEAM_NAME)
        VALUES
            ('{sq(run_id)}', '{sq(file_name)}', {file_size}, {row_count},
             {col_count}, '{sq(status)}', '{sq(reasons)}',
             {rows_loaded}, '{sq(cfg["notification"]["team_name"])}')
    """).collect()
    log_id = session.sql(f"""
        SELECT MAX(LOG_ID) AS LID
        FROM {db}.{sch}.{tbl}
        WHERE PIPELINE_RUN_ID = '{sq(run_id)}'
          AND FILE_NAME        = '{sq(file_name)}'
    """).collect()[0]['LID']
    return int(log_id)


def log_dq_results(session, cfg, run_id, file_name, log_id,
                   results: List[DQResult]):
    mon = cfg['monitoring']
    db, sch = mon['database'], mon['schema']
    tbl     = mon['dq_metrics_table']
    for r in results:
        session.sql(f"""
            INSERT INTO {db}.{sch}.{tbl}
                (LOG_ID, PIPELINE_RUN_ID, FILE_NAME, CHECK_NUMBER,
                 CHECK_NAME, CHECK_CATEGORY, CHECK_STATUS, COLUMN_NAME,
                 THRESHOLD_VALUE, ACTUAL_VALUE, SEVERITY, NOTES)
            VALUES
                ({log_id}, '{sq(run_id)}', '{sq(file_name)}',
                 {r.check_number}, '{sq(r.check_name)}',
                 '{sq(r.check_category)}', '{sq(r.check_status)}',
                 '{sq(r.column_name or "N/A")}',
                 '{sq(r.threshold_value or "")}',
                 '{sq(r.actual_value or "")}',
                 '{sq(r.severity)}',
                 '{sq(r.notes)}')
        """).collect()


# ══════════════════════════════════════════════════════════════════════════════
# EMAIL NOTIFIER — sends alert via SYSTEM$SEND_EMAIL
# ══════════════════════════════════════════════════════════════════════════════
def send_alert(session, cfg, run_id, file_name, file_size,
               row_count, failed: List[DQResult]):
    if 'FAILURE' not in cfg['notification']['send_on']:
        return
    mon = cfg['monitoring']
    recipients = session.sql(f"""
        SELECT EMAIL_ADDRESS
        FROM {mon['database']}.{mon['schema']}.{mon['email_recipient_table']}
        WHERE IS_ACTIVE   = TRUE
          AND TEAM_NAME   = '{sq(cfg["notification"]["team_name"])}'
          AND NOTIFICATION_TYPE IN ('FAILURE', 'ALL')
    """).collect()
    if not recipients:
        print('    [NOTIFY] No active email recipients found — skipping email')
        return
    to_list = ', '.join(r['EMAIL_ADDRESS'] for r in recipients)
    ts      = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')
    subject = f"{cfg['notification']['subject_prefix']} — {file_name} — {ts}"
    failed_block = ''
    for f in failed:
        failed_block += f'Check #{f.check_number} — {f.check_name}  [{f.severity}]\n'
        if f.column_name:     failed_block += f'  Column    : {f.column_name}\n'
        if f.threshold_value: failed_block += f'  Threshold : {f.threshold_value}\n'
        if f.actual_value:    failed_block += f'  Actual    : {f.actual_value}\n'
        if f.notes:           failed_block += f'  Notes     : {f.notes}\n'
        failed_block += '\n'
    body = (
        f'Pipeline Run ID : {run_id}\n'
        f'Team            : {cfg["notification"]["team_name"]}\n'
        f'File            : {file_name}\n'
        f'File Size       : {file_size:,} bytes\n'
        f'Row Count       : {row_count}\n'
        f'Status          : REJECTED\n\n'
        f'FAILED CHECKS\n'
        f'{"=" * 60}\n'
        f'{failed_block}'
        f'ACTION: File quarantined in S3. Fix data and re-upload.\n\n'
        f'Audit query:\n'
        f"  SELECT * FROM ANALYTICS_DB.DQ_MONITORING.DQ_METRICS_LOG\n"
        f"  WHERE FILE_NAME = '{file_name}' ORDER BY CHECK_NUMBER;\n"
    )
    try:
        session.sql(f"""
            CALL SYSTEM$SEND_EMAIL(
                '{mon["notification_integration"]}',
                '{sq(to_list)}',
                '{sq(subject)}',
                '{sq(body)}'
            )
        """).collect()
        print(f'    [NOTIFY] Email sent to: {to_list}')
    except Exception as e:
        print(f'    [NOTIFY] Email failed (check integration): {e}')


# ══════════════════════════════════════════════════════════════════════════════
# FILE MOVER — copies file between stages then removes from source
# ══════════════════════════════════════════════════════════════════════════════
def move_file(session, stage_name: str, file_name: str, dest_folder: str):
    src  = f'ANALYTICS_DB.RAW.{stage_name}'
    dest = f'ANALYTICS_DB.RAW.{stage_name}_{dest_folder.upper()}'
    try:
        session.sql(f"""
            COPY FILES
            INTO @{dest}
            FROM @{src}
            FILES = ('{sq(file_name)}')
        """).collect()
        session.sql(f"REMOVE @{src}/{sq(file_name)}").collect()
        print(f'    [MOVE] {file_name}  →  /{dest_folder}/')
    except Exception as e:
        print(f'    [MOVE WARN] Could not move {file_name}: {e}')


# ══════════════════════════════════════════════════════════════════════════════
# COPY INTO — loads passing file from stage to RAW.TRANSACTION
# ══════════════════════════════════════════════════════════════════════════════
def copy_into_raw(session, cfg, stage, fmt, file_name, run_id) -> int:
    target = cfg['target']['full_path']
    result = session.sql(f"""
        COPY INTO {target}
            (TRANSACTION_ID, CUSTOMER_ID, PRODUCT_ID,
             TRANSACTION_DATE, AMOUNT, QUANTITY,
             STATUS, REGION, CURRENCY,
             _DQ_PIPELINE_RUN_ID, _SOURCE_FILE_NAME)
        FROM (
            SELECT
                $1::VARCHAR,  $2::VARCHAR,  $3::VARCHAR,
                $4::DATE,     $5::FLOAT,    $6::INT,
                $7::VARCHAR,  $8::VARCHAR,  $9::VARCHAR,
                '{sq(run_id)}', '{sq(file_name)}'
            FROM @{stage}/{file_name} (FILE_FORMAT => {fmt})
        )
        FORCE         = FALSE
        ON_ERROR      = ABORT_STATEMENT
    """).collect()
    return int(result[0]['rows_loaded']) if result else 0


# ══════════════════════════════════════════════════════════════════════════════
# MAIN ENTRY POINT
# ══════════════════════════════════════════════════════════════════════════════
def main(session):

    # Set session context explicitly — avoids unresolved object name errors
    session.use_database("ANALYTICS_DB")
    session.use_schema("RAW")

    cfg       = CFG
    run_id    = str(uuid.uuid4())
    stage     = cfg['stage']['stage_name']
    fmt       = cfg['stage']['file_format_name']
    summary   = {'total': 0, 'passed': 0, 'rejected': 0, 'rows_loaded': 0}

    print('=' * 65)
    print(f'  DQ PIPELINE STARTED')
    print(f'  Pipeline Run ID : {run_id}')
    print(f'  Timestamp       : {datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")}')
    print('=' * 65)

    # ── List files from stage ─────────────────────────────────────────────
    try:
        files = list_stage_files(session, stage)
    except Exception as e:
        print(f'ERROR listing stage files: {e}')
        print(traceback.format_exc())
        return session.create_dataframe(
            [['ERROR', 0, 0, 0, 0]],
            schema=['RUN_ID', 'TOTAL', 'PASSED', 'REJECTED', 'ROWS_LOADED'],
        )

    summary['total'] = len(files)
    print(f'  Files found in stage: {len(files)}')
    for f in files:
        print(f'    {f["name"]:<50}  {f["size"]:>8,} bytes')
    print()

    # ── Process each file ─────────────────────────────────────────────────
    for f in files:
        file_name = f['name']
        file_size = f['size']
        print("-" * 60)
        print(f'  Processing: {file_name}  ({file_size:,} bytes)')

        all_results   : List[DQResult] = []
        failed_checks : List[DQResult] = []
        row_count  = 0
        col_count  = 0
        tmp_table  = None

        try:
            # ── GATE CHECKS ─────────────────────────────────────────────
            r1 = check_file_size(file_size, cfg)
            all_results.extend(r1)
            if any(r.check_status == 'FAIL' for r in r1):
                failed_checks += [r for r in r1 if r.check_status == 'FAIL']
                raise StopIteration('Check 1 FAILED: file size below threshold')

            r2, col_count, header = check_column_count(session, file_name, cfg)
            all_results.extend(r2)
            if any(r.check_status == 'FAIL' for r in r2):
                failed_checks += [r for r in r2 if r.check_status == 'FAIL']
                raise StopIteration('Check 2 FAILED: column count below threshold')

            r3 = check_required_columns(header, cfg)
            all_results.extend(r3)
            if any(r.check_status == 'FAIL' for r in r3):
                failed_checks += [r for r in r3 if r.check_status == 'FAIL']
                raise StopIteration('Check 3 FAILED: required columns missing')

            # ── Load file to temp table for content-based checks ─────────
            tmp_table = load_to_temp(session, stage, fmt, file_name)

            # ── THRESHOLD CHECKS ─────────────────────────────────────────
            r4, row_count = check_row_count(session, tmp_table, cfg)
            all_results.extend(r4)
            if any(r.check_status == 'FAIL' for r in r4):
                failed_checks += [r for r in r4 if r.check_status == 'FAIL']
                raise StopIteration('Check 4 FAILED: row count below threshold')

            r5 = check_null_pct(session, tmp_table, cfg)
            all_results.extend(r5)
            if any(r.check_status == 'FAIL' for r in r5):
                failed_checks += [r for r in r5 if r.check_status == 'FAIL']
                raise StopIteration('Check 5 FAILED: null % exceeds threshold')

            r6 = check_data_types(session, tmp_table, cfg)
            all_results.extend(r6)
            if any(r.check_status == 'FAIL' for r in r6):
                failed_checks += [r for r in r6 if r.check_status == 'FAIL']
                raise StopIteration('Check 6 FAILED: data type cast failures')

            r7 = check_primary_key(session, tmp_table, cfg)
            all_results.extend(r7)
            if any(r.check_status == 'FAIL' for r in r7):
                failed_checks += [r for r in r7 if r.check_status == 'FAIL']
                raise StopIteration('Check 7 FAILED: primary key duplicates found')

            r8 = check_foreign_keys(session, tmp_table, cfg)
            all_results.extend(r8)
            if any(r.check_status == 'FAIL' for r in r8):
                failed_checks += [r for r in r8 if r.check_status == 'FAIL']
                raise StopIteration('Check 8 FAILED: foreign key violations found')

            # ── ADVISORY CHECKS (warn only — file still loads) ────────────
            all_results.extend(check_duplicate_rows(session, tmp_table, cfg))
            all_results.extend(check_date_range(session, tmp_table, cfg))
            all_results.extend(check_numeric_range(session, tmp_table, cfg))
            all_results.extend(check_allowed_values(session, tmp_table, cfg))

            # ── ALL CHECKS PASSED: load to RAW ───────────────────────────
            rows_loaded = copy_into_raw(session, cfg, stage, fmt, file_name, run_id)
            log_id = log_file_result(
                session, cfg, run_id, file_name,
                file_size, row_count, col_count,
                'PASSED', '', rows_loaded,
            )
            log_dq_results(session, cfg, run_id, file_name, log_id, all_results)
            move_file(session, stage, file_name, 'processed')
            summary['passed']      += 1
            summary['rows_loaded'] += rows_loaded
            print(f'    STATUS: PASSED  |  {rows_loaded:,} rows loaded into RAW.TRANSACTION')

        except StopIteration as rejection_msg:
            # ── DQ CHECK FAILURE: log, notify, quarantine ────────────────
            reasons = ' | '.join(
                f'Check{r.check_number}:{r.check_name}' for r in failed_checks
            )
            try:
                log_id = log_file_result(
                    session, cfg, run_id, file_name,
                    file_size, row_count, col_count,
                    'REJECTED', reasons, 0,
                )
                log_dq_results(session, cfg, run_id, file_name, log_id, all_results)
                send_alert(
                    session, cfg, run_id, file_name,
                    file_size, row_count, failed_checks,
                )
            except Exception as log_err:
                print(f'    [LOG ERROR] Could not write audit log: {log_err}')
            move_file(session, stage, file_name, 'quarantine')
            summary['rejected'] += 1
            print(f'    STATUS: REJECTED  |  {rejection_msg}')

        except Exception as unexpected:
            # ── UNEXPECTED CODE / SQL ERROR ──────────────────────────────
            print(f'    [UNEXPECTED ERROR] {file_name}')
            print(f'    {type(unexpected).__name__}: {unexpected}')
            print('    Full traceback:')
            for line in traceback.format_exc().splitlines():
                print(f'    {line}')
            try:
                log_file_result(
                    session, cfg, run_id, file_name,
                    file_size, row_count, col_count,
                    'REJECTED', f'UNEXPECTED_ERROR: {type(unexpected).__name__}: {unexpected}', 0,
                )
            except Exception:
                pass
            summary['rejected'] += 1

    # ── PIPELINE SUMMARY ─────────────────────────────────────────────────
    print()
    print('=' * 65)
    print(f'  PIPELINE RUN COMPLETE')
    print(f'  Run ID      : {run_id}')
    print(f'  Total Files : {summary["total"]}')
    print(f'  Passed      : {summary["passed"]}')
    print(f'  Rejected    : {summary["rejected"]}')
    print(f'  Rows Loaded : {summary["rows_loaded"]:,}')
    print('=' * 65)
    print()
    print('Copy the Run ID above and use it in the audit queries in')
    print('01_ddl_setup.sql:  SET RUN_ID = \'<paste here>\';')

    return session.create_dataframe(
        [[run_id, summary['total'], summary['passed'],
          summary['rejected'], summary['rows_loaded']]],
        schema=['RUN_ID', 'TOTAL_FILES', 'PASSED', 'REJECTED', 'ROWS_LOADED'],
    )

session = get_active_session()
result = main(session)
result.show()
