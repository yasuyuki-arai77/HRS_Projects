CREATE OR REPLACE PROCEDURE IOT.IOT_RAW.SP_RUN_RECOVERY_QUEUE("SYSTEM_NAME" VARCHAR)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS OWNER
AS '
function exec(sql, binds){ return snowflake.createStatement({sqlText: sql, binds: binds||[]}).execute(); }

var systemName = SYSTEM_NAME;
var qrs = exec(`
  SELECT QUEUE_ID,SYSTEM,DATASET,PATTERN,FORCE
    FROM IOT.IOT_RAW.OPS_RECOVERY_QUEUE
   WHERE SYSTEM = :1 AND STATUS = ''PENDING''
   ORDER BY ENQ_AT
`, [systemName]);

function updateQueue(qid, status, note) {
  exec(`UPDATE IOT.IOT_RAW.OPS_RECOVERY_QUEUE SET STATUS=:1, NOTE=:2 WHERE QUEUE_ID=:3`, [status, note, qid]);
}

function insertRun(system,dataset,tgt,filePath,fileName,status,errors,firstMsg,errFlag,rawObj){
  exec(`
    INSERT INTO IOT.IOT_RAW.OPS_RUN_LOG
      (RUN_AT,SYSTEM,DATASET,TARGET_TABLE,FILE_PATH,FILE_NAME,STATUS,ERRORS_SEEN,FIRST_ERROR_MESSAGE,ERROR_FLAG,RAW)
    SELECT CURRENT_TIMESTAMP(), :1,:2,:3,:4,:5,:6,:7,:8,:9, PARSE_JSON(:10)
  `, [system,dataset,tgt,filePath,fileName,status,errors,firstMsg,errFlag,JSON.stringify(rawObj)]);
}

var done = 0;
while (qrs.next()) {
  var qid     = qrs.getColumnValue(''QUEUE_ID'');
  var system  = qrs.getColumnValue(''SYSTEM'');
  var dataset = qrs.getColumnValue(''DATASET'');
  var pattern = qrs.getColumnValue(''PATTERN'');
  var force   = qrs.getColumnValue(''FORCE'');

  var crs = exec(`
    SELECT STAGE,SUBPATH,TARGET_TABLE,
           COALESCE(FILE_FORMAT,''IOT.IOT_RAW.FF_CSV_COMMON'') AS FILE_FORMAT,
           COALESCE(ON_ERROR,''SKIP_FILE'') AS ON_ERROR
      FROM IOT.IOT_RAW.OPS_DATASET_CONFIG
     WHERE SYSTEM=:1 AND DATASET=:2 AND IS_ACTIVE=TRUE
  `, [system,dataset]);
  if (!crs.next()) { updateQueue(qid,''ERROR'',''CONFIG NOT FOUND''); continue; }

  var stage = crs.getColumnValue(''STAGE'');
  var sub   = crs.getColumnValue(''SUBPATH'') || '''';
  var tgt   = crs.getColumnValue(''TARGET_TABLE'');
  var fmt   = crs.getColumnValue(''FILE_FORMAT'');
  var onerr = crs.getColumnValue(''ON_ERROR'');

  var at   = stage.startsWith(''@'') ? stage : ''@'' + stage;
  var base = at + (sub.startsWith(''/'') ? sub : ''/'' + sub);
  var full = base + (pattern.startsWith(''/'') ? pattern : ''/'' + pattern);

  try {
    var rs2 = exec(`
      COPY INTO ${tgt}
        FROM ''${full}''
        FILE_FORMAT = (FORMAT_NAME = ${fmt})
        FORCE = ${force ? ''TRUE'' : ''FALSE''}
        ON_ERROR = ''${onerr}''
    `);

    var hadErr = false, note = ''OK'';
    while (rs2.next()) {
      var row = {}, n = rs2.getColumnCount();
      for (var j=1; j<=n; j++) row[rs2.getColumnName(j)] = rs2.getColumnValue(j);

      var filePath = row.file || row.FILE || full;
      var fileName = String(filePath).split(''/'').pop();
      var status   = row.status || row.STATUS || null;
      var errors   = row.errors_seen || row.ERRORS_SEEN || 0;
      var firstMsg = row.first_error_message || row.FIRST_ERROR_MESSAGE || null;
      var errFlag  = (String(status).toUpperCase() !== ''LOADED'') || (Number(errors) > 0);
      if (errFlag) { hadErr = true; note = firstMsg ? String(firstMsg) : ''LOAD_FAILED''; }

      insertRun(system,dataset,tgt,filePath,fileName,String(status),Number(errors),firstMsg?String(firstMsg):null,errFlag,row);
    }

    updateQueue(qid, hadErr ? ''ERROR'' : ''DONE'', note);
    done++;
  } catch (e) {
    updateQueue(qid, ''ERROR'', String(e));
  }
}
return ''RECOVERY DONE: '' + done;
';