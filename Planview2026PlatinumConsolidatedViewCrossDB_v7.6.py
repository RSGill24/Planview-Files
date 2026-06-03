"""
Planview2026PlatinumConsolidatedViewCrossDB.py
===============================================
v7 — Adds SP2 (Consolidated_Transform_Logic) and
     New SP (usp_Planview_PQ_Transformation) to the pipeline.

Execution order:
  1. Read cross-DB views → load input_{ts} schema
  2. Call SP2  → creates output_{ts} schema tables (Flow Type, EVR, Stage)
  3. Call SP1  → value mappings (Work Status, EAV, Home Portfolio, etc.)
              → merge SP1 columns into output_{ts} tables
  4. Call New SP → PQ blocks (Disposition, Approvals, Status, Parent Seq ID,
                              Epic parent, Execution Type, Other Portfolios)
              → mutates output_{ts} tables directly
  5. Read final output_{ts} tables → save to PlanviewMigration_Output schema
"""

import pandas as pd
import pyodbc
import json
import argparse
import sys
import io
import re
import logging
from pathlib import Path
from datetime import datetime

# ── Config globals ─────────────────────────────────────────────
VIEW_INITIATIVES  = "vw_Initiatives"
VIEW_EPICS        = "vw_Epics"
VIEW_SBA          = "vw_SBA"
VIEW_TASKS        = "vw_Tasks"
VIEW_SCHEMA       = "dbo"
VIEW_DATABASE     = ""
OUTPUT_FOLDER     = ""
SQL_SERVER        = ""
SQL_DATABASE      = ""
NRB_FIELD         = "L1 Net Recurring Benefits ($, annualized)-P&L/Hard"
NRB_THRESHOLD_M   = 10
WORK_HIERARCHY_TABLE = "dbo.ref_WorkHierarchy"
COLUMN_RENAME        = {"Initiatives": {}, "Epics": {}, "Value_Bundles": {}}
DEV_PPL1_TABLE       = "dbo.ref_DevPPL1"
_logger           = None
SEPARATOR         = "=" * 60


# ── Logging ───────────────────────────────────────────────────
def init_logger(ts, out_folder):
    global _logger
    Path(out_folder).mkdir(parents=True, exist_ok=True)
    log_file = Path(out_folder) / f"prod_pipeline_run_{ts}.log"
    _logger = logging.getLogger("prod_pipeline")
    _logger.setLevel(logging.DEBUG)
    _logger.handlers.clear()
    fh = logging.FileHandler(log_file, encoding="utf-8")
    fh.setFormatter(logging.Formatter("%(asctime)s  %(message)s",
                                       datefmt="%Y-%m-%d %H:%M:%S"))
    _logger.addHandler(fh)
    ch = logging.StreamHandler(sys.stdout)
    ch.setFormatter(logging.Formatter("%(message)s"))
    _logger.addHandler(ch)
    return log_file

def log(msg, indent=0):
    line = "  " * indent + msg
    _logger.info(line) if _logger else print(line)

def log_step(n, msg):
    _logger.info(f"\n[{n}] {msg}") if _logger else print(f"\n[{n}] {msg}")


# ── Config loader ─────────────────────────────────────────────
def load_config(config_path=None):
    global VIEW_INITIATIVES, VIEW_EPICS, VIEW_SBA, VIEW_TASKS
    global VIEW_SCHEMA, VIEW_DATABASE
    global OUTPUT_FOLDER, SQL_SERVER, SQL_DATABASE, NRB_FIELD, NRB_THRESHOLD_M
    global WORK_HIERARCHY_TABLE, DEV_PPL1_TABLE, COLUMN_RENAME

    if config_path is None:
        config_path = Path(__file__).parent / "Planview2026PlatinumConsolidated_ViewCrossDB_config.json"
    config_path = Path(config_path)
    if not config_path.exists():
        print(f"ERROR: Config not found: {config_path}"); sys.exit(1)
    try:
        with open(config_path, encoding="utf-8") as f:
            cfg = json.load(f)
    except json.JSONDecodeError as e:
        print(f"ERROR: Bad JSON: {e}"); sys.exit(1)

    OUTPUT_FOLDER        = cfg["output_folder"]
    SQL_SERVER           = cfg.get("sql", {}).get("server", "")
    SQL_DATABASE         = cfg.get("sql", {}).get("database", "")
    VIEW_DATABASE        = cfg.get("sql", {}).get("view_database", "")
    VIEW_SCHEMA          = cfg.get("view_schema", "dbo")
    VIEW_INITIATIVES     = cfg.get("view_initiatives", "vw_Initiatives")
    VIEW_EPICS           = cfg.get("view_epics",       "vw_Epics")
    VIEW_SBA             = cfg.get("view_sba",         "vw_SBA")
    VIEW_TASKS           = cfg.get("view_tasks",       "vw_Tasks")
    NRB_FIELD            = cfg.get("nrb_field",
                                   "L1 Net Recurring Benefits ($, annualized)-P&L/Hard")
    NRB_THRESHOLD_M      = cfg.get("nrb_threshold_m", 10)
    WORK_HIERARCHY_TABLE = cfg.get("work_hierarchy_table", "dbo.ref_WorkHierarchy")
    DEV_PPL1_TABLE       = cfg.get("dev_ppl1_table",       "dbo.ref_DevPPL1")
    raw_rename           = cfg.get("column_rename", {})
    def _clean_rename(d):
        # Strip whitespace from both keys and values to avoid invisible mismatch
        return {k.strip(): v.strip() for k, v in d.items()} if d else {}
    COLUMN_RENAME        = {
        "Initiatives":   _clean_rename(raw_rename.get("Initiatives",   {})),
        "Epics":         _clean_rename(raw_rename.get("Epics",         {})),
        "Value_Bundles": _clean_rename(raw_rename.get("Value_Bundles", {})),
        "Tasks":         _clean_rename(raw_rename.get("Tasks",         {})),
    }


