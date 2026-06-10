-- ============================================================
-- Validation Script : Planview2026PlatinumConsolidatedv2
-- Description       : Validates all 26 transformation tasks
--                     against PlanviewMigration_Output_v2
--                     output tables.
-- Run After         : Planview2026PlatinumConsolidatedv2_Wrapper.sql
-- Expected Result   : All checks return 0 or expected values
-- Author            : Rajinder
-- Version           : v2.0
-- Date              : 2026-06-10
-- ============================================================

SET NOCOUNT ON;

PRINT '======================================================';
PRINT 'Planview2026PlatinumConsolidatedv2 — VALIDATION START';
PRINT CONVERT(VARCHAR, GETDATE(), 120);
PRINT '======================================================';

-- ============================================================
-- DECLARE RESULTS TABLE
-- Collects all check results in one place
-- ============================================================

IF OBJECT_ID('tempdb..#validation_results', 'U') IS NOT NULL
    DROP TABLE #validation_results;

CREATE TABLE #validation_results (
    Check_ID        INT IDENTITY(1,1),
    Entity          NVARCHAR(20),
    Tracker_ID      NVARCHAR(50),
    Check_Name      NVARCHAR(100),
    Expected        NVARCHAR(50),
    Actual          NVARCHAR(50),
    Result          NVARCHAR(10)  -- PASS / FAIL / INFO
);


-- ============================================================
-- CHECK 1 : ROW COUNT — Initiatives
-- ============================================================

DECLARE @src_init   INT, @out_init INT;
DECLARE @src_epic   INT, @out_epic INT;
DECLARE @src_task   INT, @out_task INT;

SELECT @src_init = COUNT(*) FROM FDXMIG.ip.FDXPROD_initiatives_extract;
SELECT @out_init = COUNT(*) FROM PlanviewMigration_Output_v2.Initiatives;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Initiative', 'Prod-Init-002', 'Row count — no rows lost or gained',
        CAST(@src_init AS NVARCHAR), CAST(@out_init AS NVARCHAR),
        CASE WHEN @src_init = @out_init THEN 'PASS' ELSE 'FAIL' END);

-- CHECK 2 : ROW COUNT — Epics
SELECT @src_epic = COUNT(*) FROM FDXMIG.ip.FDXPROD_epics_extract;
SELECT @out_epic = COUNT(*) FROM PlanviewMigration_Output_v2.Epics;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Epic', 'Prod-Epic-002', 'Row count — no rows lost or gained',
        CAST(@src_epic AS NVARCHAR), CAST(@out_epic AS NVARCHAR),
        CASE WHEN @src_epic = @out_epic THEN 'PASS' ELSE 'FAIL' END);

-- CHECK 3 : ROW COUNT — Tasks
SELECT @src_task = COUNT(*) FROM FDXMIG.ip.FDXPROD_tasks_extract;
SELECT @out_task = COUNT(*) FROM PlanviewMigration_Output_v2.Tasks;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Task', 'Prod-Task-002', 'Row count — no rows lost or gained',
        CAST(@src_task AS NVARCHAR), CAST(@out_task AS NVARCHAR),
        CASE WHEN @src_task = @out_task THEN 'PASS' ELSE 'FAIL' END);


-- ============================================================
-- CHECK 4 : DATA SOURCE — Initiatives (Prod-Init-004)
-- ============================================================

DECLARE @bad_ds_init INT;
SELECT @bad_ds_init = COUNT(*) FROM PlanviewMigration_Output_v2.Initiatives
WHERE [Data Source] <> 'Prod-Init' OR [Data Source] IS NULL;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Initiative', 'Prod-Init-004', 'Data Source = Prod-Init for all rows',
        '0', CAST(@bad_ds_init AS NVARCHAR),
        CASE WHEN @bad_ds_init = 0 THEN 'PASS' ELSE 'FAIL' END);

