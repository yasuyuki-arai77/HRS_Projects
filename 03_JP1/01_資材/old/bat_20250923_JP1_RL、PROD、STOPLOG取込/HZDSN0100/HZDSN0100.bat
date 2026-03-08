@echo off
rem =====================================================================
rem HZDSN0100.bat
rem 役割:
rem   HZDSN0100 の送信ジョブ起動スクリプト。
rem   共通ランチャー run_winscp.bat を呼び出し、INI と JOBBASE を渡す。
rem
rem 参照:
rem   - 共通バッチ      : exec\bin\common\run_winscp.bat
rem   - WinSCPスクリプト: exec\bin\common\sftp_run_winscp.txt
rem   - 共通INI         : exec\conf\common.ini（DEST_*/HOSTKEY/SSH_KEY 等を集中管理）
rem
rem 引数:
rem   - なし（自フォルダの HZDSN0100.ini を使用）
rem
rem ログ:
rem   - exec\log\HZDSN0100\HZDSN0100_yyyyMMdd_HHmmss_{out|err|winscp}.log
rem     ※出力は共通バッチ側で実施
rem
rem 戻り値:
rem   - run_winscp.bat の ERRORLEVEL をそのまま返却（成功=0／失敗=12）
rem
rem 注意:
rem   - 本ファイルの配置: exec\bin\bat\HZDSN0100\HZDSN0100.bat
rem   - 相対パス解決は %~dp0（このファイルのフォルダ）を基準とする
rem   - JP1等から本バッチを直接起動（標準出力/標準エラーの指定は不要）
rem
rem フロー:
rem   1) HERE=%~dp0 で自フォルダを基準化
rem   2) run_winscp.bat を呼び出し（INI と JOBBASE を渡す）
rem   3) 返ってきた ERRORLEVEL をそのまま返却
rem =====================================================================

setlocal
set "HERE=%~dp0"

call "%HERE%..\..\common\run_winscp.bat" "%HERE%HZDSN0100.ini" "HZDSN0100"
exit /b %ERRORLEVEL%
