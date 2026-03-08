CREATE OR REPLACE PROCEDURE IOT.IOT_RAW.SP_LOAD_TABLE("P_TARGET_TABLE" VARCHAR, "P_LOAD_TYPE" VARCHAR, "P_STAGE_LOCATION" VARCHAR, "P_FILE_FORMAT_NAME" VARCHAR, "P_FILE_PATTERN" VARCHAR DEFAULT null, "P_ON_ERROR" VARCHAR DEFAULT 'ABORT_STATEMENT')
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS '
DECLARE
    /* 変数仕様（一覧）
       V_NL                    : 改行コード（Slack整形用）
       V_LOAD_TYPE             : ロード種別（大文字正規化）
       V_TASK_NAME             : 実行中TASK名（通知用、取得できない場合はNULL）
       V_SQL                   : 実行SQL（COPY / INSERT OVERWRITE）

       V_INTEGRATION           : Slack通知統合名（固定: TL_SLACK_WEBHOOK_20_BATCH_ALERTS）
       V_MESSAGE               : Slack送信本文（複数行）
       V_JSON_BODY             : Slack送信JSON（{"text":"..."})

       V_COPY_QUERY_ID         : COPY INTO のクエリID（RESULT_SCAN用）
       V_DESC_QUERY_ID         : DESC RESULT のクエリID（RESULT_SCAN用）
       V_HAS_ERRORS_SEEN       : COPY結果に errors_seen 列があるか
       V_HAS_STATUS            : COPY結果に status 列があるか
       V_COPY_STATUS           : COPY結果の status 値
       V_ERROR_FILE_COUNT      : errors_seen>0 のファイル数
       V_ERROR_ROW_COUNT       : errors_seen 合計（参考）
       V_ERROR_SAMPLE          : エラー要約（file + line/char + first_error）
       V_ERROR_MORE            : 6件目以降の件数

       V_DB/V_SCHEMA/V_TABLE   : 対象テーブル分解（FULL_REFRESH用）
       V_INFO_COLUMNS          : "<DB>.INFORMATION_SCHEMA.COLUMNS"（IDENTIFIER用）
       V_COL_LIST              : INSERT対象列（"COL1","COL2",...）
       V_SEL_LIST              : ステージSELECT列（$1,$2,...）
    */

    V_NL                    STRING;

    V_LOAD_TYPE             STRING;
    V_TASK_NAME             STRING;
    V_SQL                   STRING;

    V_INTEGRATION           STRING;
    V_MESSAGE               STRING;
    V_JSON_BODY             STRING;

    V_COPY_QUERY_ID         STRING;
    V_DESC_QUERY_ID         STRING;
    V_HAS_ERRORS_SEEN       NUMBER;
    V_HAS_STATUS            NUMBER;
    V_COPY_STATUS           STRING;

    V_ERROR_FILE_COUNT      NUMBER;
    V_ERROR_ROW_COUNT       NUMBER;
    V_ERROR_SAMPLE          STRING;
    V_ERROR_MORE            NUMBER;

    V_DB                    STRING;
    V_SCHEMA                STRING;
    V_TABLE                 STRING;

    V_INFO_COLUMNS          STRING;

    V_COL_LIST              STRING;
    V_SEL_LIST              STRING;

    E_INVALID_LOAD_TYPE       EXCEPTION (-20001, ''Invalid load type. Use APPEND or FULL_REFRESH.'');
    E_INVALID_TARGET          EXCEPTION (-20002, ''Target table must be <DB>.<SCHEMA>.<TABLE>.'');
    E_TABLE_NOT_FOUND         EXCEPTION (-20003, ''Target table not found in INFORMATION_SCHEMA.COLUMNS.'');
    E_UNEXPECTED_COPY_RESULT  EXCEPTION (-20004, ''Unexpected COPY INTO result shape.'');
