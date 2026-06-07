CREATE OR ALTER VIEW [PlanviewMigration_Transform_Output].[vw_Epics_Consolidated] AS

SELECT

    /* ==========================================
       SECTION 1: [PlanviewMigration_Output].[Epics_v12] BASE COLUMNS
       Alias: a
       Excluded: Run_ID, Save_Timestamp, Execution Type
       ========================================== */

    COALESCE(a.[Name],                                      b.[Name])                               AS [Name],
    COALESCE(a.[Work ID #],                                 b.[Work ID #])                          AS [Work ID #],
    COALESCE(a.[Sequence ID],                               b.[Sequence ID])                        AS [Sequence ID],
    -- Name difference: a "Epic Name w_ container Name" = b "Epic Name (w/ container Name)"
    COALESCE(a.[Epic Name w_ container Name],               b.[Epic Name (w/ container Name)])      AS [Epic Name w_ container Name],
    COALESCE(a.[Epic Name],                                 b.[Epic Name])                          AS [Epic Name],
    COALESCE(a.[Associated Initiative Seq ID],              b.[Associated Initiative Seq ID])       AS [Associated Initiative Seq ID],
    COALESCE(a.[Associated Initiative],                     b.[Associated Initiative])              AS [Associated Initiative],
    COALESCE(a.[Description],                               b.[Description])                        AS [Description],
    COALESCE(a.[Initiative Owner],                          b.[Initiative Owner])                   AS [Initiative Owner],
    COALESCE(a.[Epic Owner],                                b.[Epic Owner])                         AS [Epic Owner],
    COALESCE(a.[Work Status],                               b.[Work Status])                        AS [Work Status],
    COALESCE(a.[Health Status],                             b.[Health Status])                      AS [Health Status],
    COALESCE(a.[Demand Type],                               b.[Demand Type])                        AS [Demand Type],
    COALESCE(a.[Work Type],                                 b.[Work Type])                          AS [Work Type],
    -- Name difference: a "What Business Unit does this request support?" = b "Demand Domain or Portfolio"
    COALESCE(a.[What Business Unit does this request support?], b.[Demand Domain or Portfolio])     AS [What Business Unit does this request support?],
    -- Name difference: a "Level of Governance" = b "Governance Level"
    COALESCE(a.[Level of Governance],                       b.[Governance Level])                   AS [Level of Governance],
    COALESCE(a.[Phase],                                     b.[Phase])                              AS [Phase],
    COALESCE(a.[Exclude from Migratlon],                    b.[Exclude from Migratlon])             AS [Exclude from Migratlon],
    COALESCE(a.[Epic Impacted Pods],                        b.[Epic Impacted Pods])                 AS [Epic Impacted Pods],
    COALESCE(a.[In Scope],                                  b.[In Scope])                           AS [In Scope],
    COALESCE(a.[Out of Scope],                              b.[Out of Scope])                       AS [Out of Scope],
    COALESCE(a.[T-Shirt Size],                              b.[T-Shirt Size])                       AS [T-Shirt Size],
    COALESCE(a.[Expected Business Outcome],                 b.[Expected Business Outcome])          AS [Expected Business Outcome],
    COALESCE(a.[Primary Type of Value Impact],              b.[Primary Type of Value Impact])       AS [Primary Type of Value Impact],
    COALESCE(a.[Primary Type of Value],                     b.[Primary Type of Value])              AS [Primary Type of Value],
    -- Name difference: a "Home Domain_Portfolio" = b "Home Domain/Portfolio"
    COALESCE(a.[Home Domain_Portfolio],                     b.[Home Domain/Portfolio])              AS [Home Domain_Portfolio],
    -- Name difference: a "Other Impacted Portfolios" = b "Impacted Portfolios"
    COALESCE(a.[Other Impacted Portfolios],                 b.[Impacted Portfolios])                AS [Other Impacted Portfolios],
    COALESCE(a.[Impacted Solutions],                        b.[Impacted Solutions])                 AS [Impacted Solutions],
    COALESCE(a.[PPM Project Number],                        b.[PPM Project Number])                 AS [PPM Project Number],
    COALESCE(a.[Ability To Statements],                     b.[Ability To Statements])              AS [Ability To Statements],
    COALESCE(a.[Epic Architectural Documentation],          b.[Epic Architectural Documentation])   AS [Epic Architectural Documentation],
    COALESCE(a.[IT Architect],                              b.[IT Architect])                       AS [IT Architect],
    COALESCE(a.[Business Architect],                        b.[Business Architect])                 AS [Business Architect],
    COALESCE(a.[Dependencies & Constraints],                b.[Dependencies & Constraints])         AS [Dependencies & Constraints],
    COALESCE(a.[Agility #],                                 b.[Agility #])                          AS [Agility #],
    COALESCE(a.[AgilePlace External Id],                    b.[AgilePlace External Id])             AS [AgilePlace External Id],
    COALESCE(a.[Agility URL],                               b.[Agility URL])                        AS [Agility URL],
    COALESCE(a.[Azure Subscription Group],                  b.[Azure Subscription Group])           AS [Azure Subscription Group],
    COALESCE(a.[Baseline Start],                            b.[Baseline Start])                     AS [Baseline Start],
    COALESCE(a.[Baseline Finish],                           b.[Baseline Finish])                    AS [Baseline Finish],
    COALESCE(a.[Change - Impacted regions],                 b.[Change - Impacted regions])          AS [Change - Impacted regions],
    COALESCE(a.[Change - Impacted stakeholder groups],      b.[Change - Impacted stakeholder groups])  AS [Change - Impacted stakeholder groups],
    COALESCE(a.[Change - Number of external stakeholders],  b.[Change - Number of external stakeholders])  AS [Change - Number of external stakeholders],
    COALESCE(a.[Change - Number of internal stakeholders],  b.[Change - Number of internal stakeholders])  AS [Change - Number of internal stakeholders],
    -- Name difference: a "Change - Significance Magnitude" = b "Change - Significance (Magnitude)"
    COALESCE(a.[Change - Significance Magnitude],           b.[Change - Significance (Magnitude)]) AS [Change - Significance Magnitude],
    COALESCE(a.[Change - Willingness],                      b.[Change - Willingness])               AS [Change - Willingness],
    COALESCE(a.[DRIVE Pod Lead],                            b.[DRIVE Pod Lead])                     AS [DRIVE Pod Lead],
    COALESCE(a.[DRIVE Pod Name],                            b.[DRIVE Pod Name])                     AS [DRIVE Pod Name],
    COALESCE(a.[EAI #],                                     b.[EAI #])                              AS [EAI #],
    COALESCE(a.[Epic Notes and Comments],                   b.[Epic Notes and Comments])            AS [Epic Notes and Comments],
    COALESCE(a.[IdeaPlace URL],                             b.[IdeaPlace URL])                      AS [IdeaPlace URL],
    -- Name difference: a "L2 One-time Benefit $-Soft" = b "L2 One-time Benefit ($)-Soft"
    COALESCE(a.[L2 One-time Benefit $-Soft],                b.[L2 One-time Benefit ($)-Soft])       AS [L2 One-time Benefit $-Soft],
    COALESCE(a.[Key Assumptions Made in Quantifying Impact],b.[Key Assumptions Made in Quantifying Impact])  AS [Key Assumptions Made in Quantifying Impact],
    -- Name difference: a "PEL_Solution Management Approver 1" = b "PEL/Solution Management Approver 1"
    COALESCE(a.[PEL_Solution Management Approver 1],        b.[PEL/Solution Management Approver 1]) AS [PEL_Solution Management Approver 1],
    -- Name difference: a "PEL_Solution Management Approver 2" = b "PEL/Solution Management Approver 2"
    COALESCE(a.[PEL_Solution Management Approver 2],        b.[PEL/Solution Management Approver 2]) AS [PEL_Solution Management Approver 2],
    COALESCE(a.[PEO],                                       b.[PEO])                                AS [PEO],
    COALESCE(a.[Triage Comments],                           b.[Triage Comments])                    AS [Triage Comments],


    /* ==========================================
       SECTION 2: [PlanviewMigration_Transform_Output].[Epics_SP3_v1] ADDITIONAL COLUMNS
       Alias: b  |  SP3-only columns + Execution Type moved here
       ========================================== */

    b.[Index_ID]                                                                                    AS [Index_ID],
    b.[Execution Type]                                                                              AS [Execution Type],
    b.[Demand Type - Legacy]                                                                        AS [Demand Type - Legacy],
    b.[Execution Type - Legacy]                                                                     AS [Execution Type - Legacy],
    b.[GrandParent Index]                                                                           AS [GrandParent Index],
    b.[Parent Sequence ID]                                                                          AS [Parent Sequence ID],
    b.[Inherited Flow Type]                                                                         AS [Inherited Flow Type],
    b.[Epic Flow Type]                                                                              AS [Epic Flow Type],


    /* ==========================================
       SECTION 3: SOURCE TRACEABILITY FLAGS
       ========================================== */

    CASE WHEN a.[Sequence ID] IS NOT NULL THEN 'Y' ELSE 'N' END                                    AS [In_Epics_v12],
    CASE WHEN b.[Sequence ID] IS NOT NULL THEN 'Y' ELSE 'N' END                                    AS [In_Epics_SP3_v1]

FROM      [PlanviewMigration_Output].[Epics_v12]                                    a
FULL OUTER JOIN [PlanviewMigration_Transform_Output].[Epics_SP3_v1]                 b   ON  a.[Sequence ID] = b.[Sequence ID];