-- CHECK 5 : INDEX FORMAT — Initiatives
DECLARE @bad_idx_init INT;
SELECT @bad_idx_init = COUNT(*) FROM PlanviewMigration_Output_v2.Initiatives
WHERE [Index] NOT LIKE 'Prod-Init-%' OR [Index] IS NULL;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Initiative', 'Prod-Init-004', 'Index format = Prod-Init-XXXX for all rows',
        '0', CAST(@bad_idx_init AS NVARCHAR),
        CASE WHEN @bad_idx_init = 0 THEN 'PASS' ELSE 'FAIL' END);

-- CHECK 6 : DATA SOURCE — Epics (Prod-Epic-004)
DECLARE @bad_ds_epic INT;
SELECT @bad_ds_epic = COUNT(*) FROM PlanviewMigration_Output_v2.Epics
WHERE [Data Source] <> 'Prod-Epic' OR [Data Source] IS NULL;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Epic', 'Prod-Epic-004', 'Data Source = Prod-Epic for all rows',
        '0', CAST(@bad_ds_epic AS NVARCHAR),
        CASE WHEN @bad_ds_epic = 0 THEN 'PASS' ELSE 'FAIL' END);

-- CHECK 7 : INDEX FORMAT — Epics
DECLARE @bad_idx_epic INT;
SELECT @bad_idx_epic = COUNT(*) FROM PlanviewMigration_Output_v2.Epics
WHERE [Index] NOT LIKE 'Prod-Epic-%' OR [Index] IS NULL;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Epic', 'Prod-Epic-004', 'Index format = Prod-Epic-XXXX for all rows',
        '0', CAST(@bad_idx_epic AS NVARCHAR),
        CASE WHEN @bad_idx_epic = 0 THEN 'PASS' ELSE 'FAIL' END);

-- CHECK 8 : DATA SOURCE — Tasks
DECLARE @bad_ds_task INT;
SELECT @bad_ds_task = COUNT(*) FROM PlanviewMigration_Output_v2.Tasks
WHERE [Data Source] <> 'Prod-Task' OR [Data Source] IS NULL;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Task', 'Prod-Task-002', 'Data Source = Prod-Task for all rows',
        '0', CAST(@bad_ds_task AS NVARCHAR),
        CASE WHEN @bad_ds_task = 0 THEN 'PASS' ELSE 'FAIL' END);

-- CHECK 9 : INDEX FORMAT — Tasks
DECLARE @bad_idx_task INT;
SELECT @bad_idx_task = COUNT(*) FROM PlanviewMigration_Output_v2.Tasks
WHERE [Index] NOT LIKE 'Prod-Task-%' OR [Index] IS NULL;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Task', 'Prod-Task-002', 'Index format = Prod-Task-XXXX for all rows',
        '0', CAST(@bad_idx_task AS NVARCHAR),
        CASE WHEN @bad_idx_task = 0 THEN 'PASS' ELSE 'FAIL' END);


-- ============================================================
-- CHECK 10 : IMPACTS PLATFORMS CONSOLIDATION (Prod-Init-019)
-- If Data&AI=Yes OR Platform=Yes then Impacts Platforms must = Yes
-- ============================================================

DECLARE @bad_platforms INT;
SELECT @bad_platforms = COUNT(*) FROM PlanviewMigration_Output_v2.Initiatives
WHERE ([Impacts Data & AI Portfolio?] = 'Yes' OR [Impacts Platform Portfolio?] = 'Yes')
AND ISNULL([Impacts Platforms Portfolio?], '') <> 'Yes';
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Initiative', 'Prod-Init-019', 'Impacts Platforms = Yes where Data&AI or Platform = Yes',
        '0', CAST(@bad_platforms AS NVARCHAR),
        CASE WHEN @bad_platforms = 0 THEN 'PASS' ELSE 'FAIL' END);


