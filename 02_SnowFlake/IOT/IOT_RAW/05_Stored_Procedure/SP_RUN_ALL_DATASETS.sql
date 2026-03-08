CREATE OR REPLACE PROCEDURE IOT.IOT_RAW.SP_RUN_ALL_DATASETS("SYSTEM_NAME" VARCHAR)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS OWNER
AS '
var systemName = SYSTEM_NAME;

// 対象データセット
var sel = `
  SELECT SYSTEM, DATASET, STAGE, SUBPATH, TARGET_TABLE,
         COALESCE(FILE_FORMAT,''IOT.IOT_RAW.FF_CSV_COMMON'') AS FILE_FORMAT,
         COALESCE(ON_ERROR,''SKIP_FILE'')                    AS ON_ERROR
    FROM IOT.IOT_RAW.OPS_DATASET_CONFIG
   WHERE SYSTEM = :1 AND IS_ACTIVE = TRUE
   ORDER BY DATASET
`;
var stmt = snowflake.createStatement({ sqlText: sel, binds: [systemName] });
var rs   = stmt.execute();

var processed = 0;

while (rs.next()) {
  var system     = rs.getColumnValue(''SYSTEM'');
  var dataset    = rs.getColumnValue(''DATASET'');
  var stage      = rs.getColumnValue(''STAGE'');
  var subpath    = rs.getColumnValue(''SUBPATH'') || '''';
  var target     = rs.getColumnValue(''TARGET_TABLE'');
  var fileFormat = rs.getColumnValue(''FILE_FORMAT'');
  var onError    = rs.getColumnValue(''ON_ERROR'');

  if (!stage.startsWith(''@'')) stage = ''@'' + stage;
  if (subpath && !subpath.startsWith(''/'')) subpath = ''/'' + subpath;
  var basePath = stage + subpath;

  // ===== 1) 事前検証（RETURN_ERRORS）→ OPS_RUN_LOG =====
  try {
    var vsql = `
      COPY INTO ${target}
        FROM ${basePath}
        FILE_FORMAT = (FORMAT_NAME = ${fileFormat})
        VALIDATION_MODE = ''RETURN_ERRORS''
    `;
    var vstmt = snowflake.createStatement({ sqlText: vsql });
    var vrs   = vstmt.execute();

    while (vrs.next()) {
      var rawRow = {};
      var cc = vrs.getColumnCount();
      for (var i=1; i<=cc; i++) rawRow[vrs.getColumnName(i)] = vrs.getColumnValue(i);

      var fpath = String(rawRow[''FILE''] || (basePath + (rawRow[''FILE_NAME''] || '''')));
      var fname = String(rawRow[''FILE_NAME''] || (fpath ? fpath.split(''/'').pop() : '''') || '''');
      var ferr  = String(rawRow[''ERROR''] || rawRow[''FIRST_ERROR''] || '''');

      snowflake.createStatement({
        sqlText: `
          INSERT INTO IOT.IOT_RAW.OPS_RUN_LOG
          (RUN_AT, SYSTEM, DATASET, TARGET_TABLE, FILE_PATH, FILE_NAME,
           STATUS, ERRORS_SEEN, FIRST_ERROR_MESSAGE, ERROR_FLAG, RAW)
          SELECT CURRENT_TIMESTAMP(), :1, :2, :3, :4, :5,
                 ''VALIDATION_ERROR'', 1, :6, TRUE, PARSE_JSON(:7)
        `,
        binds: [ system, dataset, target, fpath, fname, ferr, JSON.stringify(rawRow) ]
      }).execute();
    }
  } catch (e) {
    snowflake.createStatement({
      sqlText: `
        INSERT INTO IOT.IOT_RAW.OPS_RUN_LOG
        (RUN_AT, SYSTEM, DATASET, TARGET_TABLE, FILE_PATH, FILE_NAME,
         STATUS, ERRORS_SEEN, FIRST_ERROR_MESSAGE, ERROR_FLAG, RAW)
        SELECT CURRENT_TIMESTAMP(), :1, :2, :3, NULL, NULL,
               ''VALIDATION_FAILED'', NULL, :4, TRUE, PARSE_JSON(:5)
      `,
      binds: [ system, dataset, target, String(e), JSON.stringify({exception:String(e)}) ]
    }).execute();
  }

  // ===== 2) 本番 COPY → OPS_RUN_LOG =====
  try {
    var csql = `
      COPY INTO ${target}
        FROM ${basePath}
        FILE_FORMAT = (FORMAT_NAME = ${fileFormat})
        ON_ERROR    = ''${onError}''
    `;
    var cstmt = snowflake.createStatement({ sqlText: csql });
    var crs   = cstmt.execute();

    while (crs.next()) {
      var row = {};
      var n = crs.getColumnCount();
      for (var j=1; j<=n; j++) row[crs.getColumnName(j)] = crs.getColumnValue(j);

      var fname2   = String(row[''FILE_NAME''] || row[''NAME''] || '''');
      var fpath2   = basePath + fname2;
      var status   = String(row[''STATUS''] || '''');
      var errSeen  = Number(row[''ERRORS_SEEN''] != null ? row[''ERRORS_SEEN''] : ((status && status !== ''LOADED'') ? 1 : 0));
      var firstErr = String(row[''FIRST_ERROR''] || '''');
      var errFlagNum = (errSeen > 0 || (status && status !== ''LOADED'')) ? 1 : 0;  // 0/1（←ここが重要）

      snowflake.createStatement({
        sqlText: `
          INSERT INTO IOT.IOT_RAW.OPS_RUN_LOG
          (RUN_AT, SYSTEM, DATASET, TARGET_TABLE, FILE_PATH, FILE_NAME,
           STATUS, ERRORS_SEEN, FIRST_ERROR_MESSAGE, ERROR_FLAG, RAW)
          SELECT CURRENT_TIMESTAMP(), :1, :2, :3, :4, :5,
                 :6, :7, :8, IFF(:9=1, TRUE, FALSE), PARSE_JSON(:10)
        `,
        binds: [
          system, dataset, target, fpath2, fname2,
          status, errSeen, firstErr, errFlagNum, JSON.stringify(row)
        ]
      }).execute();
    }
  } catch (e2) {
    snowflake.createStatement({
      sqlText: `
        INSERT INTO IOT.IOT_RAW.OPS_RUN_LOG
        (RUN_AT, SYSTEM, DATASET, TARGET_TABLE, FILE_PATH, FILE_NAME,
         STATUS, ERRORS_SEEN, FIRST_ERROR_MESSAGE, ERROR_FLAG, RAW)
        SELECT CURRENT_TIMESTAMP(), :1, :2, :3, NULL, NULL,
               ''LOAD_FAILED'', NULL, :4, TRUE, PARSE_JSON(:5)
      `,
      binds: [ system, dataset, target, String(e2), JSON.stringify({exception:String(e2)}) ]
    }).execute();
  }

  processed++;
}

return ''DONE: '' + processed + '' dataset(s)'';
';