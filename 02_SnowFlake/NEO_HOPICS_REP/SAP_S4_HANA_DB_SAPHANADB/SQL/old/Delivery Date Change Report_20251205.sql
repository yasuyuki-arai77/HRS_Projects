/* =============================================================================
　要件
　　Delivery Date Change Report.xlsx
  説明
    Excelに記載の要件に沿い、Step1→Step2-1→Step2-2→Step2-3→Step2-4→Step3 の順でLEFT OUTER JOIN
    最終SELECTで「ToBeレポート」列名へリネーム。
============================================================================= */
WITH
/* ---------------------------------------------------------------------------
  Step1 : Work1
  ・変更履歴（CDHDR×CDPOS）を（CHANGENR, OBJECTID）で結合
  ・変更日（UDATE）を「今日から30日以内」に限定
--------------------------------------------------------------------------- */
Work1 AS (
  SELECT
    CDHDR.CHANGENR AS CHANGENR,
    CDHDR.OBJECTID AS OBJECTID,
    CDHDR.UDATE    AS UDATE,
    CDPOS.VALUE_OLD AS VALUE_OLD,
    CDPOS.VALUE_NEW AS VALUE_NEW,
    CDPOS.TABKEY   AS TABKEY,
    SUBSTRING(CDPOS.TABKEY, 14, 6) AS SOLINE,
    SUBSTRING(CDPOS.TABKEY, 20, 4) AS SCHELINE
  FROM NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.CDHDR AS CDHDR
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.CDPOS AS CDPOS
    ON CDHDR.CHANGENR = CDPOS.CHANGENR
   AND CDHDR.OBJECTID = CDPOS.OBJECTID
  WHERE CDHDR.OBJECTCLAS = 'VERKBELEG'
    AND CDPOS.TABNAME   = 'VBEP'
    AND CDHDR.MANDANT   = '900'     /* 開発=420（本番=900） */
    AND CDPOS.FNAME     = 'EDATU'
    AND CDHDR.UDATE    >= DATEADD('day', -30, CURRENT_DATE())   /*直近30日 */
),

/* ---------------------------------------------------------------------------
  Step2-1 : Work2_1（VBAP：品目列を付与）
  ・Work1 × VBAP（OBJECTID=VBELN、SOLINE=POSNR）
--------------------------------------------------------------------------- */
Work2_1 AS (
  SELECT
    Work1.CHANGENR,
    Work1.OBJECTID,
    Work1.UDATE,
    Work1.VALUE_OLD,
    Work1.VALUE_NEW,
    Work1.TABKEY,
    Work1.SOLINE,
    Work1.SCHELINE,
    VBAP.MATNR,
    VBAP.ARKTX,
    VBAP.KDMAT,
    VBAP.BSTKD_ANA,
    VBAP.BERID
  FROM Work1
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBAP AS VBAP
    ON Work1.OBJECTID = VBAP.VBELN
   AND Work1.SOLINE   = VBAP.POSNR
),