# ── Read from SQL view (cross-database) ──────────────────────
def read_from_view(conn, view_name):
    if not view_name or not view_name.strip():
        log(f"  [skipped — view name not configured]", 1)
        return pd.DataFrame(), {}
    if VIEW_DATABASE:
        full_name = f"[{VIEW_DATABASE}].[{VIEW_SCHEMA}].[{view_name}]"
    else:
        full_name = f"[{view_name}]"
    try:
        cursor = conn.cursor()
        try:
            cursor.execute(f"SELECT * FROM {full_name}")
        except Exception as fetch_e:
            log(f"  Warning: direct SELECT failed for {full_name}: {fetch_e}", 1)
            log(f"  Retrying with EXEC approach...", 1)
            cursor.execute(f"EXEC('SELECT * FROM {full_name}')")

        col_descriptions = cursor.description
        cols = [col[0] for col in col_descriptions]
        rows = cursor.fetchall()
        df = pd.DataFrame.from_records([tuple(r) for r in rows], columns=cols)

        import decimal, datetime as dt_mod
        type_map = {}
        try:
            for col_desc in col_descriptions:
                col_name  = col_desc[0]
                type_code = col_desc[1]
                if type_code is decimal.Decimal:
                    prec  = col_desc[4] or 20
                    scale = col_desc[5] or 2
                    type_map[col_name] = f'decimal({prec},{scale})'
                elif type_code is dt_mod.datetime:
                    type_map[col_name] = 'datetime'
                elif type_code is int:
                    type_map[col_name] = 'bigint'
                elif type_code is float:
                    type_map[col_name] = 'float'
                else:
                    type_map[col_name] = 'nvarchar(MAX)'
        except Exception as meta_e:
            log(f"  Warning: could not build type_map for [{view_name}]: {meta_e}", 1)
            type_map = {col: 'nvarchar(MAX)' for col in cols}

        log(f"  {full_name} — {len(df):,} rows | {len(df.columns)} cols", 1)
        return df, type_map
    except Exception as e:
        log(f"ERROR reading view {full_name}: {e}", 1)
        sys.exit(1)


# ── SQL: Connect ──────────────────────────────────────────────
def connect_sql():
    log_step("2/7", "Connecting to SQL Server...")
    try:
        conn = pyodbc.connect(
            f"DRIVER={{ODBC Driver 17 for SQL Server}};"
            f"SERVER={SQL_SERVER};DATABASE={SQL_DATABASE};"
            f"Trusted_Connection=yes;Connection Timeout=30;"
        )
        conn.autocommit = True
        log(f"Server   : {SQL_SERVER} / {SQL_DATABASE}", 1)
        log("Status   : Connected", 1)
        return conn
    except pyodbc.Error as e:
        log(f"ERROR: Could not connect to SQL Server: {e}", 1)
        sys.exit(1)


# ── SQL column name sanitiser ─────────────────────────────────
def _sql_col(name):
    clean = (str(name)
             .replace(']', '')
             .replace('[', '')
             .replace(',', '_')
             .replace('/', '_')
             .replace('\\', '_')
             .replace(':', '_')
             .replace('(', '')
             .replace(')', '')
             .strip())
    return clean[:120]


def _sql_type(series):
    import pandas as pd
    dtype = series.dtype
    if pd.api.types.is_integer_dtype(dtype):
        return 'bigint'
    elif pd.api.types.is_float_dtype(dtype):
        return 'decimal(20,2)'
    elif pd.api.types.is_datetime64_any_dtype(dtype):
        return 'datetime'
    elif pd.api.types.is_bool_dtype(dtype):
        return 'bit'
    else:
        return 'nvarchar(MAX)'


# ── SQL: Load single dataframe into a table ───────────────────
def load_to_sql(conn, df, schema_name, table_name, ts, type_map=None):
    cursor = conn.cursor()
    cursor.execute(f"""
        IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name='{schema_name}')
            EXEC('CREATE SCHEMA [{schema_name}]')
    """)
    cursor.execute(f"""
        IF OBJECT_ID('[{schema_name}].[{table_name}]') IS NOT NULL
            DROP TABLE [{schema_name}].[{table_name}]
    """)

    safe_cols = [_sql_col(c) for c in df.columns]
    seen = {}
    final_cols = []
    for c in safe_cols:
        if c in seen:
            seen[c] += 1
            c = f"{c}_{seen[c]}"
        else:
            seen[c] = 0
        final_cols.append(c)
    df = df.copy()
    df.columns = final_cols
    df = df.drop(columns=[c for c in ['Run_ID', 'Load_Timestamp', 'Save_Timestamp']
                           if c in df.columns])

    col_defs = ", ".join([f"[{c}] nvarchar(MAX)" for c in df.columns])
    cursor.execute(f"""
        CREATE TABLE [{schema_name}].[{table_name}] (
            {col_defs}
        )
    """)
    col_names    = ", ".join([f"[{c}]" for c in final_cols])
    placeholders = ", ".join(["?" for _ in final_cols])
    ins = (
        f"INSERT INTO [{schema_name}].[{table_name}] "
        f"({col_names}) "
        f"VALUES ({placeholders})"
    )
    import math, datetime as dt_mod

    def to_str(v):
        if v is None:
            return None
        if isinstance(v, float) and (math.isnan(v) or math.isinf(v)):
            return None
        if isinstance(v, (dt_mod.datetime, dt_mod.date)):
            return str(v).strip() or None
        s = str(v).strip()
        if s.upper() in ('NULL', 'NONE', 'NAT', 'NAN') or s == '':
            return None
        return (s.replace("\n", " ").replace("\r", " ")
                 .replace("|", " ").replace('"', "'"))

    rows = []
    for _, row in df.iterrows():
        rows.append(tuple(to_str(v) for v in row))

    conn.autocommit = False
    try:
        for i in range(0, len(rows), 500):
            cursor.executemany(ins, rows[i:i+500])
        conn.commit()
    except Exception as e:
        conn.rollback(); raise
    finally:
        conn.autocommit = True
    log(f"  [{schema_name}].[{table_name}] — {len(rows):,} rows loaded", 1)