BEGIN
    /* STEP 0: 初期化 */
    V_NL               := CHAR(10);

    V_LOAD_TYPE        := UPPER(P_LOAD_TYPE);
    V_TASK_NAME        := SYSTEM$CURRENT_USER_TASK_NAME();

    V_INTEGRATION      := ''TL_SLACK_WEBHOOK_20_BATCH_ALERTS'';

    V_COPY_QUERY_ID    := NULL;
    V_DESC_QUERY_ID    := NULL;
    V_HAS_ERRORS_SEEN  := 0;
    V_HAS_STATUS       := 0;
    V_COPY_STATUS      := NULL;

    V_ERROR_FILE_COUNT := 0;
    V_ERROR_ROW_COUNT  := 0;
    V_ERROR_SAMPLE     := NULL;
    V_ERROR_MORE       := 0;

    V_INFO_COLUMNS     := NULL;

    /* STEP 1: APPEND（COPY INTO） */
    IF (V_LOAD_TYPE = ''APPEND'') THEN
        V_SQL :=
              ''COPY INTO '' || P_TARGET_TABLE
          || '' FROM '' || P_STAGE_LOCATION
          || '' FILE_FORMAT = (FORMAT_NAME = '''''' || P_FILE_FORMAT_NAME || '''''')''
          || '' ON_ERROR = '''''' || P_ON_ERROR || '''''''';

        IF (P_FILE_PATTERN IS NOT NULL) THEN
            V_SQL := V_SQL || '' PATTERN = '''''' || P_FILE_PATTERN || '''''''';
        END IF;

        EXECUTE IMMEDIATE V_SQL;

        V_COPY_QUERY_ID := LAST_QUERY_ID();

        /* COPY結果の列構成確認。
           0 files processed の場合は status のみになるケースがあるため、先に DESC RESULT で判定する。 */
        EXECUTE IMMEDIATE ''DESC RESULT '''''' || V_COPY_QUERY_ID || '''''''';
        V_DESC_QUERY_ID := LAST_QUERY_ID();

        SELECT
            COALESCE(SUM(IFF(LOWER("name") = ''errors_seen'', 1, 0)), 0),
            COALESCE(SUM(IFF(LOWER("name") = ''status'', 1, 0)), 0)
        INTO
            :V_HAS_ERRORS_SEEN,
            :V_HAS_STATUS
        FROM TABLE(RESULT_SCAN(:V_DESC_QUERY_ID));

        IF (V_HAS_ERRORS_SEEN = 0) THEN
            IF (V_HAS_STATUS > 0) THEN
                BEGIN
                    SELECT
                        MIN("status")
                    INTO
                        :V_COPY_STATUS
                    FROM TABLE(RESULT_SCAN(:V_COPY_QUERY_ID));
                EXCEPTION
                    WHEN OTHER THEN
                        SELECT
                            MIN(STATUS)
                        INTO
                            :V_COPY_STATUS
                        FROM TABLE(RESULT_SCAN(:V_COPY_QUERY_ID));
                END;

                IF (POSITION(''0 files processed'' IN COALESCE(V_COPY_STATUS, '''')) > 0) THEN
                    RETURN ''OK'';
                END IF;
            END IF;

            RAISE E_UNEXPECTED_COPY_RESULT;
        END IF;

        /* COPY結果集計（errors_seen が存在する通常ケース） */
        BEGIN
            SELECT
                COALESCE(SUM(IFF("errors_seen" > 0, 1, 0)), 0),
                COALESCE(SUM("errors_seen"), 0)
            INTO
                :V_ERROR_FILE_COUNT,
                :V_ERROR_ROW_COUNT
            FROM TABLE(RESULT_SCAN(:V_COPY_QUERY_ID));
        EXCEPTION
            WHEN OTHER THEN
                SELECT
                    COALESCE(SUM(IFF(ERRORS_SEEN > 0, 1, 0)), 0),
                    COALESCE(SUM(ERRORS_SEEN), 0)
                INTO
                    :V_ERROR_FILE_COUNT,
                    :V_ERROR_ROW_COUNT
                FROM TABLE(RESULT_SCAN(:V_COPY_QUERY_ID));
        END;

        /* 壊れファイルがあれば Slack警告（ただしタスクは成功扱いで返す） */
        IF (V_ERROR_FILE_COUNT > 0) THEN
            BEGIN
                SELECT
                    LISTAGG(
                        REGEXP_REPLACE("file", ''^.*/'', '''')
                        || '' (line='' || COALESCE(TO_VARCHAR("first_error_line"), ''NULL'')
                        || '', char='' || COALESCE(TO_VARCHAR("first_error_character"), ''NULL'') || '')''
                        || '' : ''
                        || LEFT("first_error", 180),
                        :V_NL
                    ) WITHIN GROUP (ORDER BY "file")
                INTO
                    :V_ERROR_SAMPLE
                FROM (
                    SELECT
                        "file",
                        "first_error",
                        "first_error_line",
                        "first_error_character"
                    FROM TABLE(RESULT_SCAN(:V_COPY_QUERY_ID))
                    WHERE "errors_seen" > 0
                    ORDER BY "file"
                );
            EXCEPTION
                WHEN OTHER THEN
                    SELECT
                        LISTAGG(
                            REGEXP_REPLACE(FILE, ''^.*/'', '''')
                            || '' (line='' || COALESCE(TO_VARCHAR(FIRST_ERROR_LINE), ''NULL'')
                            || '', char='' || COALESCE(TO_VARCHAR(FIRST_ERROR_CHARACTER), ''NULL'') || '')''
                            || '' : ''
                            || LEFT(FIRST_ERROR, 180),
                            :V_NL
                        ) WITHIN GROUP (ORDER BY FILE)
                    INTO
                        :V_ERROR_SAMPLE
                    FROM (
                        SELECT
                            FILE,
                            FIRST_ERROR,
                            FIRST_ERROR_LINE,
                            FIRST_ERROR_CHARACTER
                        FROM TABLE(RESULT_SCAN(:V_COPY_QUERY_ID))
                        WHERE ERRORS_SEEN > 0
                        ORDER BY FILE
                    );
            END;

            V_ERROR_MORE := GREATEST(V_ERROR_FILE_COUNT - 5, 0);

            IF (V_ERROR_MORE > 0) THEN
                V_ERROR_SAMPLE :=
                    COALESCE(V_ERROR_SAMPLE, '''')
                    || V_NL
                    || ''(+ '' || TO_VARCHAR(V_ERROR_MORE) || '' more files...)'';
            END IF;

            IF (V_ERROR_SAMPLE IS NOT NULL) THEN
                V_ERROR_SAMPLE := LEFT(V_ERROR_SAMPLE, 2500);
            END IF;

            V_MESSAGE :=
                  ''```'' || V_NL
              || ''[TASK_WARNING]'' || V_NL
              || ''RESULT=SUCCESS_WITH_SKIPPED_FILES'' || V_NL
              || ''TASK='' || COALESCE(V_TASK_NAME, ''UNKNOWN'') || V_NL
              || ''TARGET='' || COALESCE(P_TARGET_TABLE, ''NULL'') || V_NL
              || ''STAGE='' || COALESCE(P_STAGE_LOCATION, ''NULL'') || V_NL
              || ''FILE_FORMAT='' || COALESCE(P_FILE_FORMAT_NAME, ''NULL'') || V_NL
              || ''PATTERN='' || COALESCE(P_FILE_PATTERN, ''NULL'') || V_NL
              || ''ON_ERROR='' || COALESCE(P_ON_ERROR, ''NULL'') || V_NL
              || ''COPY_QUERY_ID='' || COALESCE(V_COPY_QUERY_ID, ''NULL'') || V_NL
              || ''COPY_STATUS='' || COALESCE(V_COPY_STATUS, ''NULL'') || V_NL
              || ''ERROR_FILE_COUNT='' || TO_VARCHAR(V_ERROR_FILE_COUNT) || V_NL
              || ''ERROR_ROW_COUNT='' || TO_VARCHAR(V_ERROR_ROW_COUNT) || V_NL
              || ''ERROR_SAMPLE='' || V_NL || COALESCE(V_ERROR_SAMPLE, ''(none)'') || V_NL
              || ''```'';

            V_JSON_BODY := OBJECT_CONSTRUCT(''text'', V_MESSAGE)::STRING;

            CALL SYSTEM$SEND_SNOWFLAKE_NOTIFICATION(
                SNOWFLAKE.NOTIFICATION.TEXT_PLAIN(
                    SNOWFLAKE.NOTIFICATION.SANITIZE_WEBHOOK_CONTENT(:V_JSON_BODY)
                ),
                SNOWFLAKE.NOTIFICATION.INTEGRATION(:V_INTEGRATION)
            );

            RETURN ''WARN'';
        END IF;

        RETURN ''OK'';
    END IF;

    /* STEP 2: FULL_REFRESH（INSERT OVERWRITE） */
    IF (V_LOAD_TYPE = ''FULL_REFRESH'') THEN
        V_DB     := SPLIT_PART(P_TARGET_TABLE, ''.'', 1);
        V_SCHEMA := SPLIT_PART(P_TARGET_TABLE, ''.'', 2);
        V_TABLE  := SPLIT_PART(P_TARGET_TABLE, ''.'', 3);

        IF (V_DB IS NULL OR V_SCHEMA IS NULL OR V_TABLE IS NULL) THEN
            RAISE E_INVALID_TARGET;
        END IF;

        V_INFO_COLUMNS := V_DB || ''.INFORMATION_SCHEMA.COLUMNS'';

        SELECT
            LISTAGG(''"'' || REPLACE(COLUMN_NAME, ''"'', ''""'') || ''"'', '', '')
                WITHIN GROUP (ORDER BY ORDINAL_POSITION),
            LISTAGG(''$'' || ORDINAL_POSITION, '', '')
                WITHIN GROUP (ORDER BY ORDINAL_POSITION)
        INTO
            :V_COL_LIST,
            :V_SEL_LIST
        FROM IDENTIFIER(:V_INFO_COLUMNS)
        WHERE TABLE_SCHEMA = :V_SCHEMA
          AND TABLE_NAME   = :V_TABLE;

        IF (V_COL_LIST IS NULL) THEN
            RAISE E_TABLE_NOT_FOUND;
        END IF;

        V_SQL :=
              ''INSERT OVERWRITE INTO '' || P_TARGET_TABLE || '' ('' || V_COL_LIST || '')''
          || '' SELECT '' || V_SEL_LIST
          || '' FROM '' || P_STAGE_LOCATION
          || '' (FILE_FORMAT => '''''' || P_FILE_FORMAT_NAME || '''''''';

        IF (P_FILE_PATTERN IS NOT NULL) THEN
            V_SQL := V_SQL || '', PATTERN => '''''' || P_FILE_PATTERN || '''''''';
        END IF;

        V_SQL := V_SQL || '')'';

        EXECUTE IMMEDIATE V_SQL;

        RETURN ''OK'';
    END IF;

    /* STEP 3: LOAD_TYPE不正 */
    RAISE E_INVALID_LOAD_TYPE;

EXCEPTION
    WHEN OTHER THEN
        /* STEP 4: 例外時（タスク失敗） */
        V_MESSAGE :=
              ''```'' || V_NL
          || ''[TASK_FAILED]'' || V_NL
          || ''TASK='' || COALESCE(V_TASK_NAME, ''UNKNOWN'') || V_NL
          || ''LOAD_TYPE='' || COALESCE(P_LOAD_TYPE, ''NULL'') || V_NL
          || ''TARGET='' || COALESCE(P_TARGET_TABLE, ''NULL'') || V_NL
          || ''STAGE='' || COALESCE(P_STAGE_LOCATION, ''NULL'') || V_NL
          || ''FILE_FORMAT='' || COALESCE(P_FILE_FORMAT_NAME, ''NULL'') || V_NL
          || ''PATTERN='' || COALESCE(P_FILE_PATTERN, ''NULL'') || V_NL
          || ''ON_ERROR='' || COALESCE(P_ON_ERROR, ''NULL'') || V_NL
          || ''COPY_QUERY_ID='' || COALESCE(V_COPY_QUERY_ID, ''NULL'') || V_NL
          || ''COPY_STATUS='' || COALESCE(V_COPY_STATUS, ''NULL'') || V_NL
          || ''SQLCODE='' || SQLCODE || V_NL
          || ''SQLSTATE='' || SQLSTATE || V_NL
          || ''SQLERRM='' || SQLERRM || V_NL
          || ''```'';

        V_JSON_BODY := OBJECT_CONSTRUCT(''text'', V_MESSAGE)::STRING;

        BEGIN
            CALL SYSTEM$SEND_SNOWFLAKE_NOTIFICATION(
                SNOWFLAKE.NOTIFICATION.TEXT_PLAIN(
                    SNOWFLAKE.NOTIFICATION.SANITIZE_WEBHOOK_CONTENT(:V_JSON_BODY)
                ),
                SNOWFLAKE.NOTIFICATION.INTEGRATION(:V_INTEGRATION)
            );
        EXCEPTION
            WHEN OTHER THEN
                NULL;
        END;

        RAISE;
END;
';