/* ---------------------------------------------------------------------------
  Step2-2 : Work2_2（VBPA：AG/WE/ZR 明細優先・ヘッダ代替）
--------------------------------------------------------------------------- */
Work2_2 AS (
  SELECT
    Work2_1.CHANGENR,
    Work2_1.OBJECTID,
    Work2_1.UDATE,
    Work2_1.VALUE_OLD,
    Work2_1.VALUE_NEW,
    Work2_1.TABKEY,
    Work2_1.SOLINE,
    Work2_1.SCHELINE,
    Work2_1.MATNR,
    Work2_1.ARKTX,
    Work2_1.KDMAT,
    Work2_1.BSTKD_ANA,
    Work2_1.BERID,

    /* AG（Sold-to） */
    COALESCE(VBPA_AG_L.ASSIGNED_BP, VBPA_AG_H.ASSIGNED_BP) AS SoldToBP,
    COALESCE(VBPA_AG_L.ADRNR,       VBPA_AG_H.ADRNR)       AS SoldToBPAddr,

    /* WE（Ship-to） */
    COALESCE(VBPA_WE_L.ASSIGNED_BP, VBPA_WE_H.ASSIGNED_BP) AS ShipToBP,
    COALESCE(VBPA_WE_L.ADRNR,       VBPA_WE_H.ADRNR)       AS ShipToBPAddr,

    /* ZR（PIC2） */
    COALESCE(VBPA_ZR_L.ASSIGNED_BP, VBPA_ZR_H.ASSIGNED_BP) AS PIC2BP,
    COALESCE(VBPA_ZR_L.ADRNR,       VBPA_ZR_H.ADRNR)       AS PIC2Addr,
    COALESCE(VBPA_ZR_L.LAND1,       VBPA_ZR_H.LAND1)       AS PIC2Country
  FROM Work2_1

  /* ===== AG：明細（000000除外 & 対象明細のみ） ===== */
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA AS VBPA_AG_L
    ON Work2_1.OBJECTID      = VBPA_AG_L.VBELN
   AND Work2_1.SOLINE        = VBPA_AG_L.POSNR
   AND VBPA_AG_L.PARVW       = 'AG'
   AND VBPA_AG_L.POSNR      <> '000000'

  /* ===== AG：ヘッダ（明細が1件も無いときだけ） ===== */
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA AS VBPA_AG_H
    ON Work2_1.OBJECTID      = VBPA_AG_H.VBELN
   AND VBPA_AG_H.PARVW       = 'AG'
   AND VBPA_AG_H.POSNR       = '000000'
   AND NOT EXISTS (
         SELECT 1
           FROM NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA v
          WHERE v.VBELN = Work2_1.OBJECTID
            AND v.PARVW = 'AG'
            AND v.POSNR <> '000000'
       )

  /* ===== WE：明細 ===== */
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA AS VBPA_WE_L
    ON Work2_1.OBJECTID      = VBPA_WE_L.VBELN
   AND Work2_1.SOLINE        = VBPA_WE_L.POSNR
   AND VBPA_WE_L.PARVW       = 'WE'
   AND VBPA_WE_L.POSNR      <> '000000'

  /* ===== WE：ヘッダ（明細なし時のみ） ===== */
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA AS VBPA_WE_H
    ON Work2_1.OBJECTID      = VBPA_WE_H.VBELN
   AND VBPA_WE_H.PARVW       = 'WE'
   AND VBPA_WE_H.POSNR       = '000000'
   AND NOT EXISTS (
         SELECT 1
           FROM NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA v
          WHERE v.VBELN = Work2_1.OBJECTID
            AND v.PARVW = 'WE'
            AND v.POSNR <> '000000'
       )

  /* ===== ZR：明細 ===== */
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA AS VBPA_ZR_L
    ON Work2_1.OBJECTID      = VBPA_ZR_L.VBELN
   AND Work2_1.SOLINE        = VBPA_ZR_L.POSNR
   AND VBPA_ZR_L.PARVW       = 'ZR'
   AND VBPA_ZR_L.POSNR      <> '000000'

  /* ===== ZR：ヘッダ（明細なし時のみ） ===== */
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA AS VBPA_ZR_H
    ON Work2_1.OBJECTID      = VBPA_ZR_H.VBELN
   AND VBPA_ZR_H.PARVW       = 'ZR'
   AND VBPA_ZR_H.POSNR       = '000000'
   AND NOT EXISTS (
         SELECT 1
           FROM NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA v
          WHERE v.VBELN = Work2_1.OBJECTID
            AND v.PARVW = 'ZR'
            AND v.POSNR <> '000000'
       )
),

/* ---------------------------------------------------------------------------
  Step2-3 : Work2_3（VBEP：希望/回答納期）
--------------------------------------------------------------------------- */
Work2_3 AS (
  SELECT
    Work2_2.CHANGENR,
    Work2_2.OBJECTID,
    Work2_2.UDATE,
    Work2_2.VALUE_OLD,
    Work2_2.VALUE_NEW,
    Work2_2.TABKEY,
    Work2_2.SOLINE,
    Work2_2.SCHELINE,
    Work2_2.MATNR,
    Work2_2.ARKTX,
    Work2_2.KDMAT,
    Work2_2.BSTKD_ANA,
    Work2_2.BERID,
    Work2_2.SoldToBP,
    Work2_2.SoldToBPAddr,
    Work2_2.ShipToBP,
    Work2_2.ShipToBPAddr,
    Work2_2.PIC2BP,
    Work2_2.PIC2Addr,
    Work2_2.PIC2Country,
    VBEP.REQ_DLVDATE,
    VBEP.EDATU
  FROM Work2_2
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBEP AS VBEP
    ON Work2_2.OBJECTID = VBEP.VBELN
   AND Work2_2.SOLINE   = VBEP.POSNR
   AND Work2_2.SCHELINE = VBEP.ETENR
),