# ── SQL: Deduplicate input table on a key column ──────────────
def dedup_input_table(conn, schema, table, key_col, label):
    cursor = conn.cursor()
    full_table = f"[{schema}].[{table}]"
    cursor.execute(f"""
        SELECT COUNT(*) FROM sys.columns
        WHERE object_id = OBJECT_ID('{schema}.{table}')
        AND name = '{key_col}'
    """)
    if cursor.fetchone()[0] == 0:
        log(f"  Dedup skipped — [{key_col}] not found in {label}", 1)
        return
    cursor.execute(f"""
        SELECT COUNT(*) - COUNT(DISTINCT [{key_col}])
        FROM {full_table}
        WHERE [{key_col}] IS NOT NULL AND LTRIM(RTRIM([{key_col}])) <> ''
    """)
    dup_count = cursor.fetchone()[0]
    if dup_count > 0:
        cursor.execute(f"""
            WITH CTE AS (
                SELECT ROW_NUMBER() OVER (
                    PARTITION BY [{key_col}]
                    ORDER BY (SELECT NULL)
                ) AS rn
                FROM {full_table}
                WHERE LTRIM(RTRIM(ISNULL([{key_col}], ''))) <> ''
            )
            DELETE FROM CTE WHERE rn > 1
        """)
        conn.commit()
        log(f"  Dedup — {label}: removed {dup_count:,} duplicate rows", 1)
    else:
        log(f"  Dedup — {label}: no duplicates found", 1)


# ── Apply column renames from config ─────────────────────────────
def apply_column_rename(df, entity):
    """
    Renames DataFrame columns using the column_rename map from config.
    Uses direct pandas .rename() — same approach as the working
    ConsolidatedTransformLogic_ViewCrossDB script.
    Keys that do not exist in the DataFrame are silently ignored.
    """
    rename_map = COLUMN_RENAME.get(entity, {})
    if not rename_map or df.empty:
        return df
    df = df.rename(columns=rename_map)
    applied = {k: v for k, v in rename_map.items() if k in df.columns or v in df.columns}
    if rename_map:
        log(f"  Column rename [{entity}]: {len(rename_map)} mappings in config", 2)
        for k, v in rename_map.items():
            if v in df.columns:
                log(f"    '{k}' → '{v}' ✓ applied", 2)
            else:
                log(f"    '{k}' → '{v}' — key not found in view (skipped)", 2)
    return df


# ── SQL: Load raw input into input schema ─────────────────────
def create_input_schema_and_load(conn, df_inits, df_epics, df_sba, df_tasks, ts,
                                  type_map_init=None, type_map_epic=None,
                                  type_map_sba=None, type_map_task=None):
    log_step("2a/7", "Loading view data to SQL Server input schema...")
    schema   = f"input_{ts}"
    stem     = "Planview_View"
    tbl_init = f"{stem}_Initiatives"
    tbl_epic = f"{stem}_Epics"
    tbl_sba  = f"{stem}_SBA"
    tbl_task = f"{stem}_Tasks"
    cursor   = conn.cursor()

    # ── Load base tables (SP2 reads these: Initiatives / Epics / Value_Bundles)
    load_to_sql(conn, df_inits, schema, "Initiatives",   ts, type_map_init)
    load_to_sql(conn, df_epics, schema, "Epics",         ts, type_map_epic)
    if not df_sba.empty:
        load_to_sql(conn, df_sba, schema, "Value_Bundles", ts, type_map_sba)
    else:
        log(f"  SBA view not configured — creating empty placeholder", 1)
        cursor.execute(f"""
            IF OBJECT_ID('[{schema}].[Value_Bundles]') IS NOT NULL
                DROP TABLE [{schema}].[Value_Bundles]
            CREATE TABLE [{schema}].[Value_Bundles] ([_placeholder] nvarchar(10) NULL)
        """)
        conn.commit()

    # ── Create SP1 stem tables via SELECT INTO — avoids re-reading views
    # SP1 reads {stem}_Initiatives / {stem}_Epics / {stem}_Tasks
    for base, stem_tbl in [("Initiatives", tbl_init), ("Epics", tbl_epic)]:
        cursor.execute(f"""
            IF OBJECT_ID('[{schema}].[{stem_tbl}]') IS NOT NULL
                DROP TABLE [{schema}].[{stem_tbl}]
        """)
        cursor.execute(f"""
            SELECT * INTO [{schema}].[{stem_tbl}] FROM [{schema}].[{base}]
        """)
        conn.commit()
        log(f"  [{schema}].[{stem_tbl}] — created from [{base}]", 1)

    # ── Tasks — loaded directly under stem name (SP1 needs {stem}_Tasks)
    if not df_tasks.empty:
        load_to_sql(conn, df_tasks, schema, tbl_task, ts, type_map_task)
    else:
        log(f"  Tasks view not configured — creating empty placeholder", 1)
        cursor.execute(f"""
            IF OBJECT_ID('[{schema}].[{tbl_task}]') IS NOT NULL
                DROP TABLE [{schema}].[{tbl_task}]
            CREATE TABLE [{schema}].[{tbl_task}] ([_placeholder] nvarchar(10) NULL)
        """)
        conn.commit()

    # ── Deduplicate base tables in SQL
    log("Deduplicating input tables in SQL...", 1)
    dedup_input_table(conn, schema, "Initiatives",  "Strategy Seq ID", "Initiatives")
    dedup_input_table(conn, schema, "Epics",        "Sequence ID",     "Epics")

    log(f"Input schema : [{schema}]", 1)
    return schema, stem


