@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 > nul

rem =====================================================================
rem run_winscp.bat  （方式A：実行ごとのフォルダに退避）
rem 役割:
rem   WinSCPスクリプト（bin\common\sftp_run_winscp.txt）を共通手順で実行。
rem   common.ini → ジョブINIを後勝ちマージ、out/err ログ分離、RC正規化(0/12)。
rem   成功→bak\<JOB>\<TS>\ / 失敗→error\<JOB>\<TS>\ へ退避
rem
rem 引数: 
rem   1=ジョブINIのパス（必須）  2=JOBBASE（任意、省略時はINI名）
rem
rem ログ: 
rem   exec\log\%JOBBASE%\%JOBBASE%_{yyyyMMdd_HHmmss}_{out|err}.log
rem
rem 方針:
rem   WinSCP実体解決は WINSCP_EXE(存在) ＞ PATH。見つからなければ異常(12)。
rem =====================================================================

rem -------- 引数チェック / JOBBASE決定 ----------------------------------
if "%~1"=="" (
  echo [ERROR] iniファイルのパスを指定してください
  exit /b 12
)
set "INI=%~1"
set "JOBBASE=%~2"
if "%JOBBASE%"=="" for %%A in ("%INI%") do set "JOBBASE=%%~nA"

rem このbatは exec\bin\common にある想定 → ルートへ移動
set "BASE=%~dp0..\.."
pushd "%BASE%" || (echo [ERROR] BASEDIR解決失敗 & exit /b 12)

rem -------- common.ini → job.ini の順で読み込み（後勝ち） ---------------
rem   既知キー: SRC_DIR, FILE_PATTERN, DEST_HOST, DEST_PORT, DEST_USER, DEST_DIR,
rem             SSH_KEY, HOSTKEY, BACKUP_DIR,ERR_DIR, LOGDIR, WINSCP_EXE
set "COMMON_INI=bin\common\common.ini"
for %%F in ("%COMMON_INI%" "%INI%") do (
  if exist "%%~F" (
    for /f "usebackq tokens=1,* delims== eol=;" %%K in ("%%~F") do (
      set "K=%%K"
      set "V=%%L"
      if not "!K!"=="" (
        if not "!K:~0,1!"=="#" if not "!K:~0,1!"=="[" (
          rem 値の先頭空白を1回トリム（key = value の書式対策）
          for /f "tokens=* delims= " %%A in ("!V!") do set "V=%%A"
          if /i "!K!"=="SRC_DIR"       set "SRC_DIR=!V!"
          if /i "!K!"=="FILE_PATTERN"  set "FILE_PATTERN=!V!"
          if /i "!K!"=="DEST_HOST"     set "DEST_HOST=!V!"
          if /i "!K!"=="DEST_PORT"     set "DEST_PORT=!V!"
          if /i "!K!"=="DEST_USER"     set "DEST_USER=!V!"
          if /i "!K!"=="DEST_DIR"      set "DEST_DIR=!V!"
          if /i "!K!"=="SSH_KEY"       set "SSH_KEY=!V!"
          if /i "!K!"=="HOSTKEY"       set "HOSTKEY=!V!"
          if /i "!K!"=="BACKUP_DIR"    set "BACKUP_DIR=!V!"
          if /i "!K!"=="ERR_DIR"       set "ERR_DIR=!V!"
          if /i "!K!"=="LOGDIR"        set "LOGDIR=!V!"
          if /i "!K!"=="WINSCP_EXE"    set "WINSCP_EXE=!V!"
        )
      )
    )
  )
)

rem -------- 既定ポート補完（INI未指定時） -------------------------------
if not defined DEST_PORT set "DEST_PORT=22"

rem -------- ログ基盤：LOGDIR既定→絶対化→ジョブ別サブフォルダ ----------
if not defined LOGDIR set "LOGDIR=log"
for %%A in ("%LOGDIR%") do set "LOGDIR=%%~fA"
set "LOGBASE=%LOGDIR%\%JOBBASE%"
if not exist "%LOGBASE%" mkdir "%LOGBASE%" 2>nul

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TS=%%i"
set "OUTLOG=%LOGBASE%\%JOBBASE%_%TS%_out.log"
set "ERRLOG=%LOGBASE%\%JOBBASE%_%TS%_err.log"

rem -------- 必須キー検証（不足ならWinSCP起動前に終了） ------------------
set "MISSING="
for %%V in (SRC_DIR FILE_PATTERN DEST_HOST DEST_USER DEST_DIR ERR_DIR) do (
  if not defined %%V set "MISSING=1"
)
if defined MISSING (
  echo [ERROR] 必須項目未設定: SRC_DIR/FILE_PATTERN/DEST_HOST/DEST_USER/DEST_DIR/ERR_DIR を確認 >>"%ERRLOG%"
  popd & exit /b 12
)

rem ---- WinSCP 実体解決（ENV優先 → PATH → なければ異常） ----
set "WINSCP=winscp.com"