-- ============================================================
-- CHECK 11 : OTHER IMPACTED PORTFOLIOS — pipe delimiter (Prod-Init-020)
-- ============================================================

DECLARE @bad_pipe_init INT;
SELECT @bad_pipe_init = COUNT(*) FROM PlanviewMigration_Output_v2.Initiatives
WHERE [Other Impacted Portfolios] LIKE '%,%';
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Initiative', 'Prod-Init-020', 'Other Impacted Portfolios — no commas, pipe only',
        '0', CAST(@bad_pipe_init AS NVARCHAR),
        CASE WHEN @bad_pipe_init = 0 THEN 'PASS' ELSE 'FAIL' END);

-- INFO: how many rows have Other Impacted Portfolios populated
DECLARE @pop_oip INT;
SELECT @pop_oip = COUNT(*) FROM PlanviewMigration_Output_v2.Initiatives
WHERE [Other Impacted Portfolios] IS NOT NULL AND [Other Impacted Portfolios] <> '';
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Initiative', 'Prod-Init-020', 'Other Impacted Portfolios — populated row count (INFO)',
        'N/A', CAST(@pop_oip AS NVARCHAR), 'INFO');


-- ============================================================
-- CHECK 12 : PRIMARY TYPE OF VALUE — no legacy values (Prod-Init-026)
-- ============================================================

DECLARE @bad_ptv_init INT;
SELECT @bad_ptv_init = COUNT(*) FROM PlanviewMigration_Output_v2.Initiatives
WHERE [Primary Type of Value - Transformed] IN (
    'Service - FO/PO', 'Service - IPF/IEF',
    'Service - Northern Border', 'Service - EU'
);
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Initiative', 'Prod-Init-026', 'Primary Type of Value — no legacy Service sub-types',
        '0', CAST(@bad_ptv_init AS NVARCHAR),
        CASE WHEN @bad_ptv_init = 0 THEN 'PASS' ELSE 'FAIL' END);

-- CHECK 13 : PRIMARY TYPE OF VALUE — Epics (Prod-Epic-014)
DECLARE @bad_ptv_epic INT;
SELECT @bad_ptv_epic = COUNT(*) FROM PlanviewMigration_Output_v2.Epics
WHERE [Primary Type of Value - Transformed] IN (
    'Service - FO/PO', 'Service - IPF/IEF',
    'Service - Northern Border', 'Service - EU'
);
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Epic', 'Prod-Epic-014', 'Primary Type of Value — no legacy Service sub-types',
        '0', CAST(@bad_ptv_epic AS NVARCHAR),
        CASE WHEN @bad_ptv_epic = 0 THEN 'PASS' ELSE 'FAIL' END);


-- ============================================================
-- CHECK 14 : ARCHITECTURE PM (Prod-Init-030)
-- ============================================================

DECLARE @bad_arch INT;
SELECT @bad_arch = COUNT(*) FROM PlanviewMigration_Output_v2.Initiatives
WHERE [Architecture Program Manager] <> 'PLACEHOLDER USERNAME'
OR [Architecture Program Manager] IS NULL;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Initiative', 'Prod-Init-030', 'Architecture PM = PLACEHOLDER USERNAME for all rows',
        '0', CAST(@bad_arch AS NVARCHAR),
        CASE WHEN @bad_arch = 0 THEN 'PASS' ELSE 'FAIL' END);


-- ============================================================
-- CHECK 15 : BUSINESS DEMAND MANAGER + DEMAND MANAGER — mutually exclusive
--            Initiatives (Prod-Init-032)
-- ============================================================

DECLARE @both_init INT;
SELECT @both_init = COUNT(*) FROM PlanviewMigration_Output_v2.Initiatives
WHERE [Business Demand Manager] IS NOT NULL
AND [Demand Manager] IS NOT NULL;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Initiative', 'Prod-Init-032', 'Business Demand Mgr + Demand Mgr — mutually exclusive',
        '0', CAST(@both_init AS NVARCHAR),
        CASE WHEN @both_init = 0 THEN 'PASS' ELSE 'FAIL' END);

