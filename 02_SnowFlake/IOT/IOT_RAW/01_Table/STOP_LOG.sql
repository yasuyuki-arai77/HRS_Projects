CREATE OR REPLACE TABLE IOT.IOT_RAW.STOP_LOG (
  "時刻" TIMESTAMP_NTZ,
  "Nコード" STRING,
  "ラインNo." STRING,
  "0:開始待/1:開始/2:停止/3:再開/4:終了" NUMBER(1,0),
  "要因No." NUMBER(3,0)
);
