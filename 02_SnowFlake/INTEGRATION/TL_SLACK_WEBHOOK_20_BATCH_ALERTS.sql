/* -----------------------------------------------------------------------------
要件名:
  Slack通知（#20_batch_alerts）

概要:
  Slack Incoming Webhook にSnowflakeから通知するための通知統合を作成する。

メモ:
  - WEBHOOK_URL にWebhook URLを貼る（ここがコピペ欄）
  - WEBHOOK_BODY_TEMPLATE はメッセージをそのままHTTP bodyにする（JSONはSP側で作る）
----------------------------------------------------------------------------- */

CREATE OR REPLACE NOTIFICATION INTEGRATION TL_SLACK_WEBHOOK_20_BATCH_ALERTS
  TYPE = WEBHOOK
  ENABLED = TRUE
  /* 【コピペ欄】Slack Incoming Webhook URL */
  WEBHOOK_URL = 'https://hooks.slack.com/services/<REDACTED>/<REDACTED>/<REDACTED>'
  WEBHOOK_BODY_TEMPLATE = 'SNOWFLAKE_WEBHOOK_MESSAGE'
  WEBHOOK_HEADERS = ('Content-Type' = 'application/json')
  COMMENT = 'Batch task failure alerts to Slack #20_batch_alerts';


/* -----------------------------------------------------------------------------
目的:
  Slack通知（Webhook）の疎通確認（任意）
----------------------------------------------------------------------------- */

CALL SYSTEM$SEND_SNOWFLAKE_NOTIFICATION(
  SNOWFLAKE.NOTIFICATION.TEXT_PLAIN(
    SNOWFLAKE.NOTIFICATION.SANITIZE_WEBHOOK_CONTENT('{"text":"[TEST] Snowflake Slack webhook integration is OK."}')
  ),
  SNOWFLAKE.NOTIFICATION.INTEGRATION('TL_SLACK_WEBHOOK_20_BATCH_ALERTS')
);
