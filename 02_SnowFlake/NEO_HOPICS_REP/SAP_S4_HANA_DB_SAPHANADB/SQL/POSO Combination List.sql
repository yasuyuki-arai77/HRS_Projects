/* =============================================================================
  要件
    SAP_POSO Combination List

  説明
    ・POSO Combination List_20251127.xlsx の要件に沿って作成
    ・Step1 → Step2-1 → Step2-2 → Step2-3 → Step3 → Step4 → Step5 の順で
      WITH句のCTEを LEFT OUTER JOIN でつないでいく
    ・Excelに記載のカラム名を 100% そのまま使用する（全角・大文字小文字含む）
============================================================================= */
WITH
/* ---------------------------------------------------------------------------
  Step1 : Work1
  ・VBEP を VBELN, POSNR 単位に集計
  ・出荷残（OpenQTY）> 0 の明細のみ残す
  ・一番下のスケジュール行番号 MAXschLine を保持
--------------------------------------------------------------------------- */
Work1 AS (
  SELECT
    VBEP.MANDT,
    VBEP.VBELN,
    VBEP.POSNR,
    SUM(VBEP.WMENG)                       AS SOQTY,
    SUM(VBEP.DLVQTY_SU)                   AS DLVQTY,
    SUM(VBEP.WMENG) - SUM(VBEP.DLVQTY_SU) AS OpenQTY,
    MAX(VBEP.ETENR)                       AS MAXschLine
  FROM
    NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBEP AS VBEP
  WHERE
    VBEP.MANDT = '900'  /* 開発=420（本番=900） */
  GROUP BY
    VBEP.MANDT,
    VBEP.VBELN,
    VBEP.POSNR
  HAVING
    SUM(VBEP.WMENG) - SUM(VBEP.DLVQTY_SU) > 0
),

/* ---------------------------------------------------------------------------
  Step2-1 : Work2_1（VBEP：最後のスケジュール行の納期情報）
--------------------------------------------------------------------------- */
Work2_1 AS (
  SELECT
    Work1.MANDT,
    Work1.VBELN,
    Work1.POSNR,
    Work1.SOQTY,
    Work1.DLVQTY,
    Work1.OpenQTY,
    Work1.MAXschLine,
    VBEP.EDATU,
    VBEP.MBDAT,
    VBEP.WADAT
  FROM
    Work1
    LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBEP AS VBEP
      ON Work1.MANDT      = VBEP.MANDT
     AND Work1.VBELN      = VBEP.VBELN
     AND Work1.POSNR      = VBEP.POSNR
     AND Work1.MAXschLine = VBEP.ETENR
),

/* ---------------------------------------------------------------------------
  Step2-2 : Work2_2（VBAP：受注明細情報付与）
--------------------------------------------------------------------------- */
Work2_2 AS (
  SELECT
    Work2_1.MANDT,
    Work2_1.VBELN,
    Work2_1.POSNR,
    Work2_1.SOQTY,
    Work2_1.DLVQTY,
    Work2_1.OpenQTY,
    Work2_1.MAXschLine,
    Work2_1.EDATU,
    Work2_1.MBDAT,
    Work2_1.WADAT,
    VBAP.ARKTX,
    VBAP.MATNR,
    VBAP.ZZSECTION,
    VBAP.BSTKD_ANA,
    VBAP.KDMAT,
    VBAP.VKORG_ANA,
    VBAP.ERDAT,
    VBAP.LGORT,
    VBAP.UMZIZ
  FROM
    Work2_1
    LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBAP AS VBAP
      ON Work2_1.MANDT = VBAP.MANDT
     AND Work2_1.VBELN = VBAP.VBELN
     AND Work2_1.POSNR = VBAP.POSNR
),