-- Business Only rows must have Business Demand Manager populated
DECLARE @bo_no_bdm INT;
SELECT @bo_no_bdm = COUNT(*) FROM PlanviewMigration_Output_v2.Initiatives
WHERE [Demand Type] = 'Business Only'
AND [Business Demand Manager] IS NULL;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Initiative', 'Prod-Init-032', 'Business Only rows — Business Demand Manager populated',
        '0', CAST(@bo_no_bdm AS NVARCHAR),
        CASE WHEN @bo_no_bdm = 0 THEN 'PASS' ELSE 'FAIL' END);

-- Non-Business Only rows must have Demand Manager populated
DECLARE @nonbo_no_dm INT;
SELECT @nonbo_no_dm = COUNT(*) FROM PlanviewMigration_Output_v2.Initiatives
WHERE [Demand Type] <> 'Business Only'
AND [Demand Manager] IS NULL;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Initiative', 'Prod-Init-032', 'Non-Business Only rows — Demand Manager populated',
        '0', CAST(@nonbo_no_dm AS NVARCHAR),
        CASE WHEN @nonbo_no_dm = 0 THEN 'PASS' ELSE 'FAIL' END);


-- ============================================================
-- CHECK 16 : BUSINESS DEMAND MANAGER + DEMAND MANAGER — Epics (Prod-Epic-019)
-- ============================================================

DECLARE @both_epic INT;
SELECT @both_epic = COUNT(*) FROM PlanviewMigration_Output_v2.Epics
WHERE [Business Demand Manager] IS NOT NULL
AND [Demand Manager] IS NOT NULL;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Epic', 'Prod-Epic-019', 'Business Demand Mgr + Demand Mgr — mutually exclusive',
        '0', CAST(@both_epic AS NVARCHAR),
        CASE WHEN @both_epic = 0 THEN 'PASS' ELSE 'FAIL' END);


-- ============================================================
-- CHECK 17 : SHOW ON ROADMAP constant (Prod-Epic-015)
-- ============================================================

DECLARE @bad_sor INT;
SELECT @bad_sor = COUNT(*) FROM PlanviewMigration_Output_v2.Epics
WHERE [Show on Roadmap] <> 'Show on Strategy & Project'
OR [Show on Roadmap] IS NULL;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Epic', 'Prod-Epic-015', 'Show on Roadmap = Show on Strategy & Project for all rows',
        '0', CAST(@bad_sor AS NVARCHAR),
        CASE WHEN @bad_sor = 0 THEN 'PASS' ELSE 'FAIL' END);


-- ============================================================
-- CHECK 18 : MILESTONE FLAG constant (Prod-Epic-016)
-- ============================================================

DECLARE @bad_mf INT;
SELECT @bad_mf = COUNT(*) FROM PlanviewMigration_Output_v2.Epics
WHERE [Milestone Flag] <> 'N' OR [Milestone Flag] IS NULL;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Epic', 'Prod-Epic-016', 'Milestone Flag = N for all Epic rows',
        '0', CAST(@bad_mf AS NVARCHAR),
        CASE WHEN @bad_mf = 0 THEN 'PASS' ELSE 'FAIL' END);


-- ============================================================
-- CHECK 19 : BUSINESS ONLY FLAG (Prod-Epic-018)
-- ============================================================

DECLARE @bad_bo_yes INT, @bad_bo_no INT;
-- Business Only rows must have 'Yes'
SELECT @bad_bo_yes = COUNT(*) FROM PlanviewMigration_Output_v2.Epics
WHERE [Demand Type] = 'Business Only'
AND [Is this demand Business Only?] <> 'Yes';
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Epic', 'Prod-Epic-018', 'Business Only Demand Type = Yes in Business Only flag',
        '0', CAST(@bad_bo_yes AS NVARCHAR),
        CASE WHEN @bad_bo_yes = 0 THEN 'PASS' ELSE 'FAIL' END);

