/* =============================================================================
  要件
    発注残マート作成（購買発注残テーブル）

  参照
    NEO-11691 購買発注残テーブルの作成方法について.xlsx

  説明
    ・Step1 → Step2 → Step3 → Step4 → Step5 → Step6 の順でCTEを接続
  来歴
  　2025/12/23 TenderLink Tanaka 新規作成
  　2025/12/23 HRS Miyashita Update
  　　・AB Refを追加
  　　・AB 行取得時、論理削除フラグを見るように変更
============================================================================= */
WITH
/* ---------------------------------------------------------------------------
  Step1 : Work1（EKET：発注残 > 0 のスケジュール行抽出）
  ・購買発注残>0のデータ抽出(未納入数＝計画数量 - 納入済数量 > 0)
--------------------------------------------------------------------------- */
Work1 AS (
  SELECT
    EKET.MANDT,
    EKET.EBELN,
    EKET.EBELP,
    EKET.EINDT AS ReqDate,
    EKET.MENGE,
    EKET.WEMNG,
    EKET.MENGE - EKET.WEMNG AS OpenQty,
    EKET.UNIQUEID
  FROM
    NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.EKET AS EKET
  WHERE
    EKET.MENGE - EKET.WEMNG > 0
),

/* ---------------------------------------------------------------------------
  Step2-1 : Work2_1（EKPO：削除明細除外）
  ・削除フラグを対象から外す(LOEKZ <> 'L'（L=削除）)
--------------------------------------------------------------------------- */
Work2_1 AS (
  SELECT
    EKPO.MANDT,
    EKPO.EBELN,
    EKPO.EBELP,
    EKPO.UNIQUEID,
    EKPO.MATNR,
    EKPO.TXZ01,
    EKPO.ZIE_RESPONSIBLE_CODE_P_PDI,
    EKPO.ZIE_CHNG_REASON_CODE_PDI,
    EKPO.EVERS,
    EKPO.BANFN,
    EKPO.EMLIF,
    EKPO.BNFPO,
    EKPO.NETPR,
    EKPO.PEINH,
    EKPO.BPRME,
    EKPO.BRTWR
  FROM
    NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.EKPO AS EKPO
  WHERE
    EKPO.LOEKZ <> 'L'  /* 削除フラグ（L=削除） */
),

