CREATE OR REPLACE TABLE IOT.IOT_RAW.PROD_LOG_FH_RAW (
  SOURCE_FILE_PATH                                        STRING,
  SOURCE_ROW_NUMBER                                       NUMBER(38,0),
  RAW_OBJ                                                 VARIANT,
  LOADED_AT                                               TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
