-- ============================================================
-- Wrapper Script : Planview2026PlatinumConsolidatedv2_Wrapper
-- Description    : 1. Creates output schema PlanviewMigration_Output_v2
--                  2. Validates source views have data
--                  3. Executes dbo.Planview2026PlatinumConsolidatedv2
--                  4. Creates 3 final output tables (one per entity)
--                  5. Prints row count summary
-- Source Views   : ip.FDXPROD_initiatives_extract
--                  ip.FDXPROD_epics_extract
--                  ip.FDXPROD_tasks_extract
-- Output Schema  : PlanviewMigration_Output_v2
-- Output Tables  : PlanviewMigration_Output_v2.Initiatives
--                  PlanviewMigration_Output_v2.Epics
--                  PlanviewMigration_Output_v2.Tasks
-- Author         : Rajinder
-- Version        : v2.0
-- Date           : 2026-06-10
-- ============================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT '======================================================';
PRINT 'Planview2026PlatinumConsolidatedv2 — WRAPPER START';
PRINT CONVERT(VARCHAR, GETDATE(), 120);
PRINT '======================================================';


-- ============================================================
-- STEP 1 : Create output schema if it does not exist
-- ============================================================

PRINT '';
PRINT '-- STEP 1: Create schema PlanviewMigration_Output_v2';

IF NOT EXISTS (
    SELECT 1 FROM sys.schemas
    WHERE name = 'PlanviewMigration_Output_v2'
)
BEGIN
    EXEC('CREATE SCHEMA PlanviewMigration_Output_v2');
    PRINT '  Schema PlanviewMigration_Output_v2 created.';
END
ELSE
BEGIN
    PRINT '  Schema PlanviewMigration_Output_v2 already exists — skipping.';
END


-- ============================================================
-- STEP 2 : Validate source views have data
-- ============================================================

PRINT '';
PRINT '-- STEP 2: Validate source views';

DECLARE @init_count  INT;
DECLARE @epic_count  INT;
DECLARE @task_count  INT;

SELECT @init_count = COUNT(*) FROM ip.FDXPROD_initiatives_extract;
SELECT @epic_count = COUNT(*) FROM ip.FDXPROD_epics_extract;
SELECT @task_count = COUNT(*) FROM ip.FDXPROD_tasks_extract;

PRINT '  ip.FDXPROD_initiatives_extract : ' + CAST(@init_count AS VARCHAR) + ' rows';
PRINT '  ip.FDXPROD_epics_extract       : ' + CAST(@epic_count AS VARCHAR) + ' rows';
PRINT '  ip.FDXPROD_tasks_extract       : ' + CAST(@task_count AS VARCHAR) + ' rows';

IF @init_count = 0
BEGIN
    RAISERROR('ERROR: ip.FDXPROD_initiatives_extract is empty. Aborting.', 16, 1);
    RETURN;
END

IF @epic_count = 0
BEGIN
    RAISERROR('ERROR: ip.FDXPROD_epics_extract is empty. Aborting.', 16, 1);
    RETURN;
END

IF @task_count = 0
BEGIN
    RAISERROR('ERROR: ip.FDXPROD_tasks_extract is empty. Aborting.', 16, 1);
    RETURN;
END

PRINT '  All source views validated — data present.';


-- ============================================================
-- STEP 3 : Execute the transformation SP
-- ============================================================

PRINT '';
PRINT '-- STEP 3: Execute dbo.Planview2026PlatinumConsolidatedv2';

EXEC dbo.Planview2026PlatinumConsolidatedv2;

PRINT '  SP execution complete.';


-- ============================================================
-- STEP 4A : Create output table — Initiatives
-- ============================================================

PRINT '';
PRINT '-- STEP 4A: Create PlanviewMigration_Output_v2.Initiatives';

IF OBJECT_ID('PlanviewMigration_Output_v2.Initiatives', 'U') IS NOT NULL
BEGIN
    DROP TABLE PlanviewMigration_Output_v2.Initiatives;
    PRINT '  Existing Initiatives output table dropped.';
END

SELECT
    *,
    GETDATE()       AS [Run_Timestamp],
    'Prod-Init'     AS [Entity_Type]
INTO PlanviewMigration_Output_v2.Initiatives
FROM dbo.stg_prod_init;

PRINT '  PlanviewMigration_Output_v2.Initiatives created — rows: '
    + CAST(@@ROWCOUNT AS VARCHAR);


-- ============================================================
-- STEP 4B : Create output table — Epics
-- ============================================================

PRINT '';
PRINT '-- STEP 4B: Create PlanviewMigration_Output_v2.Epics';

IF OBJECT_ID('PlanviewMigration_Output_v2.Epics', 'U') IS NOT NULL
BEGIN
    DROP TABLE PlanviewMigration_Output_v2.Epics;
    PRINT '  Existing Epics output table dropped.';
END

SELECT
    *,
    GETDATE()       AS [Run_Timestamp],
    'Prod-Epic'     AS [Entity_Type]
INTO PlanviewMigration_Output_v2.Epics
FROM dbo.stg_prod_epic;

PRINT '  PlanviewMigration_Output_v2.Epics created — rows: '
    + CAST(@@ROWCOUNT AS VARCHAR);


-- ============================================================
-- STEP 4C : Create output table — Tasks
-- ============================================================

PRINT '';
PRINT '-- STEP 4C: Create PlanviewMigration_Output_v2.Tasks';

IF OBJECT_ID('PlanviewMigration_Output_v2.Tasks', 'U') IS NOT NULL
BEGIN
    DROP TABLE PlanviewMigration_Output_v2.Tasks;
    PRINT '  Existing Tasks output table dropped.';
END

SELECT
    *,
    GETDATE()       AS [Run_Timestamp],
    'Prod-Task'     AS [Entity_Type]
INTO PlanviewMigration_Output_v2.Tasks
FROM dbo.stg_prod_task;

PRINT '  PlanviewMigration_Output_v2.Tasks created — rows: '
    + CAST(@@ROWCOUNT AS VARCHAR);


-- ============================================================
-- STEP 5 : Final row count summary
-- ============================================================

DECLARE @out_init INT, @out_epic INT, @out_task INT;
SELECT @out_init = COUNT(*) FROM PlanviewMigration_Output_v2.Initiatives;
SELECT @out_epic = COUNT(*) FROM PlanviewMigration_Output_v2.Epics;
SELECT @out_task = COUNT(*) FROM PlanviewMigration_Output_v2.Tasks;

PRINT '';
PRINT '======================================================';
PRINT 'FINAL OUTPUT SUMMARY';
PRINT '======================================================';
PRINT '  PlanviewMigration_Output_v2.Initiatives : ' + CAST(@out_init AS VARCHAR) + ' rows';
PRINT '  PlanviewMigration_Output_v2.Epics        : ' + CAST(@out_epic AS VARCHAR) + ' rows';
PRINT '  PlanviewMigration_Output_v2.Tasks        : ' + CAST(@out_task AS VARCHAR) + ' rows';
PRINT '';
PRINT 'Wrapper complete: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT '======================================================';

-- ============================================================
-- QUICK VALIDATION SELECTS
-- Uncomment to spot-check output after run
-- ============================================================

-- SELECT TOP 10 * FROM PlanviewMigration_Output_v2.Initiatives;
-- SELECT TOP 10 * FROM PlanviewMigration_Output_v2.Epics;
-- SELECT TOP 10 * FROM PlanviewMigration_Output_v2.Tasks;
