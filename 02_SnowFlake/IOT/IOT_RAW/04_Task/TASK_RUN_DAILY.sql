create or replace task TASK_RUN_DAILY
	warehouse=WH_LOAD
	schedule='USING CRON 55 8 * * * Asia/Tokyo'
	USER_TASK_TIMEOUT_MS=86400000
	as CALL IOT.IOT_RAW.SP_RUN_ALL_DATASETS('IOT');