/* ---------------------------------------------------------------------------
  Step2 : Work2（Work1 × Work2_1）
  ・削除明細を除外するため INNER JOIN
--------------------------------------------------------------------------- */
Work2 AS (
  SELECT
    Work1.MANDT,
    Work1.EBELN,
    Work1.EBELP,
    Work1.ReqDate,
    Work1.MENGE,
    Work1.WEMNG,
    Work1.OpenQty,
    Work1.UNIQUEID,
    Work2_1.MATNR,
    Work2_1.TXZ01,
    Work2_1.ZIE_RESPONSIBLE_CODE_P_PDI,
    Work2_1.ZIE_CHNG_REASON_CODE_PDI,
    Work2_1.EVERS,
    Work2_1.BANFN,
    Work2_1.EMLIF,
    Work2_1.BNFPO,
    Work2_1.NETPR,
    Work2_1.PEINH,
    Work2_1.BPRME,
    Work2_1.BRTWR
  FROM
    Work1
    INNER JOIN Work2_1
      ON Work1.MANDT = Work2_1.MANDT
     AND Work1.EBELN = Work2_1.EBELN
     AND Work1.EBELP = Work2_1.EBELP
),
/* ---------------------------------------------------------------------------
  Step3 : Work3（EKKO：購買伝票ヘッダデータから抽出）
--------------------------------------------------------------------------- */
Work3 AS (
  SELECT
    Work2.MANDT,
    Work2.EBELN,
    Work2.EBELP,
    Work2.UNIQUEID,
    Work2.MATNR,
    Work2.TXZ01,
    Work2.ZIE_RESPONSIBLE_CODE_P_PDI,
    Work2.ZIE_CHNG_REASON_CODE_PDI,
    Work2.EVERS,
    Work2.BANFN,
    Work2.EMLIF,
    Work2.BNFPO,
    Work2.NETPR,
    Work2.PEINH,
    Work2.BPRME,
    Work2.BRTWR,
    Work2.ReqDate,
    Work2.MENGE,
    Work2.WEMNG,
    Work2.OpenQty,
    EKKO.BUKRS,
    EKKO.BSART,
    EKKO.LIFNR,
    EKKO.ZTERM,
    EKKO.EKORG,
    EKKO.EKGRP,
    EKKO.WAERS,
    EKKO.BEDAT,
    EKKO.INCO1,
    EKKO.INCO2,
    EKKO.INCO2_L,
    EKKO.INCO3_L,
    EKKO.ZIE_COSTCTR_PDH,
    EKKO.ZIE_TUPF_PDH,
    EKKO.ZIE_PLMCD_PDH,
    EKKO.ZIE_PRCSCCD_PDH,
    EKKO.ZIE_MRPCTR_PDH,
    EKKO.ZIE_PMATNR_PDH,
    EKKO.ZIE_RSNCAT_PDH
  FROM
    Work2
    LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.EKKO
      ON Work2.MANDT = EKKO.MANDT
     AND Work2.EBELN = EKKO.EBELN
),
/* ---------------------------------------------------------------------------
  Step4 : Work4（VBFA：SO番号、Item番号を付与）
--------------------------------------------------------------------------- */
Work4 AS (
  SELECT
    Work3.MANDT,
    Work3.EBELN,
    Work3.EBELP,
    Work3.UNIQUEID,
    Work3.MATNR,
    Work3.TXZ01,
    Work3.ZIE_RESPONSIBLE_CODE_P_PDI,
    Work3.ZIE_CHNG_REASON_CODE_PDI,
    Work3.EVERS,
    Work3.BANFN,
    Work3.EMLIF,
    Work3.BNFPO,
    Work3.NETPR,
    Work3.PEINH,
    Work3.BPRME,
    Work3.BRTWR,
    Work3.ReqDate,
    Work3.MENGE,
    Work3.WEMNG,
    Work3.OpenQty,
    Work3.BUKRS,
    Work3.BSART,
    Work3.LIFNR,
    Work3.ZTERM,
    Work3.EKORG,
    Work3.EKGRP,
    Work3.WAERS,
    Work3.BEDAT,
    Work3.INCO1,
    Work3.INCO2,
    Work3.INCO2_L,
    Work3.INCO3_L,
    Work3.ZIE_COSTCTR_PDH,
    Work3.ZIE_TUPF_PDH,
    Work3.ZIE_PLMCD_PDH,
    Work3.ZIE_PRCSCCD_PDH,
    Work3.ZIE_MRPCTR_PDH,
    Work3.ZIE_PMATNR_PDH,
    Work3.ZIE_RSNCAT_PDH,
    VBFA.VBELV,
    VBFA.POSNV
  FROM
    Work3
    LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.VBFA AS VBFA
      ON Work3.MANDT = VBFA.MANDT
     AND Work3.EBELN = VBFA.VBELN
     AND Work3.EBELP = substr(VBFA.POSNN,2,5)
     AND VBFA.VBTYP_N = 'V' --'V'（購買発注)
     AND VBFA.VBTYP_V = 'C' --'C'（受注）
),

/* ---------------------------------------------------------------------------
  Step5 : Work5（EKES：AB行納入日付（回答納期）を付与）
--------------------------------------------------------------------------- */
Work5 AS (
  SELECT
    Work4.MANDT,
    Work4.EBELN,
    Work4.EBELP,
    Work4.UNIQUEID,
    Work4.MATNR,
    Work4.TXZ01,
    Work4.ZIE_RESPONSIBLE_CODE_P_PDI,
    Work4.ZIE_CHNG_REASON_CODE_PDI,
    Work4.EVERS,
    Work4.BANFN,
    Work4.EMLIF,
    Work4.BNFPO,
    Work4.NETPR,
    Work4.PEINH,
    Work4.BPRME,
    Work4.BRTWR,
    Work4.ReqDate,
    Work4.MENGE,
    Work4.WEMNG,
    Work4.OpenQty,
    Work4.BUKRS,
    Work4.BSART,
    Work4.LIFNR,
    Work4.ZTERM,
    Work4.EKORG,
    Work4.EKGRP,
    Work4.WAERS,
    Work4.BEDAT,
    Work4.INCO1,
    Work4.INCO2,
    Work4.INCO2_L,
    Work4.INCO3_L,
    Work4.ZIE_COSTCTR_PDH,
    Work4.ZIE_TUPF_PDH,
    Work4.ZIE_PLMCD_PDH,
    Work4.ZIE_PRCSCCD_PDH,
    Work4.ZIE_MRPCTR_PDH,
    Work4.ZIE_PMATNR_PDH,
    Work4.ZIE_RSNCAT_PDH,
    Work4.VBELV,
    Work4.POSNV,
    EKES.EINDT AS ABDate,
    EKES.XBLNR AS ABRef
  FROM
    Work4
    LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.EKES AS EKES
      ON Work4.MANDT = EKES.MANDT
     AND Work4.EBELN = EKES.EBELN
     AND Work4.EBELP = EKES.EBELP
     AND EKES._FIVETRAN_DELETED = 'FALSE'
     AND EKES.EBTYP = 'AB'
),