-- Non-Business Only rows must have 'No'
SELECT @bad_bo_no = COUNT(*) FROM PlanviewMigration_Output_v2.Epics
WHERE [Demand Type] <> 'Business Only'
AND [Is this demand Business Only?] <> 'No';
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Epic', 'Prod-Epic-018', 'Non-Business Only Demand Type = No in Business Only flag',
        '0', CAST(@bad_bo_no AS NVARCHAR),
        CASE WHEN @bad_bo_no = 0 THEN 'PASS' ELSE 'FAIL' END);


-- ============================================================
-- CHECK 20 : DELIMITER FIX — Epics (Prod-Epic-021)
-- ============================================================

DECLARE @bad_delim_region INT, @bad_delim_stake INT;
SELECT @bad_delim_region = COUNT(*) FROM PlanviewMigration_Output_v2.Epics
WHERE [Change - Impacted regions - Transformed] LIKE '%, %';
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Epic', 'Prod-Epic-021', 'Change - Impacted regions — no comma delimiter remaining',
        '0', CAST(@bad_delim_region AS NVARCHAR),
        CASE WHEN @bad_delim_region = 0 THEN 'PASS' ELSE 'FAIL' END);

SELECT @bad_delim_stake = COUNT(*) FROM PlanviewMigration_Output_v2.Epics
WHERE [Change - Impacted stakeholder groups - Transformed] LIKE '%, %';
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Epic', 'Prod-Epic-021', 'Change - Impacted stakeholder groups — no comma delimiter',
        '0', CAST(@bad_delim_stake AS NVARCHAR),
        CASE WHEN @bad_delim_stake = 0 THEN 'PASS' ELSE 'FAIL' END);


-- ============================================================
-- CHECK 21 : IMPACTED PORTFOLIOS TRANSFORM (Prod-Epic-022)
-- ============================================================

-- No 'Data & AI' should remain
DECLARE @bad_ip_dai INT;
SELECT @bad_ip_dai = COUNT(*) FROM PlanviewMigration_Output_v2.Epics
WHERE [Impacted Portfolios - Transformed] LIKE '%Data & AI%';
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Epic', 'Prod-Epic-022', 'Impacted Portfolios — no Data & AI remaining',
        '0', CAST(@bad_ip_dai AS NVARCHAR),
        CASE WHEN @bad_ip_dai = 0 THEN 'PASS' ELSE 'FAIL' END);

-- No commas — only pipe delimiter
DECLARE @bad_ip_comma INT;
SELECT @bad_ip_comma = COUNT(*) FROM PlanviewMigration_Output_v2.Epics
WHERE [Impacted Portfolios - Transformed] LIKE '%,%';
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Epic', 'Prod-Epic-022', 'Impacted Portfolios — pipe delimiter only, no commas',
        '0', CAST(@bad_ip_comma AS NVARCHAR),
        CASE WHEN @bad_ip_comma = 0 THEN 'PASS' ELSE 'FAIL' END);


-- ============================================================
-- CHECK 22 : WORK STATUS MAPPING — Tasks (Prod-Task-003)
-- ============================================================

-- No ERROR values
DECLARE @bad_ws_err INT;
SELECT @bad_ws_err = COUNT(*) FROM PlanviewMigration_Output_v2.Tasks
WHERE [Work Status] = 'ERROR';
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Task', 'Prod-Task-003', 'Work Status — no ERROR values',
        '0', CAST(@bad_ws_err AS NVARCHAR),
        CASE WHEN @bad_ws_err = 0 THEN 'PASS' ELSE 'FAIL' END);

