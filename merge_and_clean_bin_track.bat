@echo off
:: Use DisableDelayedExpansion by default to protect ! and ' characters
setlocal DisableDelayedExpansion

:: 1. Setup paths and counters
set "EXE_PATH=%~dp0binmerge.exe"
set "DELETE_MODE=ASK"
set /a count_merged=0
set /a count_skipped=0
set /a count_errors=0

if not exist "%EXE_PATH%" (
    echo ERROR: binmerge.exe not found at: %~dp0
    pause
    exit /b
)

:: 2. Main Loop
for /f "delims=" %%i in ('dir /s /b *.cue ^| findstr /v /i "mergedBin"') do (
    set "G_DIR=%%~dpi"
    set "G_NAME_EXT=%%~nxi"
    set "G_NAME_ONLY=%%~ni"
    call :PROCESS_GAME
)

:: 3. Final Report
echo.
echo ======================================================
echo                FINAL SUMMARY REPORT
echo ======================================================
echo  Games/Discs Merged: %count_merged%
echo  Skipped (Already single): %count_skipped%
echo  Errors Encountered: %count_errors%
echo ======================================================
echo.
pause
exit /b

:PROCESS_GAME
echo.
echo ------------------------------------------------------
echo Current Item: "%G_NAME_EXT%"

pushd "%G_DIR%"

set "track_count=0"
for /f "delims=" %%a in ('findstr /i "FILE" "%G_NAME_EXT%"') do (
    set /a track_count+=1
)

if %track_count% LEQ 1 (
    echo [SKIPPED] This disc already has only one track.
    set /a count_skipped+=1
    goto CHECK_MULTIDISC
)

if not exist "mergedBin" mkdir "mergedBin"
echo [PROCESSING] Merging tracks for "%G_NAME_ONLY%"...
"%EXE_PATH%" "%G_NAME_EXT%" "mergedBin\%G_NAME_ONLY%"

if not exist "mergedBin\%G_NAME_ONLY%.bin" (
    echo [ERROR] Merged files were not found.
    set /a count_errors+=1
    goto CHECK_MULTIDISC
)

set /a count_merged+=1

:VERIFY_CLEANUP
if "%DELETE_MODE%"=="ALWAYS" goto DO_DELETE
if "%DELETE_MODE%"=="ALWAYS_MOVE" goto DO_MOVE
if "%DELETE_MODE%"=="NEVER" goto SKIP_DELETE

:ASK_USER
echo.
echo Status: Merged files are ready in mergedBin.
echo.
echo Action for ORIGINAL tracks:
echo [Y]  Yes      - Delete originals for THIS disc
echo [YM] Yes Move - Delete originals AND move merged file to root
echo [A]  All      - Delete originals for ALL remaining items
echo [AM] All Move - Delete AND Move for ALL remaining items
echo [N]  No       - Keep originals for THIS disc
echo [S]  Skip     - Keep originals for ALL remaining items
echo.
set /p choice="Selection: "

if /i "%choice%"=="Y"  goto DO_DELETE
if /i "%choice%"=="YM" goto DO_MOVE
if /i "%choice%"=="A"  (set "DELETE_MODE=ALWAYS" & goto DO_DELETE)
if /i "%choice%"=="AM" (set "DELETE_MODE=ALWAYS_MOVE" & goto DO_MOVE)
if /i "%choice%"=="N"  goto SKIP_DELETE
if /i "%choice%"=="S"  (set "DELETE_MODE=NEVER" & goto SKIP_DELETE)
goto ASK_USER

:DO_MOVE
call :CLEAN_TRACKS
echo [MOVING] Relocating merged files to root folder...
move /y "mergedBin\*.*" . >nul
rd "mergedBin" 2>nul
goto CHECK_MULTIDISC

:DO_DELETE
call :CLEAN_TRACKS
goto CHECK_MULTIDISC

:SKIP_DELETE
echo [KEEP] Originals preserved.
goto CHECK_MULTIDISC

:CHECK_MULTIDISC
set "cue_count=0"
for %%c in (*.cue) do set /a cue_count+=1
if %cue_count% GTR 1 (
    echo [PSIO] Multi-disc detected. Updating multidisc.lst...
    if exist "multidisc.lst" del "multidisc.lst"
    powershell -NoProfile -Command "Get-ChildItem *.cue | ForEach-Object { $c = Get-Content $_.FullName | Select-String 'FILE'; $c.Line.Split([char]34) | Where-Object { $_ -like '*.bin*' } | ForEach-Object { $_.Replace('mergedBin\','') } } | Out-File -FilePath 'multidisc.lst' -Encoding ascii"
)

popd
exit /b

:CLEAN_TRACKS
echo [CLEANUP] Removing original tracks...
set "PS_TARGET=%G_NAME_EXT%"
powershell -NoProfile -Command "$cue = Get-Content $env:PS_TARGET; foreach ($line in $cue) { if ($line -match 'FILE \"(.*)\" BINARY') { $file = $matches[1]; if (Test-Path $file) { Remove-Item -Path $file -Force } } }; Remove-Item -Path $env:PS_TARGET -Force"
exit /b