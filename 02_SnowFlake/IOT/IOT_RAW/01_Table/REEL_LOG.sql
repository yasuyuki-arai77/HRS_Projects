-- DDL for IOT.IOT_RAW.REEL_LOG
-- Note: Column names are quoted to preserve Japanese identifiers exactly as in the source CSV.
-- Adjust DATABASE/SCHEMA as needed.
CREATE OR REPLACE TABLE IOT.IOT_RAW.REEL_LOG (
  "時刻" TIMESTAMP_NTZ,
  "Nコード" STRING,
  "ロットトレースNo." STRING,
  "製造指示書No." STRING,
  "ラインNo." STRING,
  "製品名" STRING,
  "計画ﾏｼﾝﾀｸﾄ" NUMBER,
  "梱包開始時間" TIME,
  "梱包終了時間" TIME,
  "R計画数" NUMBER,
  "R投入数" NUMBER,
  "R生産数" NUMBER,
  "R梱包数" NUMBER,
  "R不良数" NUMBER,
  "短絡R不良数" NUMBER,
  "短絡1R不良数" NUMBER,
  "短絡2R不良数" NUMBER,
  "導通R不良数" NUMBER,
  "機器R不良数" NUMBER,
  "平坦度1R不良数" NUMBER,
  "ﾋﾟｯﾁ1R不良数" NUMBER,
  "平坦度2R不良数" NUMBER,
  "ﾋﾟｯﾁ2R不良数" NUMBER,
  "予備R不良数" NUMBER
);