def run_sp2(conn, ts):
    """
    SP2 creates output_{ts} schema and writes:
      output_{ts}.Initiatives  — Index_ID, Flow Type, EVR, Stage remapped
      output_{ts}.Epics        — Index_ID passthrough
      output_{ts}.Value_Bundles — Index_ID passthrough
    Returns the 3 result set DataFrames.
    """
    log_step("3/7", "Running SP2 — Consolidated_Transform_Logic...")
    cursor = conn.cursor()
    cursor.execute(
        "EXEC dbo.Consolidated_Transform_LogicV2 @run_ts=?", ts
    )

    # RS1: Initiatives
    cols = [d[0] for d in cursor.description]
    df_init_sp2 = pd.DataFrame.from_records(
        [tuple(r) for r in cursor.fetchall()], columns=cols
    )
    df_init_sp2 = df_init_sp2.drop(
        columns=[c for c in ['Run_ID', 'Load_Timestamp'] if c in df_init_sp2.columns]
    )

    # RS2: Epics
    cursor.nextset()
    cols = [d[0] for d in cursor.description]
    df_epic_sp2 = pd.DataFrame.from_records(
        [tuple(r) for r in cursor.fetchall()], columns=cols
    )
    df_epic_sp2 = df_epic_sp2.drop(
        columns=[c for c in ['Run_ID', 'Load_Timestamp'] if c in df_epic_sp2.columns]
    )

    # RS3: Value_Bundles
    cursor.nextset()
    cols = [d[0] for d in cursor.description]
    df_vb_sp2 = pd.DataFrame.from_records(
        [tuple(r) for r in cursor.fetchall()], columns=cols
    )
    df_vb_sp2 = df_vb_sp2.drop(
        columns=[c for c in ['Run_ID', 'Load_Timestamp'] if c in df_vb_sp2.columns]
    )

    log(f"SP2 complete:", 1)
    log(f"Initiatives   : {len(df_init_sp2):,} rows | {len(df_init_sp2.columns)} cols", 2)
    log(f"Epics         : {len(df_epic_sp2):,} rows | {len(df_epic_sp2.columns)} cols", 2)
    log(f"Value_Bundles : {len(df_vb_sp2):,} rows | {len(df_vb_sp2.columns)} cols", 2)
    log(f"Output schema : [output_{ts}] created with all 3 tables", 2)

    return df_init_sp2, df_epic_sp2, df_vb_sp2


# ── STEP 4: Call SP1 — value mappings ────────────────────────
def run_sp1(conn, ts, input_schema, stem):
    """
    SP1 applies value mappings on top of the input tables.
    Returns mapped Initiatives, Epics, Tasks DataFrames + change logs.
    SP1 works on its own _Work copies and drops them — it does NOT
    write to output_{ts}. Python merges SP1 columns into output_{ts}.
    """
    log_step("4/7", "Running SP1 — Planview2026PlatinumConsolidatedUpdated...")
    nrb_field_sql = _sql_col(NRB_FIELD)
    cursor = conn.cursor()
    cursor.execute(
        "EXEC dbo.Planview2026PlatinumConsolidatedUpdated "
        "    @RunID=?, @InputSchema=?, @Stem=?, @NRB_Field=?, @NRB_Threshold_M=?",
        ts, input_schema, stem, nrb_field_sql, float(NRB_THRESHOLD_M)
    )

    # RS1: mapped Initiatives
    cols = [d[0] for d in cursor.description]
    df_init_sp1 = pd.DataFrame.from_records(
        [tuple(r) for r in cursor.fetchall()], columns=cols
    )
    df_init_sp1 = df_init_sp1.drop(
        columns=[c for c in ['Run_ID', 'Load_Timestamp'] if c in df_init_sp1.columns]
    )

    # RS2: mapped Epics
    cursor.nextset()
    cols = [d[0] for d in cursor.description]
    df_epic_sp1 = pd.DataFrame.from_records(
        [tuple(r) for r in cursor.fetchall()], columns=cols
    )
    df_epic_sp1 = df_epic_sp1.drop(
        columns=[c for c in ['Run_ID', 'Load_Timestamp'] if c in df_epic_sp1.columns]
    )

    # RS3: scalar (consume)
    cursor.nextset()
    cursor.fetchone()

    # RS4: init change counts
    cursor.nextset()
    changes_in = {}
    for r in cursor.fetchall():
        if r.cnt and r.cnt > 0:
            changes_in[r.col] = r.cnt

    # RS5: epic change counts
    cursor.nextset()
    changes_ep = {}
    for r in cursor.fetchall():
        if r.cnt and r.cnt > 0:
            changes_ep[r.col] = r.cnt

    # RS6: mapped Tasks
    cursor.nextset()
    cols = [d[0] for d in cursor.description]
    df_task_sp1 = pd.DataFrame.from_records(
        [tuple(r) for r in cursor.fetchall()], columns=cols
    )
    df_task_sp1 = df_task_sp1.drop(
        columns=[c for c in ['Run_ID', 'Load_Timestamp', '_placeholder']
                 if c in df_task_sp1.columns]
    )

    log(f"SP1 complete:", 1)
    log(f"Initiatives : {len(df_init_sp1):,} rows | {len(df_init_sp1.columns)} cols", 2)
    log(f"Epics       : {len(df_epic_sp1):,} rows | {len(df_epic_sp1.columns)} cols", 2)
    log(f"Tasks       : {len(df_task_sp1):,} rows | {len(df_task_sp1.columns)} cols", 2)
    if changes_in:
        for col, cnt in changes_in.items():
            log(f"Init mapping — {col}: {cnt:,} values remapped", 2)
    if changes_ep:
        for col, cnt in changes_ep.items():
            log(f"Epic mapping — {col}: {cnt:,} values remapped", 2)

    return df_init_sp1, df_epic_sp1, df_task_sp1, changes_in, changes_ep