/* ---------------------------------------------------------------------------
  Step2-3 : Work2_3（VBPA：パートナ情報）
  ・Work2_2 × VBPA
    - VBELN, POSNR, PARVW（AG / WE / ZI）で結合
  ・AG/WE/ZI は「明細優先・ヘッダ代替」
--------------------------------------------------------------------------- */
Work2_3 AS (
  SELECT
    Work2_2.MANDT,
    Work2_2.VBELN,
    Work2_2.POSNR,
    Work2_2.SOQTY,
    Work2_2.DLVQTY,
    Work2_2.OpenQTY,
    Work2_2.MAXschLine,
    Work2_2.EDATU,
    Work2_2.MBDAT,
    Work2_2.WADAT,
    Work2_2.MATNR,
    Work2_2.ARKTX,
    Work2_2.ZZSECTION,
    Work2_2.BSTKD_ANA,
    Work2_2.KDMAT,
    Work2_2.VKORG_ANA,
    Work2_2.ERDAT,
    Work2_2.LGORT,
    Work2_2.UMZIZ,

    /* AG（Sold-to） */
    COALESCE(VBPA_AG_L.ASSIGNED_BP, VBPA_AG_H.ASSIGNED_BP) AS SoldToBP,
    COALESCE(VBPA_AG_L.ADRNR,       VBPA_AG_H.ADRNR)       AS SoldToBPAddr,

    /* WE（Ship-to） */
    COALESCE(VBPA_WE_L.ASSIGNED_BP, VBPA_WE_H.ASSIGNED_BP) AS ShipToBP,
    COALESCE(VBPA_WE_L.ADRNR,       VBPA_WE_H.ADRNR)       AS ShipToBPAddr,

    /* ZI（PIC2） */
    COALESCE(VBPA_ZI_L.ASSIGNED_BP, VBPA_ZI_H.ASSIGNED_BP) AS PIC2BP,
    COALESCE(VBPA_ZI_L.ADRNR,       VBPA_ZI_H.ADRNR)       AS PIC2Addr,
    COALESCE(VBPA_ZI_L.LAND1,       VBPA_ZI_H.LAND1)       AS PIC2Country
  FROM
    Work2_2

  /* ===== AG：明細（000000除外 & 対象明細のみ） ===== */
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA AS VBPA_AG_L
    ON Work2_2.MANDT = VBPA_AG_L.MANDT
   AND Work2_2.VBELN = VBPA_AG_L.VBELN
   AND Work2_2.POSNR = VBPA_AG_L.POSNR
   AND VBPA_AG_L.PARVW = 'AG'
   AND VBPA_AG_L.POSNR <> '000000'

  /* ===== AG：ヘッダ（明細が1件も無いときだけ） ===== */
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA AS VBPA_AG_H
    ON Work2_2.MANDT = VBPA_AG_H.MANDT
   AND Work2_2.VBELN = VBPA_AG_H.VBELN
   AND VBPA_AG_H.PARVW = 'AG'
   AND VBPA_AG_H.POSNR = '000000'
   AND NOT EXISTS (
         SELECT 1
           FROM NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA AS VBPA_AG_CHK
          WHERE VBPA_AG_CHK.MANDT = Work2_2.MANDT
            AND VBPA_AG_CHK.VBELN = Work2_2.VBELN
            AND VBPA_AG_CHK.PARVW = 'AG'
            AND VBPA_AG_CHK.POSNR <> '000000'
       )

  /* ===== WE：明細 ===== */
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA AS VBPA_WE_L
    ON Work2_2.MANDT = VBPA_WE_L.MANDT
   AND Work2_2.VBELN = VBPA_WE_L.VBELN
   AND Work2_2.POSNR = VBPA_WE_L.POSNR
   AND VBPA_WE_L.PARVW = 'WE'
   AND VBPA_WE_L.POSNR <> '000000'

  /* ===== WE：ヘッダ（明細なし時のみ） ===== */
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA AS VBPA_WE_H
    ON Work2_2.MANDT = VBPA_WE_H.MANDT
   AND Work2_2.VBELN = VBPA_WE_H.VBELN
   AND VBPA_WE_H.PARVW = 'WE'
   AND VBPA_WE_H.POSNR = '000000'
   AND NOT EXISTS (
         SELECT 1
           FROM NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA AS VBPA_WE_CHK
          WHERE VBPA_WE_CHK.MANDT = Work2_2.MANDT
            AND VBPA_WE_CHK.VBELN = Work2_2.VBELN
            AND VBPA_WE_CHK.PARVW = 'WE'
            AND VBPA_WE_CHK.POSNR <> '000000'
       )

  /* ===== ZI：明細 ===== */
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA AS VBPA_ZI_L
    ON Work2_2.MANDT = VBPA_ZI_L.MANDT
   AND Work2_2.VBELN = VBPA_ZI_L.VBELN
   AND Work2_2.POSNR = VBPA_ZI_L.POSNR
   AND VBPA_ZI_L.PARVW = 'ZI'
   AND VBPA_ZI_L.POSNR <> '000000'

  /* ===== ZI：ヘッダ（明細なし時のみ） ===== */
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA AS VBPA_ZI_H
    ON Work2_2.MANDT = VBPA_ZI_H.MANDT
   AND Work2_2.VBELN = VBPA_ZI_H.VBELN
   AND VBPA_ZI_H.PARVW = 'ZI'
   AND VBPA_ZI_H.POSNR = '000000'
   AND NOT EXISTS (
         SELECT 1
           FROM NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBPA AS VBPA_ZI_CHK
          WHERE VBPA_ZI_CHK.MANDT = Work2_2.MANDT
            AND VBPA_ZI_CHK.VBELN = Work2_2.VBELN
            AND VBPA_ZI_CHK.PARVW = 'ZI'
            AND VBPA_ZI_CHK.POSNR <> '000000'
       )
),

