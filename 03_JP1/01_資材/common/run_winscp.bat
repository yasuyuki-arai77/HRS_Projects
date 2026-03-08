@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 > nul

rem ============================================================================
rem  run_winscp.bat（Azure 新仕様対応 / UTF-8 / CRLF）
rem ----------------------------------------------------------------------------
rem  目的:
rem    ・ローカル（%SRC_DIR%）→ Azure(SFTP) の %DEST_DIR% へファイルを配置する。
rem    ・Azure 側の「bak 退避」は行わない（運用廃止）。
rem    ・PUT は同名上書き前提。常にフル転送するため -resumesupport=off を明示。
rem    ・マスタ／例外トランは「配置前に Azure 側を削除」できる（INI で選択）。
rem
rem  エンコード/改行/ログ:
rem    ・本 BAT は UTF-8（BOMなし）/ CRLF。
rem    ・先頭で chcp 65001 を有効化し、out/err ログも UTF-8 で出力（文字化け防止）。
rem
rem  引数:
rem    1=ジョブ INI のパス（必須）
rem    2=JOBBASE（任意。省略時は INI のファイル名）
rem
rem  INI キー（common.ini → ジョブ INI の順で読込み、後勝ち上書き）:
rem    SRC_DIR, FILE_PATTERN, DEST_HOST, DEST_PORT, DEST_USER, DEST_DIR,
rem    SSH_KEY, HOSTKEY, BACKUP_DIR, ERR_DIR, LOGDIR, WINSCP_EXE,
rem    REMOTE_CLEAN, REMOTE_CLEAN_MASK
rem    - REMOTE_CLEAN       : OFF(既定)/ALL/PATTERN
rem         OFF     = 削除なし（積み上げ運用）。上書き PUT のみ。
rem         ALL     = %DEST_DIR% の全ファイルを削除後に PUT（マスタ等）。
rem         PATTERN = REMOTE_CLEAN_MASK に一致するもののみ削除 → PUT（例外トラン等）。
rem    - REMOTE_CLEAN_MASK  : PATTERN 時の削除対象（省略時は FILE_PATTERN を使用）。
rem
rem  フロー（概要）:
rem    0) 引数/基準ディレクトリの確認
rem    1) INI 読込（common → job 後勝ち）
rem    2) ログ初期化（exec\log\<JOBBASE>\*.log、UTF-8）
rem    3) 必須キー検証（不足なら WinSCP 未起動で RC=12）
rem    4) 送信 0 件スキップ（WinSCP 未起動で RC=0）
rem    5) WinSCP 実体解決（WINSCP_EXE＞PATH）
rem    6) セッション引数（sftp://user@host:port/ + -hostkey/-privatekey）生成
rem    7) 実行モード分岐：
rem       ・REMOTE_CLEAN=OFF        → 共通 sftp_run_winscp.txt で上書き PUT（削除なし）
rem       ・REMOTE_CLEAN=ALL/PATTERN→ rm（対象）→ put を 1 セッション実行
rem         ※本版は「一時ファイルを作らず」WinSCP /command で直接実行（追加ログは作成しない）
rem    8) 成功：BACKUP_DIR\<TS> へローカル退避／失敗：ERR_DIR\<TS> へ回収
rem
rem  ログ格納・返却コード:
rem    ・exec\log\<JOBBASE>\<JOBBASE>_yyyyMMdd_HHmmss_{out|err}.log
rem    ・正常=0 / 異常=12（WinSCP の RC を 0/非0 に正規化）
rem ============================================================================

rem -------- 0) 引数チェック / JOBBASE 決定 -------------------------------------
if "%~1"=="" (
  echo [ERROR] iniファイルのパスを指定してください
  exit /b 12
)
set "INI=%~1"
set "JOBBASE=%~2"
if "%JOBBASE%"=="" for %%A in ("%INI%") do set "JOBBASE=%%~nA"

rem この bat は exec\bin\common にある想定 → ルートへ移動
set "BASE=%~dp0..\.."
pushd "%BASE%" || (echo [ERROR] BASEDIR解決失敗 & exit /b 12)

