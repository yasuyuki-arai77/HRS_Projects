create or replace task TEST_TASK_LOAD_PROD_LOG_FH
	warehouse=WH_LOAD
	schedule='USING CRON 55 8 * * * Asia/Tokyo'
	as CALL IOT.IOT_RAW.SP_REFRESH_PROD_LOG_FH();