# ── STEP 4b: Merge SP1 columns into output_{ts} tables ───────
def merge_sp1_into_output(conn, ts, df_init_sp1, df_epic_sp1):
    """
    SP1 returns mapped columns via result sets only — it does not write
    to output_{ts}. This function identifies the columns SP1 added or
    changed and writes them into output_{ts}.Initiatives and
    output_{ts}.Epics by iterating the SP1 result set and running
    parameterised UPDATEs row by row in batches.

    SP1-specific columns (those not already in SP2 output) are:
      Initiatives: Estimated Annualized Value Range (renumbered), Work Type,
                   Home Portfolio, Risk Subtype, Other Impacted Portfolios,
                   Does this require Limited Visibility?, Status,
                   Demand Domain or Portfolio (renamed)
      Epics:       Work Status (mapped), Level of Governance, Work Type,
                   Other Impacted Portfolios, Home Domain/Portfolio (renamed)
    Rather than hardcoding, we detect SP1-only columns dynamically.
    """
    log("Merging SP1 columns into output_{ts} tables...".replace("{ts}", ts), 1)
    output_schema = f"output_{ts}"
    cursor = conn.cursor()

    def get_existing_cols(schema, table):
        cursor.execute(f"""
            SELECT name FROM sys.columns
            WHERE object_id = OBJECT_ID('[{schema}].[{table}]')
        """)
        return {r[0] for r in cursor.fetchall()}

    # ── Initiatives ───────────────────────────────────────────
    existing_init_cols = get_existing_cols(output_schema, "Initiatives")

    # SP1-only columns: in SP1 result but not already in output table
    # Always include these key mapped columns regardless
    sp1_init_mapped = [
        'Estimated Annualized Value Range', 'Work Type', 'Home Portfolio',
        'Risk Subtype', 'Other Impacted Portfolios', 'Status',
        'Does this require Limited Visibility?', 'Demand Domain or Portfolio',
        'What Business Unit does this request support?',
    ]

    init_to_merge = [c for c in df_init_sp1.columns
                     if c in sp1_init_mapped or c not in existing_init_cols]
    init_to_merge = [c for c in init_to_merge if c != 'Strategy Seq ID']

    if init_to_merge and 'Strategy Seq ID' in df_init_sp1.columns:
        # Add missing columns to output table first
        for col in init_to_merge:
            safe = _sql_col(col)
            if safe not in existing_init_cols:
                try:
                    cursor.execute(f"""
                        ALTER TABLE [{output_schema}].[Initiatives]
                        ADD [{safe}] NVARCHAR(MAX)
                    """)
                except Exception:
                    pass  # column may already exist

        # Batch UPDATE: 500 rows at a time
        set_clause = ", ".join([f"[{_sql_col(c)}] = ?" for c in init_to_merge])
        update_sql = (
            f"UPDATE [{output_schema}].[Initiatives] "
            f"SET {set_clause} "
            f"WHERE [Strategy Seq ID] = ?"
        )

        def _val(v):
            if v is None: return None
            s = str(v).strip()
            return None if s.upper() in ('NULL','NONE','NAN','NAT','') else s

        batch = []
        for _, row in df_init_sp1.iterrows():
            vals = [_val(row[c]) for c in init_to_merge]
            vals.append(_val(row['Strategy Seq ID']))
            batch.append(tuple(vals))
            if len(batch) == 500:
                cursor.executemany(update_sql, batch)
                batch = []
        if batch:
            cursor.executemany(update_sql, batch)
        conn.commit()
        log(f"  Initiatives: {len(init_to_merge)} SP1 columns merged "
            f"({len(df_init_sp1):,} rows updated)", 2)

    # ── Epics ──────────────────────────────────────────────────
    existing_epic_cols = get_existing_cols(output_schema, "Epics")

    sp1_epic_mapped = [
        'Work Status', 'Level of Governance', 'Work Type',
        'Other Impacted Portfolios', 'Home Domain/Portfolio',
        'Estimated Annualized Value Range',
        'What Business Unit does this request support?',
    ]

    epic_to_merge = [c for c in df_epic_sp1.columns
                     if c in sp1_epic_mapped or c not in existing_epic_cols]
    epic_to_merge = [c for c in epic_to_merge if c != 'Sequence ID']

    if epic_to_merge and 'Sequence ID' in df_epic_sp1.columns:
        for col in epic_to_merge:
            safe = _sql_col(col)
            if safe not in existing_epic_cols:
                try:
                    cursor.execute(f"""
                        ALTER TABLE [{output_schema}].[Epics]
                        ADD [{safe}] NVARCHAR(MAX)
                    """)
                except Exception:
                    pass

        set_clause = ", ".join([f"[{_sql_col(c)}] = ?" for c in epic_to_merge])
        update_sql = (
            f"UPDATE [{output_schema}].[Epics] "
            f"SET {set_clause} "
            f"WHERE [Sequence ID] = ?"
        )

        batch = []
        for _, row in df_epic_sp1.iterrows():
            vals = [_val(row[c]) for c in epic_to_merge]
            vals.append(_val(row['Sequence ID']))
            batch.append(tuple(vals))
            if len(batch) == 500:
                cursor.executemany(update_sql, batch)
                batch = []
        if batch:
            cursor.executemany(update_sql, batch)
        conn.commit()
        log(f"  Epics: {len(epic_to_merge)} SP1 columns merged "
            f"({len(df_epic_sp1):,} rows updated)", 2)


# ── STEP 5: Call New SP — PQ transformation blocks ───────────
def run_new_sp(conn, ts):
    """
    usp_Planview_PQ_Transformation reads and mutates
    output_{ts}.Initiatives and output_{ts}.Epics directly.
    Adds: Disposition, 16 approval fields, Status, Work Status,
    Limited Visibility, Other Impacted Portfolios, Execution Type remap,
    Parent Sequence ID, Epic GrandParent Index, Epic Flow Type.
    Returns 2 result sets — final Initiatives and Epics.
    """
    log_step("5/7", "Running New SP — usp_Planview_PQ_Transformation...")
    cursor = conn.cursor()
    cursor.execute(
        "EXEC dbo.usp_Planview_PQ_Transformation "
        "    @run_ts=?, @WorkHierarchyTable=?, @DevPPL1Table=?",
        ts, WORK_HIERARCHY_TABLE, DEV_PPL1_TABLE
    )

    # RS1: final Initiatives (all SP2 + SP1 + New SP columns)
    cols = [d[0] for d in cursor.description]
    df_init_final = pd.DataFrame.from_records(
        [tuple(r) for r in cursor.fetchall()], columns=cols
    )
    df_init_final = df_init_final.drop(
        columns=[c for c in ['Run_ID', 'Load_Timestamp'] if c in df_init_final.columns]
    )

    # RS2: final Epics (all SP2 + SP1 + New SP columns)
    cursor.nextset()
    cols = [d[0] for d in cursor.description]
    df_epic_final = pd.DataFrame.from_records(
        [tuple(r) for r in cursor.fetchall()], columns=cols
    )
    df_epic_final = df_epic_final.drop(
        columns=[c for c in ['Run_ID', 'Load_Timestamp'] if c in df_epic_final.columns]
    )

    log(f"New SP complete:", 1)
    log(f"Initiatives : {len(df_init_final):,} rows | {len(df_init_final.columns)} cols", 2)
    log(f"Epics       : {len(df_epic_final):,} rows | {len(df_epic_final.columns)} cols", 2)

    # Log new columns added by New SP
    new_sp_cols = [
        'Disposition', 'SL3 EPG Approval', 'L3 EPM Review 1',
        'SL4 Close Work Bundle -D&T Finance Approval',
        'Status', 'Work Status', 'Does this require Limited Visibility?',
        'Other Impacted Portfolios', 'Execution Type New',
        'Parent Sequence ID', 'GrandParent Index', 'Epic Flow Type'
    ]
    found = [c for c in new_sp_cols if c in df_init_final.columns
             or c in df_epic_final.columns]
    log(f"PQ columns added: {', '.join(found)}", 2)

    return df_init_final, df_epic_final