/* ---------------------------------------------------------------------------
  Step2-4 : Work2（VBFA：後続PO）
--------------------------------------------------------------------------- */
Work2 AS (
  SELECT
    Work2_3.CHANGENR,
    Work2_3.OBJECTID,
    Work2_3.UDATE,
    Work2_3.VALUE_OLD,
    Work2_3.VALUE_NEW,
    Work2_3.TABKEY,
    Work2_3.SOLINE,
    Work2_3.SCHELINE,
    Work2_3.MATNR,
    Work2_3.ARKTX,
    Work2_3.KDMAT,
    Work2_3.BSTKD_ANA,
    Work2_3.BERID,
    Work2_3.SoldToBP,
    Work2_3.SoldToBPAddr,
    Work2_3.ShipToBP,
    Work2_3.ShipToBPAddr,
    Work2_3.PIC2BP,
    Work2_3.PIC2Addr,
    Work2_3.PIC2Country,
    Work2_3.REQ_DLVDATE,
    Work2_3.EDATU,
    VBFA.VBELN,
    VBFA.POSNV
  FROM Work2_3
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBFA AS VBFA
    ON Work2_3.OBJECTID = VBFA.VBELV
   AND Work2_3.SOLINE   = VBFA.POSNV
  WHERE VBFA.VBTYP_N = 'V'
   AND VBFA.VBTYP_V = 'C'
),

/* ---------------------------------------------------------------------------
  Step3 : Work3（ADRC：名称付与 ×3回）
  ・DataMapping の条件を各JOINの ON に明記（ADDRNUMBER）
    1) SoldToBPName：CLIENT='900'
    2) ShipToBPName：CLIENT='900'
    3) PIC2BPName：CLIENT='900'
--------------------------------------------------------------------------- */
Work3 AS (
  SELECT
    Work2.CHANGENR,
    Work2.OBJECTID,
    Work2.UDATE,
    Work2.VALUE_OLD,
    Work2.VALUE_NEW,
    Work2.TABKEY,
    Work2.SOLINE,
    Work2.SCHELINE,
    Work2.MATNR,
    Work2.ARKTX,
    Work2.KDMAT,
    Work2.BSTKD_ANA,
    Work2.BERID,
    Work2.SoldToBP,
    Work2.SoldToBPAddr,
    Work2.ShipToBP,
    Work2.ShipToBPAddr,
    Work2.PIC2BP,
    Work2.PIC2Addr,
    Work2.PIC2Country,
    Work2.REQ_DLVDATE,
    Work2.EDATU,
    Work2.VBELN,
    Work2.POSNV,
    ADRC_AG.NAME1 AS SoldToBPName,
    ADRC_WE.NAME1 AS ShipToBPName,
    ADRC_ZR.NAME1 AS PIC2BPName
  FROM Work2

  /* 1) SoldToBPName */
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.ADRC AS ADRC_AG
    ON Work2.SoldToBPAddr = ADRC_AG.ADDRNUMBER
   AND ADRC_AG.CLIENT      = '900'

  /* 2) ShipToBPName */
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.ADRC AS ADRC_WE
    ON Work2.ShipToBPAddr  = ADRC_WE.ADDRNUMBER
   AND ADRC_WE.CLIENT      = '900'

  /* 3) PIC2BPName */
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.ADRC AS ADRC_ZR
    ON Work2.PIC2Addr      = ADRC_ZR.ADDRNUMBER
   AND ADRC_ZR.CLIENT      = '900'
)

/* ---------------------------------------------------------------------------
  最終出力：ToBeレポートの列名・順序でSELECT
--------------------------------------------------------------------------- */
SELECT DISTINCT
  OBJECTID     AS "Sales Doc No",
  SOLINE       AS "Sales Line No",
  SoldToBP     AS "Sold to CD",
  SoldToBPName AS "Sold to name",
  BSTKD_ANA    AS "Customer Ref No",
  PIC2BPName   AS "PIC2 Name",
  PIC2Country  AS "PIC2 Branch",
  MATNR        AS "CL",
  BERID        AS "Sales Org",
  ARKTX        AS "Description",
  KDMAT        AS "CustomerPart#",
  UDATE        AS "Updated Date",
  REQ_DLVDATE  AS "Org Req Date",
  EDATU        AS "Current Delivery Date",
  SUBSTR(TO_VARCHAR(VALUE_NEW), 1, 4) || '-' ||
  SUBSTR(TO_VARCHAR(VALUE_NEW), 5, 2) || '-' ||
  SUBSTR(TO_VARCHAR(VALUE_NEW), 7, 2)            AS "Current MAD",
  SUBSTR(TO_VARCHAR(VALUE_OLD), 1, 4) || '-' ||
  SUBSTR(TO_VARCHAR(VALUE_OLD), 5, 2) || '-' ||
  SUBSTR(TO_VARCHAR(VALUE_OLD), 7, 2)            AS "Previous MAD",
  VBELN        AS "Connected PO",
  POSNV        AS "Connected PO Item"
FROM Work3;