-- Only known target values
DECLARE @bad_ws_unknown INT;
SELECT @bad_ws_unknown = COUNT(*) FROM PlanviewMigration_Output_v2.Tasks
WHERE [Work Status] NOT IN (
    'New', 'Active', 'On Hold', 'Completed/Closed',
    'Cancelled', 'Rejected', 'ERROR'
)
AND [Work Status] IS NOT NULL;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Task', 'Prod-Task-003', 'Work Status — only known target values present',
        '0', CAST(@bad_ws_unknown AS NVARCHAR),
        CASE WHEN @bad_ws_unknown = 0 THEN 'PASS' ELSE 'FAIL' END);


-- ============================================================
-- CHECK 23 : EXECUTION TYPE — Tasks (Prod-Task-008)
-- ============================================================

-- Only Milestone or Business Task
DECLARE @bad_et INT;
SELECT @bad_et = COUNT(*) FROM PlanviewMigration_Output_v2.Tasks
WHERE [Execution Type] NOT IN ('Milestone', 'Business Task');
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Task', 'Prod-Task-008', 'Execution Type — only Milestone or Business Task',
        '0', CAST(@bad_et AS NVARCHAR),
        CASE WHEN @bad_et = 0 THEN 'PASS' ELSE 'FAIL' END);

-- Milestone Flag = Y must map to Milestone
DECLARE @bad_et_mf INT;
SELECT @bad_et_mf = COUNT(*) FROM PlanviewMigration_Output_v2.Tasks
WHERE [Milestone Flag] = 'Y' AND [Execution Type] <> 'Milestone';
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Task', 'Prod-Task-008', 'Milestone Flag = Y always maps to Execution Type = Milestone',
        '0', CAST(@bad_et_mf AS NVARCHAR),
        CASE WHEN @bad_et_mf = 0 THEN 'PASS' ELSE 'FAIL' END);


-- ============================================================
-- CHECK 24 : TASK MILESTONE TYPE MAPPING (Prod-Task-011)
-- ============================================================

-- Finance must be mapped to Other (not remain as Finance)
DECLARE @bad_tmt_fin INT;
SELECT @bad_tmt_fin = COUNT(*) FROM PlanviewMigration_Output_v2.Tasks
WHERE [Task or Milestone Type - Transformed] = 'Finance';
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Task', 'Prod-Task-011', 'Task Milestone Type — Finance mapped to Other',
        '0', CAST(@bad_tmt_fin AS NVARCHAR),
        CASE WHEN @bad_tmt_fin = 0 THEN 'PASS' ELSE 'FAIL' END);

-- Legal must be mapped to Legal / Regulatory
DECLARE @bad_tmt_leg INT;
SELECT @bad_tmt_leg = COUNT(*) FROM PlanviewMigration_Output_v2.Tasks
WHERE [Task or Milestone Type - Transformed] = 'Legal';
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Task', 'Prod-Task-011', 'Task Milestone Type — Legal mapped to Legal / Regulatory',
        '0', CAST(@bad_tmt_leg AS NVARCHAR),
        CASE WHEN @bad_tmt_leg = 0 THEN 'PASS' ELSE 'FAIL' END);

-- Technology / Systems must be mapped to Technology
DECLARE @bad_tmt_tech INT;
SELECT @bad_tmt_tech = COUNT(*) FROM PlanviewMigration_Output_v2.Tasks
WHERE [Task or Milestone Type - Transformed] = 'Technology / Systems';
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Task', 'Prod-Task-011', 'Task Milestone Type — Technology / Systems mapped to Technology',
        '0', CAST(@bad_tmt_tech AS NVARCHAR),
        CASE WHEN @bad_tmt_tech = 0 THEN 'PASS' ELSE 'FAIL' END);

-- INFO: all distinct target values
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
SELECT DISTINCT
    'Task', 'Prod-Task-011',
    'Task Milestone Type — distinct target values (INFO)',
    'Known values only',
    [Task or Milestone Type - Transformed],
    'INFO'
FROM PlanviewMigration_Output_v2.Tasks;


