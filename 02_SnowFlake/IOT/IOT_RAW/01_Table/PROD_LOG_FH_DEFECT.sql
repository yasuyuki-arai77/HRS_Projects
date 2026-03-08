CREATE OR REPLACE TABLE IOT.IOT_RAW.PROD_LOG_FH_DEFECT (
  EVENT_ID                                                STRING,
  SOURCE_FILE_PATH                                        STRING,
  SOURCE_ROW_NUMBER                                       NUMBER(38,0),
  DEFECT_NAME                                             STRING,
  DEFECT_VALUE                                            NUMBER(18,0),
  DEFECT_VALUE_RAW                                        STRING,
  CREATED_AT                                              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  UPDATED_AT                                              TIMESTAMP_NTZ
);