rem 1) 明示指定があれば最優先（存在チェック）
if defined WINSCP_EXE if exist "%WINSCP_EXE%" set "WINSCP=%WINSCP_EXE%"

rem 2) まだ既定値なら PATH から解決（where で実体を拾う）
if /i "%WINSCP%"=="winscp.com" (
  for /f "delims=" %%P in ('where winscp.com 2^>nul') do (
    set "WINSCP=%%P"
    goto :WINSCP_FOUND
  )
  echo [ERROR] WinSCP.com が見つかりません（WINSCP_EXE 未設定/不正、PATHにも無し）
  popd & exit /b 12
)
:WINSCP_FOUND
echo [INFO] Using WinSCP: "%WINSCP%"

rem -------- セッション引数生成（hostkey / privatekey は任意） -----------
set "SESSION=sftp://%DEST_USER%@%DEST_HOST%:%DEST_PORT%/"
if defined HOSTKEY set SESSION=%SESSION% -hostkey=""%HOSTKEY%""
if defined SSH_KEY  set SESSION=%SESSION% -privatekey=%SSH_KEY%

rem -------- スクリプト所在チェック --------------------------------------
set "SCRIPT=bin\common\sftp_run_winscp.txt"
if not exist "%SCRIPT%" (
  echo [ERROR] WinSCP script not found: %SCRIPT% >>"%ERRLOG%"
  popd & exit /b 12
)

rem -------- 実行ヘッダ（追跡に必要な情報をOUTLOGへ） -------------------
echo [INFO] %JOBBASE% start %DATE% %TIME% >>"%OUTLOG%"
echo [INFO] SRC_DIR=%SRC_DIR%, FILE_PATTERN=%FILE_PATTERN% >>"%OUTLOG%"
echo [INFO] DEST=%DEST_USER%@%DEST_HOST%:%DEST_PORT%%DEST_DIR% >>"%OUTLOG%"
echo [INFO] WINSCP=%WINSCP% >>"%OUTLOG%"

rem -------- WinSCP 実行（標準出力→OUTLOG、標準エラー→ERRLOG） ---------
"%WINSCP%" /ini=nul ^
  /script="%SCRIPT%" ^
  /parameter "%SESSION%" "%SRC_DIR%" "%DEST_DIR%" "%FILE_PATTERN%" ^
  1>>"%OUTLOG%" 2>>"%ERRLOG%"
set "RC=%ERRORLEVEL%"

rem ---- 成功：bak\<TS>\ へ退避 ------------------------------------
if "%RC%"=="0" (
  echo [INFO] WinSCP success ^(RC=0^)>>"%OUTLOG%"
  echo BACKUP_DIR %BACKUP_DIR%



  if defined BACKUP_DIR (
    echo [debug] BACKUP_DIR %BACKUP_DIR% 
    echo [debug] TS %TS%
    echo [debug] %BACKUP_DIR%\%TS%
    set RUN_BAK=%BACKUP_DIR%\%TS%
    echo RUN_BAK !RUN_BAK!
    if not exist "!RUN_BAK!" mkdir "!RUN_BAK!" 2>>"%ERRLOG%"
    set "MOVE_ERR="
    for /f "delims=" %%F in ('dir /b /a:-d "%SRC_DIR%\%FILE_PATTERN%" 2^>nul') do (
      echo move "%SRC_DIR%\%%F" "!RUN_BAK!\"
      move /Y "%SRC_DIR%\%%F" "!RUN_BAK!\" 1>>"%OUTLOG%" 2>>"%ERRLOG%" || set "MOVE_ERR=1"
    )
    if defined MOVE_ERR (
      echo [ERROR] 退避^(move^)に失敗しました >>"%ERRLOG%"
      echo [END] RC=12 >>"%OUTLOG%"
      popd & exit /b 12
    )
  )
  echo [END] RC=0>>"%OUTLOG%"

  popd & exit /b 0
)

rem ---- 失敗：error\<TS>\ へ回収 ------------------------------------
echo [ERROR] WinSCP異常終了 RC=%RC% >>"%ERRLOG%"

set "RUN_ERR=%ERR_DIR%\%TS%"
if not exist "%RUN_ERR%" mkdir "%RUN_ERR%" 2>>"%ERRLOG%"
set "ERR_MOVE="
for /f "delims=" %%F in ('dir /b /a:-d "%SRC_DIR%\%FILE_PATTERN%" 2^>nul') do (
  move /Y "%SRC_DIR%\%%F" "%RUN_ERR%\" 1>>"%OUTLOG%" 2>>"%ERRLOG%" || set "ERR_MOVE=1"
)
if defined ERR_MOVE (
  echo [ERROR] 失敗ファイルの回収^(move^)に失敗しました >>"%ERRLOG%"
)
echo [END] RC=12>>"%OUTLOG%"

popd & exit /b 12

rem -------- 返却コードマッピング（0以外は異常=12で返却） ---------------
if not "%RC%"=="0" (
  popd & exit /b 12
)
popd & exit /b 0