# ── SQL: Save single output table ─────────────────────────────
def save_output_to_sql(conn, df, schema_name, table_name, ts, type_map=None):
    cursor = conn.cursor()
    cursor.execute(f"""
        IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name='{schema_name}')
            EXEC('CREATE SCHEMA [{schema_name}]')
    """)
    cursor.execute(f"""
        IF OBJECT_ID('[{schema_name}].[{table_name}]') IS NOT NULL
            DROP TABLE [{schema_name}].[{table_name}]
    """)
    if df.empty:
        log(f"  [{schema_name}].[{table_name}] — 0 rows (skipped)", 1)
        return

    safe_cols = [_sql_col(c) for c in df.columns]
    seen = {}
    final_cols = []
    for c in safe_cols:
        if c in seen:
            seen[c] += 1
            c = f"{c}_{seen[c]}"
        else:
            seen[c] = 0
        final_cols.append(c)
    df = df.copy()
    df.columns = final_cols
    df = df.drop(columns=[c for c in ['Run_ID', 'Load_Timestamp', 'Save_Timestamp']
                           if c in df.columns])

    col_type_map = {}
    if type_map:
        for orig_col, sql_type in type_map.items():
            col_type_map[_sql_col(orig_col)] = sql_type
            col_type_map[orig_col] = sql_type

    col_defs = ", ".join([
        f"[{c}] {col_type_map.get(c, 'nvarchar(MAX)')}"
        for c in df.columns
    ])
    cursor.execute(f"""
        CREATE TABLE [{schema_name}].[{table_name}] (
            [Run_ID]         nvarchar(50) DEFAULT '{ts}',
            [Save_Timestamp] datetime     DEFAULT GETDATE(),
            {col_defs}
        )
    """)
    col_names    = ", ".join([f"[{c}]" for c in df.columns])
    placeholders = ", ".join(["?" for _ in df.columns])
    ins = (
        f"INSERT INTO [{schema_name}].[{table_name}] "
        f"([Run_ID],[Save_Timestamp],{col_names}) "
        f"VALUES ('{ts}',GETDATE(),{placeholders})"
    )
    import math, datetime as dt_mod

    SQL_DT_MIN = dt_mod.datetime(1753, 1, 1)
    SQL_DT_MAX = dt_mod.datetime(9999, 12, 31)

    def to_typed_val(v, col):
        if v is None:
            return None
        if isinstance(v, float) and (math.isnan(v) or math.isinf(v)):
            return None
        if isinstance(v, str) and v.strip().upper() in ('NULL', 'NONE', 'NAT', 'NAN', ''):
            return None
        sql_t = col_type_map.get(col, 'nvarchar(MAX)')
        if 'decimal' in sql_t or 'numeric' in sql_t or 'float' in sql_t:
            try: return float(str(v).strip())
            except: return None
        elif sql_t in ('bigint', 'int'):
            try: return int(float(str(v).strip()))
            except: return None
        elif sql_t == 'datetime':
            if isinstance(v, (dt_mod.datetime, dt_mod.date)):
                try:
                    d = dt_mod.datetime(v.year, v.month, v.day) if not isinstance(v, dt_mod.datetime) else v
                    return d if SQL_DT_MIN <= d <= SQL_DT_MAX else None
                except: return None
            s = str(v).strip()
            if not s or s.upper() in ('NULL', 'NONE', 'NAT', 'NAN'): return None
            for fmt in ('%Y-%m-%d %H:%M:%S', '%Y-%m-%d %H:%M:%S.%f', '%Y-%m-%d'):
                try:
                    d = dt_mod.datetime.strptime(s[:26], fmt)
                    return d if SQL_DT_MIN <= d <= SQL_DT_MAX else None
                except: continue
            return None
        else:
            s = str(v).strip()
            s = s.replace("\n", " ").replace("\r", " ").replace("|", " ").replace('"', "'")
            return s if s and s.upper() not in ('NULL', 'NONE') else None

    rows = []
    for _, row in df.iterrows():
        rows.append(tuple(to_typed_val(v, col) for v, col in zip(row, df.columns)))

    conn.autocommit = False
    try:
        for i in range(0, len(rows), 500):
            cursor.executemany(ins, rows[i:i+500])
        conn.commit()
    except Exception as e:
        conn.rollback(); raise
    finally:
        conn.autocommit = True
    log(f"  [{schema_name}].[{table_name}] — {len(df):,} rows saved", 1)


# ── SQL: Get next version number ──────────────────────────────
def get_next_version(conn, schema):
    cursor = conn.cursor()
    cursor.execute(f"""
        IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name='{schema}')
            EXEC('CREATE SCHEMA [{schema}]')
    """)
    cursor.execute(f"""
        SELECT MAX(CAST(REPLACE(t.name, 'Initiatives_v', '') AS int))
        FROM sys.tables t
        JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE s.name = '{schema}'
        AND t.name LIKE 'Initiatives_v%'
        AND ISNUMERIC(REPLACE(t.name, 'Initiatives_v', '')) = 1
    """)
    row = cursor.fetchone()
    max_v = row[0] if row and row[0] is not None else 0
    return max_v + 1