/* ---------------------------------------------------------------------------
  Step3 : Work3（ADRC：パートナー名称付与）
  ・Work2_3 × ADRC
    - SoldToBPAddr / ShipToBPAddr / PIC2Addr = ADRNUMBER,
    - SoldToBPName / ShipToBPName / PIC2BPName を取得
--------------------------------------------------------------------------- */
Work3 AS (
  SELECT
    Work2_3.MANDT,
    Work2_3.VBELN,
    Work2_3.POSNR,
    Work2_3.SOQTY,
    Work2_3.DLVQTY,
    Work2_3.OpenQTY,
    Work2_3.MAXschLine,
    Work2_3.EDATU,
    Work2_3.MBDAT,
    Work2_3.WADAT,
    Work2_3.MATNR,
    Work2_3.ARKTX,
    Work2_3.ZZSECTION,
    Work2_3.BSTKD_ANA,
    Work2_3.KDMAT,
    Work2_3.VKORG_ANA,
    Work2_3.ERDAT,
    Work2_3.LGORT,
    Work2_3.UMZIZ,
    Work2_3.SoldToBP,
    Work2_3.SoldToBPAddr,
    Work2_3.ShipToBP,
    Work2_3.ShipToBPAddr,
    Work2_3.PIC2BP,
    Work2_3.PIC2Addr,
    Work2_3.PIC2Country,
    ADRC_AG.NAME1 AS SoldToBPName,
    ADRC_WE.NAME1 AS ShipToBPName,
    ADRC_ZI.NAME1 AS PIC2BPName
  FROM
    Work2_3
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.ADRC AS ADRC_AG
    ON Work2_3.SoldToBPAddr = ADRC_AG.ADDRNUMBER
   AND Work2_3.MANDT = ADRC_AG.CLIENT
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.ADRC AS ADRC_WE
    ON Work2_3.ShipToBPAddr = ADRC_WE.ADDRNUMBER
   AND Work2_3.MANDT = ADRC_WE.CLIENT
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.ADRC AS ADRC_ZI
    ON Work2_3.PIC2Addr = ADRC_ZI.ADDRNUMBER
   AND Work2_3.MANDT = ADRC_ZI.CLIENT
),