rem -------- 1) INI 読込（common → job、後勝ち） -------------------------------
set "COMMON_INI=bin\common\common.ini"
for %%F in ("%COMMON_INI%" "%INI%") do (
  if exist "%%~F" (
    for /f "usebackq eol=; tokens=1,* delims==" %%K in ("%%~F") do (
      set "K=%%K"
      set "V=%%L"
      if not "!K!"=="" (
        if not "!K:~0,1!"=="#" if not "!K:~0,1!"=="[" (
          for /f "tokens=* delims= " %%A in ("!V!") do set "V=%%A"
          if /i "!K!"=="SRC_DIR"            set "SRC_DIR=!V!"
          if /i "!K!"=="FILE_PATTERN"       set "FILE_PATTERN=!V!"
          if /i "!K!"=="DEST_HOST"          set "DEST_HOST=!V!"
          if /i "!K!"=="DEST_PORT"          set "DEST_PORT=!V!"
          if /i "!K!"=="DEST_USER"          set "DEST_USER=!V!"
          if /i "!K!"=="DEST_DIR"           set "DEST_DIR=!V!"
          if /i "!K!"=="SSH_KEY"            set "SSH_KEY=!V!"
          if /i "!K!"=="HOSTKEY"            set "HOSTKEY=!V!"
          if /i "!K!"=="BACKUP_DIR"         set "BACKUP_DIR=!V!"
          if /i "!K!"=="ERR_DIR"            set "ERR_DIR=!V!"
          if /i "!K!"=="LOGDIR"             set "LOGDIR=!V!"
          if /i "!K!"=="WINSCP_EXE"         set "WINSCP_EXE=!V!"
          if /i "!K!"=="REMOTE_CLEAN"       set "REMOTE_CLEAN=!V!"
          if /i "!K!"=="REMOTE_CLEAN_MASK"  set "REMOTE_CLEAN_MASK=!V!"
        )
      )
    )
  )
)

rem -------- 2) 既定補完・ログ初期化 --------------------------------------------
if not defined DEST_PORT set "DEST_PORT=22"
if not defined LOGDIR    set "LOGDIR=log"
if not defined REMOTE_CLEAN set "REMOTE_CLEAN=OFF"
if not defined REMOTE_CLEAN_MASK set "REMOTE_CLEAN_MASK=%FILE_PATTERN%"

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TS=%%i"
for %%A in ("%LOGDIR%") do set "LOGDIR=%%~fA"
set "LOGBASE=%LOGDIR%\%JOBBASE%"
if not exist "%LOGBASE%" mkdir "%LOGBASE%" 2>nul
set "OUTLOG=%LOGBASE%\%JOBBASE%_%TS%_out.log"
set "ERRLOG=%LOGBASE%\%JOBBASE%_%TS%_err.log"

rem -------- 3) 必須キー検証（不足なら WinSCP 未起動で RC=12） ------------------
set "MISSING="
for %%V in (SRC_DIR FILE_PATTERN DEST_HOST DEST_USER DEST_DIR ERR_DIR) do (
  if not defined %%V set "MISSING=1"
)
if defined MISSING (
  echo [ERROR] 必須項目未設定: SRC_DIR/FILE_PATTERN/DEST_HOST/DEST_USER/DEST_DIR/ERR_DIR を確認 >>"%ERRLOG%"
  popd & exit /b 12
)

rem -------- 4) 送信 0 件スキップ（WinSCP 未起動・正常終了） ---------------------
set "CNT="
for /f %%i in ('dir /b /a:-d "%SRC_DIR%\%FILE_PATTERN%" 2^>nul ^| find /c /v ""') do set "CNT=%%i"
if "%CNT%"=="0" (
  echo [INFO] No local files. Skip SFTP.>>"%OUTLOG%"
  popd & exit /b 0
)

rem -------- 5) WinSCP 実体解決（WINSCP_EXE ＞ PATH ＞ 無ければ異常） ----------
set "WINSCP=winscp.com"
if defined WINSCP_EXE if exist "%WINSCP_EXE%" set "WINSCP=%WINSCP_EXE%"
if /i "%WINSCP%"=="winscp.com" (
  for /f "delims=" %%P in ('where winscp.com 2^>nul') do (
    set "WINSCP=%%P"
    goto :WINSCP_FOUND
  )
  echo [ERROR] WinSCP.com が見つかりません（WINSCP_EXE 未設定/不正、PATHにも無し）>>"%ERRLOG%"
  popd & exit /b 12
)
:WINSCP_FOUND
echo [INFO] Using WinSCP: "%WINSCP%" >>"%OUTLOG%"

