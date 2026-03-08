create or replace task TASK_RUN_RECOVERY
	warehouse=WH_LOAD
	schedule='USING CRON 0 0 1 1 * Asia/Tokyo'
	as CALL IOT.IOT_RAW.SP_RUN_RECOVERY_QUEUE('IOT');