/* ---------------------------------------------------------------------------
  Step4 : Work4（VBFA：販売伝票フローから後続PO取得）
  ・Work3 × VBFA
    - VBELV（前伝票）= 受注VBELN
    - POSNN（前明細）= 受注明細POSNR
    - VBTYP_V='C'（受注） / VBTYP_N='V'（購買発注）
--------------------------------------------------------------------------- */
Work4 AS (
  SELECT
    Work3.MANDT,
    Work3.VBELN,
    Work3.POSNR,
    Work3.SOQTY,
    Work3.DLVQTY,
    Work3.OpenQTY,
    Work3.MAXschLine,
    Work3.EDATU,
    Work3.MBDAT,
    Work3.WADAT,
    Work3.ARKTX,
    Work3.MATNR,
    Work3.ZZSECTION,
    Work3.BSTKD_ANA,
    Work3.KDMAT,
    Work3.VKORG_ANA,
    Work3.ERDAT,
    Work3.LGORT,
    Work3.UMZIZ,
    Work3.SoldToBP,
    Work3.SoldToBPAddr,
    Work3.ShipToBP,
    Work3.ShipToBPAddr,
    Work3.PIC2BP,
    Work3.PIC2Addr,
    Work3.PIC2Country,
    Work3.SoldToBPName,
    Work3.ShipToBPName,
    Work3.PIC2BPName,
    VBFA.VBELN     AS VBELN_PO,
    VBFA.POSNN     AS POSNN_PO
  FROM 
    Work3
  LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBFA AS VBFA
    ON Work3.MANDT = VBFA.MANDT
   AND Work3.VBELN = VBFA.VBELV
   AND Work3.POSNR = VBFA.POSNV
  WHERE VBFA.VBTYP_V = 'C'
    AND VBFA.VBTYP_N = 'V'
),


/* ---------------------------------------------------------------------------
  Step5 : Work5（EKES / EKET：PO納期・回答納期）
--------------------------------------------------------------------------- */
Work5 AS (
  SELECT
    Work4.MANDT,
    Work4.VBELN,
    Work4.POSNR,
    Work4.SOQTY,
    Work4.DLVQTY,
    Work4.OpenQTY,
    Work4.MAXschLine,
    Work4.EDATU,
    Work4.MBDAT,
    Work4.WADAT,
    Work4.ARKTX,
    Work4.MATNR,
    Work4.ZZSECTION,
    Work4.BSTKD_ANA,
    Work4.KDMAT,
    Work4.VKORG_ANA,
    Work4.ERDAT,
    Work4.LGORT,
    Work4.UMZIZ,
    Work4.SoldToBP,
    Work4.SoldToBPAddr,
    Work4.ShipToBP,
    Work4.ShipToBPAddr,
    Work4.PIC2BP,
    Work4.PIC2Addr,
    Work4.PIC2Country,
    Work4.SoldToBPName,
    Work4.ShipToBPName,
    Work4.PIC2BPName,
    Work4.VBELN_PO,
    Work4.POSNN_PO,
    EKES.EINDT  AS ABDate,
    EKET.EINDT AS ReqDate
  FROM 
    Work4
    LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.EKES AS EKES
      ON Work4.VBELN_PO = EKES.EBELN
     AND substr(Work4.POSNN_PO,2,5) = EKES.EBELP
     AND EKES.EBTYP  = 'AB'
    LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.EKET AS EKET
      ON Work4.VBELN_PO = EKET.EBELN
     AND substr(Work4.POSNN_PO,2,5) = EKET.EBELP
     AND EKET.ETENR = '0001'
)

/* ---------------------------------------------------------------------------
  最終出力
  ・Reportシート（ToBeテーブル）の列名・順に合わせてSELECT
--------------------------------------------------------------------------- */
SELECT
  MANDT,
  VBELN        AS "Sales Document",
  POSNR        AS "Sales Document Item",
  SOQTY,
  DLVQTY,
  OpenQTY,
  MAXschLine,
  EDATU        AS "Delivery Date",
  MBDAT        AS "Material Avail. Date",
  WADAT        AS "Goods Issue Date",
  ARKTX        AS "Item Description",
  MATNR        AS Material,
  ZZSECTION    AS "Section",
  BSTKD_ANA    AS "Customer Reference",
  KDMAT        AS "Customer Material Number",
  VKORG_ANA    AS "Sales Org",
  ERDAT        AS "Created On",
  LGORT        AS "Storage Location",
  UMZIZ        AS "Conversion Factor",
  SoldToBP,
  SoldToBPAddr,
  ShipToBP,
  ShipToBPAddr,
  PIC2BP,
  PIC2Addr,
  PIC2Country,
  SoldToBPName,
  ShipToBPName,
  PIC2BPName,
  VBELN_PO     AS "PO Document",
  POSNN_PO     AS "PO Document Item",
  ABDate,
  ReqDate
FROM
  Work5;