/* ---------------------------------------------------------------------------
  Step6 : Work6（LFA1：サプライヤ名付与）
--------------------------------------------------------------------------- */
Work6 AS (
  SELECT
    Work5.MANDT,
    Work5.EBELN,
    Work5.EBELP,
    Work5.UNIQUEID,
    Work5.MATNR,
    Work5.TXZ01,
    Work5.ZIE_RESPONSIBLE_CODE_P_PDI,
    Work5.ZIE_CHNG_REASON_CODE_PDI,
    Work5.EVERS,
    Work5.BANFN,
    Work5.EMLIF,
    Work5.BNFPO,
    Work5.NETPR,
    Work5.PEINH,
    Work5.BPRME,
    Work5.BRTWR,
    Work5.ReqDate,
    Work5.MENGE,
    Work5.WEMNG,
    Work5.OpenQty,
    Work5.BUKRS,
    Work5.BSART,
    Work5.LIFNR,
    Work5.ZTERM,
    Work5.EKORG,
    Work5.EKGRP,
    Work5.WAERS,
    Work5.BEDAT,
    Work5.INCO1,
    Work5.INCO2,
    Work5.INCO2_L,
    Work5.INCO3_L,
    Work5.ZIE_COSTCTR_PDH,
    Work5.ZIE_TUPF_PDH,
    Work5.ZIE_PLMCD_PDH,
    Work5.ZIE_PRCSCCD_PDH,
    Work5.ZIE_MRPCTR_PDH,
    Work5.ZIE_PMATNR_PDH,
    Work5.ZIE_RSNCAT_PDH,
    Work5.VBELV,
    Work5.POSNV,
    Work5.ABDate,
    Work5.ABRef,
    LFA1.NAME1
  FROM
    Work5
    LEFT OUTER JOIN NEO_HOPICS_REP.SAP_S4_HANA_DB_SAPHANADB.LFA1 AS LFA1
      ON Work5.MANDT = LFA1.MANDT
     AND Work5.LIFNR = LFA1.LIFNR
)

/* ---------------------------------------------------------------------------
  最終SELECT：TOBEレポートシートの列順
--------------------------------------------------------------------------- */
SELECT
  Work6.EBELN,
  Work6.EBELP,
  Work6.UNIQUEID,
  Work6.MATNR,
  Work6.TXZ01,
  Work6.ZIE_RESPONSIBLE_CODE_P_PDI,
  Work6.ZIE_CHNG_REASON_CODE_PDI,
  Work6.EVERS,
  Work6.BANFN,
  Work6.EMLIF,
  Work6.BNFPO,
  Work6.NETPR,
  Work6.PEINH,
  Work6.BPRME,
  Work6.BRTWR,
  Work6.ReqDate,
  Work6.MENGE,
  Work6.WEMNG,
  Work6.OpenQty,
  Work6.BUKRS,
  Work6.BSART,
  Work6.LIFNR,
  Work6.ZTERM,
  Work6.EKORG,
  Work6.EKGRP,
  Work6.WAERS,
  Work6.BEDAT,
  Work6.INCO1,
  Work6.INCO2,
  Work6.INCO2_L,
  Work6.INCO3_L,
  Work6.ZIE_COSTCTR_PDH,
  Work6.ZIE_TUPF_PDH,
  Work6.ZIE_PLMCD_PDH,
  Work6.ZIE_PRCSCCD_PDH,
  Work6.ZIE_MRPCTR_PDH,
  Work6.ZIE_PMATNR_PDH,
  Work6.ZIE_RSNCAT_PDH,
  Work6.VBELV,
  Work6.POSNV,
  Work6.ABDate,
  Work6.ABRef,
  Work6.NAME1
FROM
  Work6
;