rem -------- 6) セッション引数生成（hostkey / privatekey は任意） --------------
set "SESSION=sftp://%DEST_USER%@%DEST_HOST%:%DEST_PORT%/"
if defined HOSTKEY set SESSION=%SESSION% -hostkey=""%HOSTKEY%""
if defined SSH_KEY  set SESSION=%SESSION% -privatekey="%SSH_KEY%"

rem -------- 7) 実行モード分岐（REMOTE_CLEAN：OFF/ALL/PATTERN） ---------------
set "REMOTE_CLEAN_NORM=OFF"
if /i "%REMOTE_CLEAN%"=="ALL"      set "REMOTE_CLEAN_NORM=ALL"
if /i "%REMOTE_CLEAN%"=="PATTERN"  set "REMOTE_CLEAN_NORM=PATTERN"
if /i "%REMOTE_CLEAN%"=="ON"       set "REMOTE_CLEAN_NORM=PATTERN"
if /i "%REMOTE_CLEAN%"=="TRUE"     set "REMOTE_CLEAN_NORM=PATTERN"

if /i "%REMOTE_CLEAN_NORM%"=="OFF" (
  rem --- 7-1) 削除なし（標準）：共通スクリプトで上書き PUT ---------------------
  set "SCRIPT=bin\common\sftp_run_winscp.txt"
  if not exist "!SCRIPT!" (
    echo [ERROR] WinSCP script not found: !SCRIPT! >>"%ERRLOG%"
    popd & exit /b 12
  )
  "%WINSCP%" /ini=nul /script="!SCRIPT!" /parameter "%SESSION%" "%SRC_DIR%" "%DEST_DIR%" "%FILE_PATTERN%" 1>>"%OUTLOG%" 2>>&1
  set "WINSCP_RC=!ERRORLEVEL!"
  set "RC=0"
  if not "!WINSCP_RC!"=="0" set "RC=12"
  
  goto :AFTER_WINSCP
)

rem --- 7-2) 削除あり：rm → put を 1 セッションで実行（※一時ファイルは作らない） ---
set "RM_LINE=rm ""%REMOTE_CLEAN_MASK%"""
if /i "%REMOTE_CLEAN_NORM%"=="ALL" set "RM_LINE=rm *"

"%WINSCP%" /ini=nul /command "open %SESSION%" "cd ""%DEST_DIR%""" "option batch abort" "option confirm off" "option transfer binary" "option failonnomatch off" "%RM_LINE%" "option failonnomatch on" "lcd ""%SRC_DIR%""" "put -resumesupport=off ""%FILE_PATTERN%""" "exit" 1>>"%OUTLOG%" 2>>&1
set "WINSCP_RC=!ERRORLEVEL!"
set "RC=0"
if not "!WINSCP_RC!"=="0" set "RC=12"

:AFTER_WINSCP

rem -------- 8) 結果処理：成功ならローカル退避／失敗なら回収 ------------------
if "%RC%"=="0" (
  echo [INFO] WinSCP success ^(RC=0^)>>"%OUTLOG%"
  if defined BACKUP_DIR (
    set "RUN_BAK=!BACKUP_DIR!\!TS!"
    if not exist "!RUN_BAK!" mkdir "!RUN_BAK!" 1>>"%OUTLOG%" 2>>&1
    set "MOVE_ERR="
    for /f "delims=" %%F in ('dir /b /a:-d "%SRC_DIR%\%FILE_PATTERN%" 2^>nul') do (
      move /Y "!SRC_DIR!\%%F" "!RUN_BAK!\" 1>>"%OUTLOG%" 2>>&1 || set "MOVE_ERR=1"
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

echo [ERROR] WinSCP異常終了 RC=%RC% >>"%ERRLOG%"
set "RUN_ERR=!ERR_DIR!\!TS!"
if not exist "!RUN_ERR!" mkdir "!RUN_ERR!" 2>>"%ERRLOG%"
set "ERR_MOVE="
for /f "delims=" %%F in ('dir /b /a:-d "%SRC_DIR%\%FILE_PATTERN%" 2^>nul') do (
  move /Y "!SRC_DIR!\%%F" "!RUN_ERR!\" 1>>"%OUTLOG%" 2>>"%ERRLOG%" || set "ERR_MOVE=1"
)
if defined ERR_MOVE (
  echo [ERROR] 失敗ファイルの回収^(move^)に失敗しました >>"%ERRLOG%"
)
echo [END] RC=12>>"%OUTLOG%"
popd & exit /b 12
