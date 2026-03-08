create or replace task TEST_TASK_LOAD_REEL_LOG
	schedule='USING CRON 55 8 * * * Asia/Tokyo'
	as CALL IOT.IOT_RAW.SP_LOAD_TABLE(
      P_TARGET_TABLE     => 'IOT.IOT_RAW.TEST_REEL_LOG',
      P_LOAD_TYPE        => 'APPEND',
      P_STAGE_LOCATION   => '@IOT.IOT_RAW.MY_AZURE_STAGE/dataspider/IoT/Recv/REEL_LOG/',
      P_FILE_FORMAT_NAME => 'IOT.IOT_RAW.FF_CSV_COMMON',
      P_ON_ERROR         => 'SKIP_FILE'
  );