-- ============================================================
-- CHECK 25 : NULL STUBS — confirm placeholders in place
-- ============================================================

-- Prod-Epic-009 Disposition stub
DECLARE @ep_disp INT;
SELECT @ep_disp = COUNT(*) FROM PlanviewMigration_Output_v2.Epics
WHERE [Disposition] IS NOT NULL;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Epic', 'Prod-Epic-009', 'Disposition stub — all NULL (pending RosettaStone)',
        '0', CAST(@ep_disp AS NVARCHAR),
        CASE WHEN @ep_disp = 0 THEN 'PASS' ELSE 'INFO - some values present' END);

-- Prod-Task-009 Disposition stub
DECLARE @tk_disp INT;
SELECT @tk_disp = COUNT(*) FROM PlanviewMigration_Output_v2.Tasks
WHERE [Disposition] IS NOT NULL;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Task', 'Prod-Task-009', 'Disposition stub — all NULL (pending RosettaStone)',
        '0', CAST(@tk_disp AS NVARCHAR),
        CASE WHEN @tk_disp = 0 THEN 'PASS' ELSE 'INFO - some values present' END);

-- Prod-Task-010 Work Type stub
DECLARE @tk_wt INT;
SELECT @tk_wt = COUNT(*) FROM PlanviewMigration_Output_v2.Tasks
WHERE [Work Type] IS NOT NULL;
INSERT INTO #validation_results (Entity, Tracker_ID, Check_Name, Expected, Actual, Result)
VALUES ('Task', 'Prod-Task-010', 'Work Type stub — all NULL (pending RosettaStone)',
        '0', CAST(@tk_wt AS NVARCHAR),
        CASE WHEN @tk_wt = 0 THEN 'PASS' ELSE 'INFO - some values present' END);


-- ============================================================
-- FINAL RESULTS
-- ============================================================

PRINT '';
PRINT '======================================================';
PRINT 'VALIDATION RESULTS SUMMARY';
PRINT '======================================================';

-- Count PASS / FAIL / INFO
DECLARE @pass_cnt INT, @fail_cnt INT, @info_cnt INT;
SELECT
    @pass_cnt = SUM(CASE WHEN Result = 'PASS' THEN 1 ELSE 0 END),
    @fail_cnt = SUM(CASE WHEN Result = 'FAIL' THEN 1 ELSE 0 END),
    @info_cnt = SUM(CASE WHEN Result = 'INFO' THEN 1 ELSE 0 END)
FROM #validation_results;

PRINT '  PASS : ' + CAST(@pass_cnt AS VARCHAR);
PRINT '  FAIL : ' + CAST(@fail_cnt AS VARCHAR);
PRINT '  INFO : ' + CAST(@info_cnt AS VARCHAR);
PRINT '';
PRINT CASE WHEN @fail_cnt = 0
           THEN 'ALL CHECKS PASSED — SP logic validated successfully'
           ELSE ' ' + CAST(@fail_cnt AS VARCHAR) + ' CHECK(S) FAILED — review FAIL rows below'
      END;
PRINT '======================================================';

-- Full results table
SELECT
    Check_ID,
    Entity,
    Tracker_ID,
    Check_Name,
    Expected,
    Actual,
    Result
FROM #validation_results
ORDER BY Result DESC, Entity, Check_ID;

-- FAIL rows only — for quick fix focus
IF @fail_cnt > 0
BEGIN
    PRINT '';
    PRINT '-- FAILED CHECKS ONLY:';
    SELECT
        Check_ID,
        Entity,
        Tracker_ID,
        Check_Name,
        Expected,
        Actual
    FROM #validation_results
    WHERE Result = 'FAIL'
    ORDER BY Entity, Check_ID;
END

PRINT '';
PRINT 'Validation complete: ' + CONVERT(VARCHAR, GETDATE(), 120);

DROP TABLE #validation_results;
