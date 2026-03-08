CREATE OR REPLACE PROCEDURE IOT.IOT_RAW.SP_NORMALIZE_PROD_LOG_FH()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
' 
BEGIN
  MERGE INTO IOT.IOT_RAW.PROD_LOG_FH T
  USING (
    SELECT
      TO_VARCHAR(SHA2(SOURCE_FILE_PATH || ''|'' || TO_VARCHAR(SOURCE_ROW_NUMBER), 256)) AS EVENT_ID,
      SOURCE_FILE_PATH,
      SOURCE_ROW_NUMBER,
      TRY_TO_TIMESTAMP_NTZ(RAW_OBJ:"時刻"::STRING) AS "時刻",
      RAW_OBJ:"Nコード"::STRING AS "Nコード",
      RAW_OBJ:"ラインNo."::STRING AS "ラインNo.",
      TRY_TO_NUMBER(RAW_OBJ:"0:生産開始/1:定時/2：一時停止/3:生産終了/4:定時終了"::STRING) AS "0:生産開始/1:定時/2：一時停止/3:生産終了/4:定時終了",
      TRY_TO_NUMBER(RAW_OBJ:"T投入数[個]"::STRING) AS "T投入数[個]",
      TRY_TO_NUMBER(RAW_OBJ:"T生産数[個]"::STRING) AS "T生産数[個]",
      TRY_TO_NUMBER(RAW_OBJ:"T梱包数[個]"::STRING) AS "T梱包数[個]",
      TRY_TO_NUMBER(RAW_OBJ:"現在計画数[個]"::STRING) AS "現在計画数[個]",
      TRY_TO_NUMBER(RAW_OBJ:"進捗率[%]"::STRING) AS "進捗率[%]",
      TRY_TO_NUMBER(RAW_OBJ:"T計画数[個]"::STRING) AS "T計画数[個]",
      TRY_TO_NUMBER(RAW_OBJ:"計画ﾏｼﾝﾀｸﾄ[10ms]"::STRING) AS "計画ﾏｼﾝﾀｸﾄ[10ms]",
      TRY_TO_NUMBER(RAW_OBJ:"平均ﾀｸﾄ[10ms]"::STRING) AS "平均ﾀｸﾄ[10ms]",
      TRY_TO_NUMBER(RAW_OBJ:"T不良数[個]"::STRING) AS "T不良数[個]",
      TRY_TO_NUMBER(RAW_OBJ:"T不良率ppm"::STRING) AS "T不良率ppm"
    FROM IOT.IOT_RAW.PROD_LOG_FH_RAW
  ) S
  ON T.EVENT_ID = S.EVENT_ID
  WHEN MATCHED THEN UPDATE SET
    T.SOURCE_FILE_PATH = S.SOURCE_FILE_PATH,
    T.SOURCE_ROW_NUMBER = S.SOURCE_ROW_NUMBER,
    T."時刻" = S."時刻",
    T."Nコード" = S."Nコード",
    T."ラインNo." = S."ラインNo.",
    T."0:生産開始/1:定時/2：一時停止/3:生産終了/4:定時終了" = S."0:生産開始/1:定時/2：一時停止/3:生産終了/4:定時終了",
    T."T投入数[個]" = S."T投入数[個]",
    T."T生産数[個]" = S."T生産数[個]",
    T."T梱包数[個]" = S."T梱包数[個]",
    T."現在計画数[個]" = S."現在計画数[個]",
    T."進捗率[%]" = S."進捗率[%]",
    T."T計画数[個]" = S."T計画数[個]",
    T."計画ﾏｼﾝﾀｸﾄ[10ms]" = S."計画ﾏｼﾝﾀｸﾄ[10ms]",
    T."平均ﾀｸﾄ[10ms]" = S."平均ﾀｸﾄ[10ms]",
    T."T不良数[個]" = S."T不良数[個]",
    T."T不良率ppm" = S."T不良率ppm",
    T.UPDATED_AT = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT (
    EVENT_ID,
    SOURCE_FILE_PATH,
    SOURCE_ROW_NUMBER,
    "時刻",
    "Nコード",
    "ラインNo.",
    "0:生産開始/1:定時/2：一時停止/3:生産終了/4:定時終了",
    "T投入数[個]",
    "T生産数[個]",
    "T梱包数[個]",
    "現在計画数[個]",
    "進捗率[%]",
    "T計画数[個]",
    "計画ﾏｼﾝﾀｸﾄ[10ms]",
    "平均ﾀｸﾄ[10ms]",
    "T不良数[個]",
    "T不良率ppm",
    CREATED_AT,
    UPDATED_AT
  ) VALUES (
    S.EVENT_ID,
    S.SOURCE_FILE_PATH,
    S.SOURCE_ROW_NUMBER,
    S."時刻",
    S."Nコード",
    S."ラインNo.",
    S."0:生産開始/1:定時/2：一時停止/3:生産終了/4:定時終了",
    S."T投入数[個]",
    S."T生産数[個]",
    S."T梱包数[個]",
    S."現在計画数[個]",
    S."進捗率[%]",
    S."T計画数[個]",
    S."計画ﾏｼﾝﾀｸﾄ[10ms]",
    S."平均ﾀｸﾄ[10ms]",
    S."T不良数[個]",
    S."T不良率ppm",
    CURRENT_TIMESTAMP(),
    CURRENT_TIMESTAMP()
  );

  MERGE INTO IOT.IOT_RAW.PROD_LOG_FH_DEFECT T
  USING (
    SELECT
      TO_VARCHAR(SHA2(R.SOURCE_FILE_PATH || ''|'' || TO_VARCHAR(R.SOURCE_ROW_NUMBER), 256)) AS EVENT_ID,
      R.SOURCE_FILE_PATH,
      R.SOURCE_ROW_NUMBER,
      F.KEY::STRING AS DEFECT_NAME,
      TRY_TO_NUMBER(F.VALUE::STRING) AS DEFECT_VALUE,
      F.VALUE::STRING AS DEFECT_VALUE_RAW
    FROM IOT.IOT_RAW.PROD_LOG_FH_RAW R,
         LATERAL FLATTEN(
           INPUT => OBJECT_DELETE(
             R.RAW_OBJ,
             ''時刻'',
             ''Nコード'',
             ''ラインNo.'',
             ''0:生産開始/1:定時/2：一時停止/3:生産終了/4:定時終了'',
             ''T投入数[個]'',
             ''T生産数[個]'',
             ''T梱包数[個]'',
             ''現在計画数[個]'',
             ''進捗率[%]'',
             ''T計画数[個]'',
             ''計画ﾏｼﾝﾀｸﾄ[10ms]'',
             ''平均ﾀｸﾄ[10ms]'',
             ''T不良数[個]'',
             ''T不良率ppm''
           )
         ) F
    WHERE TRY_TO_NUMBER(F.VALUE::STRING) IS NOT NULL
  ) S
  ON  T.EVENT_ID = S.EVENT_ID
  AND T.DEFECT_NAME = S.DEFECT_NAME
  WHEN MATCHED THEN UPDATE SET
    T.SOURCE_FILE_PATH = S.SOURCE_FILE_PATH,
    T.SOURCE_ROW_NUMBER = S.SOURCE_ROW_NUMBER,
    T.DEFECT_VALUE = S.DEFECT_VALUE,
    T.DEFECT_VALUE_RAW = S.DEFECT_VALUE_RAW,
    T.UPDATED_AT = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT (
    EVENT_ID,
    SOURCE_FILE_PATH,
    SOURCE_ROW_NUMBER,
    DEFECT_NAME,
    DEFECT_VALUE,
    DEFECT_VALUE_RAW,
    CREATED_AT,
    UPDATED_AT
  ) VALUES (
    S.EVENT_ID,
    S.SOURCE_FILE_PATH,
    S.SOURCE_ROW_NUMBER,
    S.DEFECT_NAME,
    S.DEFECT_VALUE,
    S.DEFECT_VALUE_RAW,
    CURRENT_TIMESTAMP(),
    CURRENT_TIMESTAMP()
  );

  RETURN ''OK'';
END;
';