# ── STEP 6: Save final output to PlanviewMigration_Output ────
def save_final_output(conn, df_inits, df_epics, df_vb, df_tasks, df_sba, ts):
    """
    Saves all four final DataFrames — which now have ALL SP transformations
    applied (SP2 + SP1 + New SP) — into PlanviewMigration_Output schema
    as versioned tables.
    """
    log_step("6/7", "Saving final output to PlanviewMigration_Output schema...")
    schema  = "PlanviewMigration_Output"
    version = get_next_version(conn, schema)
    v       = f"v{version}"
    log(f"Output version : {v}", 1)
    log(f"All 3 SP transformations applied to Initiatives and Epics", 1)

    save_output_to_sql(conn, df_inits, schema, f"Initiatives_{v}", ts)
    save_output_to_sql(conn, df_epics, schema, f"Epics_{v}",       ts)
    save_output_to_sql(conn, df_vb,    schema, f"Value_Bundles_{v}", ts)
    save_output_to_sql(conn, df_tasks, schema, f"Tasks_{v}",       ts)
    save_output_to_sql(conn, df_sba,   schema, f"SBA_{v}",         ts)

    log(f"Output schema  : [{schema}]", 1)
    log(f"Tables saved   : Initiatives_{v} | Epics_{v} | Value_Bundles_{v} | Tasks_{v} | SBA_{v}", 1)

    # Log column counts so team can verify all transforms are present
    log(f"Column counts:", 1)
    log(f"  Initiatives_{v} : {len(df_inits.columns)} columns", 2)
    log(f"  Epics_{v}       : {len(df_epics.columns)} columns", 2)
    log(f"  Value_Bundles_{v}: {len(df_vb.columns)} columns", 2)
    log(f"  Tasks_{v}       : {len(df_tasks.columns)} columns", 2)

    return f"{schema} ({v})"


# ── Helper: Add _Original columns ─────────────────────────────
def add_original_cols(df_output, df_raw, mapped_cols, join_key):
    df = df_output.copy()
    if join_key not in df_raw.columns:
        return df
    dup_count = df_raw[join_key].duplicated().sum()
    if dup_count > 0:
        log(f"  WARNING: {dup_count:,} duplicate {join_key} values in raw data", 2)
    df_raw_dedup = df_raw.drop_duplicates(subset=[join_key], keep='first')
    raw_indexed  = df_raw_dedup.set_index(join_key)

    for col in mapped_cols:
        if col not in df.columns:
            continue
        raw_col = None
        if col in df_raw.columns:
            raw_col = col
        elif col + '?' in df_raw.columns:
            raw_col = col + '?'
        if raw_col is None:
            continue
        orig_col = col + '_Original'
        col_idx  = df.columns.get_loc(col)
        orig_vals = (df[join_key]
            .map(raw_indexed[raw_col])
            .fillna('')
            .astype(str)
            .str.strip()
            .replace('nan', ''))
        df.insert(col_idx + 1, orig_col, orig_vals.values)
    return df


def get_changed_positions(df_with_orig, mapped_cols):
    changed = set()
    for col in mapped_cols:
        orig_col = col + '_Original'
        if col not in df_with_orig.columns or orig_col not in df_with_orig.columns:
            continue
        col_i  = df_with_orig.columns.get_loc(col) + 1
        orig_i = df_with_orig.columns.get_loc(orig_col) + 1
        for row_i, (nv, ov) in enumerate(
            zip(df_with_orig[col], df_with_orig[orig_col]), start=2
        ):
            nv_s = str(nv).strip() if nv is not None else ''
            ov_s = str(ov).strip() if ov is not None else ''
            if nv_s != ov_s:
                changed.add((row_i, col_i))
                changed.add((row_i, orig_i))
    return changed


# ── SQL: Log run to run_history ───────────────────────────────
def log_run_history(conn, ts, input_path, input_schema, output_schema,
                    df_inits, df_epics, df_sba, df_tasks, elapsed, status):
    cursor = conn.cursor()
    cursor.execute("""
        IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name='run_history')
            EXEC('CREATE SCHEMA [run_history]')
    """)
    cursor.execute("""
        IF OBJECT_ID('run_history.Pipeline_Runs_Prod') IS NOT NULL
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM sys.columns
                WHERE object_id=OBJECT_ID('run_history.Pipeline_Runs_Prod')
                AND name='Task_Count'
            )
            DROP TABLE run_history.Pipeline_Runs_Prod
        END
    """)
    cursor.execute("""
        IF OBJECT_ID('run_history.Pipeline_Runs_Prod') IS NULL
        CREATE TABLE run_history.Pipeline_Runs_Prod (
            Run_ID             nvarchar(50)  PRIMARY KEY,
            Run_Timestamp      datetime      DEFAULT GETDATE(),
            Pipeline_Name      nvarchar(200),
            Pipeline_Version   nvarchar(20),
            Input_File         nvarchar(500),
            Input_Schema       nvarchar(200),
            Output_Schema      nvarchar(200),
            Init_Count         int,
            Epic_Count         int,
            SBA_Count          int,
            Task_Count         int,
            Runtime_Seconds    decimal(10,1),
            Run_Status         nvarchar(50)
        )
    """)
    cursor.execute("""
        INSERT INTO run_history.Pipeline_Runs_Prod (
            Run_ID, Pipeline_Name, Pipeline_Version, Input_File,
            Input_Schema, Output_Schema,
            Init_Count, Epic_Count, SBA_Count, Task_Count,
            Runtime_Seconds, Run_Status
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
    """, (
        ts, 'Prod Data Pipeline', 'prod_v7', str(input_path),
        input_schema, output_schema,
        len(df_inits), len(df_epics), len(df_sba), len(df_tasks),
        elapsed, status
    ))
    conn.commit()
    log(f"Run logged : run_history.Pipeline_Runs_Prod — Run_ID: {ts}", 1)


# ── Dedup helper ───────────────────────────────────────────────
def dedup(df, key, label):
    if key in df.columns:
        before = len(df)
        df = df.drop_duplicates(subset=[key], keep='first').reset_index(drop=True)
        removed = before - len(df)
        if removed > 0:
            log(f"  Dedup — {label}: removed {removed:,} duplicate rows", 1)
    return df


