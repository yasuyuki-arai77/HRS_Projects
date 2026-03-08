CREATE OR REPLACE PROCEDURE IOT.IOT_RAW.SP_LOAD_PROD_LOG_FH_RAW()
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS OWNER
AS
' 
var sql = `
MERGE INTO IOT.IOT_RAW.PROD_LOG_FH_RAW T
USING (
  SELECT
    METADATA$FILENAME        AS SOURCE_FILE_PATH,
    METADATA$FILE_ROW_NUMBER AS SOURCE_ROW_NUMBER,
    OBJECT_CONSTRUCT_KEEP_NULL(
      ''時刻'', $1,
      ''Nコード'', $2,
      ''ラインNo.'', $3,
      ''0:生産開始/1:定時/2：一時停止/3:生産終了/4:定時終了'', $4,
      ''T投入数[個]'', $5,
      ''T生産数[個]'', $6,
      ''T梱包数[個]'', $7,
      ''現在計画数[個]'', $8,
      ''進捗率[%]'', $9,
      ''T計画数[個]'', $10,
      ''計画ﾏｼﾝﾀｸﾄ[10ms]'', $11,
      ''平均ﾀｸﾄ[10ms]'', $12,
      ''T不良数[個]'', $13,
      ''T不良率ppm'', $14,
      ''T不良_01'', $15,
      ''T不良_02'', $16,
      ''T不良_03'', $17,
      ''T不良_04'', $18,
      ''T不良_05'', $19,
      ''T不良_06'', $20,
      ''T不良_07'', $21,
      ''T不良_08'', $22,
      ''T不良_09'', $23,
      ''T不良_10'', $24,
      ''T不良_11'', $25,
      ''T不良_12'', $26,
      ''T不良_13'', $27,
      ''T不良_14'', $28,
      ''T不良_15'', $29,
      ''T不良_16'', $30,
      ''T不良_17'', $31,
      ''T不良_18'', $32,
      ''T不良_19'', $33,
      ''T不良_20'', $34,
      ''T不良_21'', $35,
      ''T不良_22'', $36,
      ''T不良_23'', $37,
      ''T不良_24'', $38,
      ''T不良_25'', $39,
      ''T不良_26'', $40,
      ''T不良_27'', $41,
      ''T不良_28'', $42,
      ''T不良_29'', $43,
      ''T不良_30'', $44,
      ''T不良_31'', $45,
      ''T不良_32'', $46,
      ''T不良_33'', $47,
      ''T不良_34'', $48,
      ''T不良_35'', $49,
      ''T不良_36'', $50,
      ''T不良_37'', $51,
      ''T不良_38'', $52,
      ''T不良_39'', $53,
      ''T不良_40'', $54,
      ''T不良_41'', $55,
      ''T不良_42'', $56,
      ''T不良_43'', $57,
      ''T不良_44'', $58,
      ''T不良_45'', $59,
      ''T不良_46'', $60
    ) AS RAW_OBJ,
    CURRENT_TIMESTAMP()      AS LOADED_AT
  FROM @IOT.IOT_RAW.MY_AZURE_STAGE/dataspider_dev/IoT/FH/Recv/
  (
    FILE_FORMAT => ''IOT.IOT_RAW.FF_CSV_PROD_LOG_FH'',
    PATTERN => ''.*Prod_log/.*\\\\.csv''
  )
) S
ON  T.SOURCE_FILE_PATH = S.SOURCE_FILE_PATH
AND T.SOURCE_ROW_NUMBER = S.SOURCE_ROW_NUMBER
WHEN NOT MATCHED THEN
  INSERT (SOURCE_FILE_PATH, SOURCE_ROW_NUMBER, RAW_OBJ, LOADED_AT)
  VALUES (S.SOURCE_FILE_PATH, S.SOURCE_ROW_NUMBER, S.RAW_OBJ, S.LOADED_AT)
`;

var stmt = snowflake.createStatement({ sqlText: sql });
stmt.execute();

return ''OK'';
';