# ── Main ──────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="Planview Prod Pipeline v7 — SP2 + SP1 + New SP"
    )
    parser.add_argument("--config", default=None)
    args = parser.parse_args()
    load_config(args.config)

    start = datetime.now()
    ts    = start.strftime("%Y%m%d_%H%M%S")
    log_file = init_logger(ts, OUTPUT_FOLDER)

    log(SEPARATOR)
    log("  Planview2026PlatinumConsolidatedViewCrossDB v7")
    log("  SPs: Consolidated_Transform_Logic + "
        "Planview2026PlatinumConsolidatedUpdated + "
        "usp_Planview_PQ_Transformation")
    log(f"  Views    : {VIEW_DATABASE}.{VIEW_SCHEMA} on {SQL_SERVER}")
    log(f"  Working  : {SQL_DATABASE} on {SQL_SERVER}")
    log(f"  Output   : PlanviewMigration_Output schema")
    log(f"  Started  : {start.strftime('%Y-%m-%d %H:%M:%S')}")
    log(SEPARATOR)

    # ── Step 1 — Connect + read views ────────────────────────
    log_step("1/7", "Connecting to SQL and reading views...")
    conn = connect_sql()

    df_in_raw,  type_map_init = read_from_view(conn, VIEW_INITIATIVES)
    df_ep_raw,  type_map_epic = read_from_view(conn, VIEW_EPICS)
    df_sba_raw, type_map_sba  = read_from_view(conn, VIEW_SBA)
    df_tk_raw,  type_map_task = read_from_view(conn, VIEW_TASKS)

    # Apply column renames immediately after reading views
    # exactly as the working ConsolidatedTransformLogic script does
    df_in_raw  = df_in_raw.rename(columns=COLUMN_RENAME.get("Initiatives",   {}))
    df_ep_raw  = df_ep_raw.rename(columns=COLUMN_RENAME.get("Epics",         {}))
    df_sba_raw = df_sba_raw.rename(columns=COLUMN_RENAME.get("Value_Bundles", {})) if not df_sba_raw.empty else df_sba_raw
    df_tk_raw  = df_tk_raw.rename(columns=COLUMN_RENAME.get("Tasks",         {}))  if not df_tk_raw.empty  else df_tk_raw
    if COLUMN_RENAME.get("Initiatives"):
        log(f"  Column renames applied to Initiatives: {COLUMN_RENAME.get('Initiatives')}", 1)

    log(f"Initiatives : {len(df_in_raw):,} rows | {len(df_in_raw.columns)} cols", 1)
    log(f"Epics       : {len(df_ep_raw):,} rows | {len(df_ep_raw.columns)} cols", 1)
    log(f"Tasks       : {len(df_tk_raw):,} rows | {len(df_tk_raw.columns)} cols", 1)
    log(f"SBA         : {len(df_sba_raw):,} rows | {len(df_sba_raw.columns)} cols", 1)

    # ── Step 2a — Load to input schema ───────────────────────
    input_schema, stem = create_input_schema_and_load(
        conn, df_in_raw, df_ep_raw, df_sba_raw, df_tk_raw, ts,
        type_map_init, type_map_epic, type_map_sba, type_map_task)

    # ── Step 3 — SP2: Flow Type, EVR, Stage, Index_ID ────────
    df_init_sp2, df_epic_sp2, df_vb_sp2 = run_sp2(conn, ts)

    # ── Step 4 — SP1: value mappings ─────────────────────────
    (df_init_sp1, df_epic_sp1, df_task_sp1,
     changes_in, changes_ep) = run_sp1(conn, ts, input_schema, stem)

    # ── Step 4b — Merge SP1 columns into output_{ts} ─────────
    merge_sp1_into_output(conn, ts, df_init_sp1, df_epic_sp1)

    # ── Step 5 — New SP: PQ transformation blocks ─────────────
    df_init_final, df_epic_final = run_new_sp(conn, ts)

    # ── Dedup all final DataFrames ────────────────────────────
    df_init_final = dedup(df_init_final, 'Strategy Seq ID', 'Initiatives final')
    df_epic_final = dedup(df_epic_final, 'Sequence ID',     'Epics final')
    df_task_sp1   = dedup(df_task_sp1,   'Sequence ID',     'Tasks')
    df_in_raw     = dedup(df_in_raw,     'Strategy Seq ID', 'Initiatives raw')
    df_ep_raw     = dedup(df_ep_raw,     'Sequence ID',     'Epics raw')

    log(f"\nFINAL ROW COUNTS (all transforms applied):", 1)
    log(f"  Initiatives : {len(df_init_final):,} rows | {len(df_init_final.columns)} cols", 1)
    log(f"  Epics       : {len(df_epic_final):,} cols | {len(df_epic_final.columns)} cols", 1)
    log(f"  Value Bundles: {len(df_vb_sp2):,} rows", 1)
    log(f"  Tasks       : {len(df_task_sp1):,} rows", 1)
    log(f"  SBA         : {len(df_sba_raw):,} rows (passthrough)", 1)

    # ── Step 6 — Save to PlanviewMigration_Output ────────────
    output_schema = save_final_output(
        conn,
        df_init_final, df_epic_final,
        df_vb_sp2, df_task_sp1, df_sba_raw,
        ts
    )

    # ── Step 7 — Log run ──────────────────────────────────────
    log_step("7/7", "Logging run to run_history...")
    elapsed = round((datetime.now() - start).total_seconds(), 1)
    log_run_history(
        conn, ts,
        f"views:{VIEW_DATABASE}.{VIEW_SCHEMA}:"
        f"{VIEW_INITIATIVES},{VIEW_EPICS},{VIEW_TASKS},{VIEW_SBA}",
        input_schema, output_schema,
        df_init_final, df_epic_final, df_sba_raw, df_task_sp1,
        elapsed, "Completed"
    )

    conn.close()

    log(f"\n{SEPARATOR}")
    log("  PIPELINE COMPLETE — v7 (SP2 + SP1 + New SP)")
    log(f"  Output  : PlanviewMigration_Output schema")
    log(f"  Log     : {log_file}")
    log(f"")
    log(f"  INITIATIVES  : {len(df_init_final):,} rows "
        f"({len(df_init_final.columns)} cols — SP2 + SP1 + New SP)")
    log(f"  EPICS        : {len(df_epic_final):,} rows "
        f"({len(df_epic_final.columns)} cols — SP2 + SP1 + New SP)")
    log(f"  VALUE BUNDLES: {len(df_vb_sp2):,} rows (SP2)")
    log(f"  TASKS        : {len(df_task_sp1):,} rows (SP1)")
    log(f"  SBA          : {len(df_sba_raw):,} rows (passthrough)")
    log(f"  Runtime      : {elapsed}s")
    log(SEPARATOR)


if __name__ == "__main__":
    main()
