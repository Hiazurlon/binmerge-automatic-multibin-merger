
# 💿 Batch Multi-Bin Merger with Safe Deletion

A professional Windows Batch script to merge multiple `.bin` tracks into a single file across thousands of folders, featuring a smart cleanup system with user prompts and PowerShell-backed file handling.

## 📋 Overview

This tool automates the consolidation of CD-based games (PS1, Saturn, Sega CD) while providing an optional cleanup phase. It ensures the new files exist before offering to delete the old ones, with options for manual or automated bulk processing.

### Key Features:

* **Smart Cleanup:** Options for [Y]es, [N]o, [A]ll (Always delete), and [S]kip all (Never delete).
* **PowerShell Integration:** Uses a PowerShell subroutine to safely parse `.cue` files and delete tracks, ensuring filenames with spaces, parentheses, or brackets are handled perfectly.
* **Integrity Check:** Only offers to delete if the merged `.bin` and `.cue` are successfully created in the `mergedBin` folder.
* **Multi-Disc Support:** Safely processes Disc 1, Disc 2, etc., in the same folder without accidentally deleting the wrong files.
* **Recursion:** Works across 1400+ folders automatically.

---

## 💻 The Script (`merge_and_clean_bin_track.bat`)

```batch
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

:: 2. Main Loop - We use 'dir /b /s' but we handle the output very carefully
for /f "delims=" %%i in ('dir /s /b *.cue ^| findstr /v /i "mergedBin"') do (
    set "FULL_PATH=%%i"
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

:: --- SAFETY CHECK: Count tracks using a method that doesn't care about ' or ! ---
set "track_count=0"
for /f "delims=" %%a in ('findstr /i "FILE" "%G_NAME_EXT%"') do (
    set /a track_count+=1
)

if %track_count% LEQ 1 (
    echo [SKIPPED] This disc already has only one track.
    set /a count_skipped+=1
    goto CHECK_MULTIDISC
)

:: --- MERGE PHASE ---
if not exist "mergedBin" mkdir "mergedBin"
echo [PROCESSING] Merging tracks for "%G_NAME_ONLY%"...

:: Run binmerge with quoted variables
"%EXE_PATH%" "%G_NAME_EXT%" "mergedBin\%G_NAME_ONLY%"

if not exist "mergedBin\%G_NAME_ONLY%.bin" (
    echo [ERROR] Merged files were not created.
    set /a count_errors+=1
    goto CHECK_MULTIDISC
)

set /a count_merged+=1

:VERIFY_CLEANUP
:: We use a temporary variable for the choice to avoid expansion issues
set "USER_CHOICE=N"
if "%DELETE_MODE%"=="ALWAYS" (set "USER_CHOICE=Y" & goto DO_DELETE)
if "%DELETE_MODE%"=="ALWAYS_MOVE" (set "USER_CHOICE=YM" & goto DO_MOVE)
if "%DELETE_MODE%"=="NEVER" (goto SKIP_DELETE)

echo.
echo Status: Merged files are ready in mergedBin.
echo Action for ORIGINAL tracks: [Y] Yes, [YM] Yes+Move, [A] All, [AM] All+Move, [N] No, [S] Skip All
set /p choice="Selection: "

:: Use 'if' checks without delayed expansion
if /i "%choice%"=="Y"  goto DO_DELETE
if /i "%choice%"=="YM" goto DO_MOVE
if /i "%choice%"=="A"  (set "DELETE_MODE=ALWAYS" & goto DO_DELETE)
if /i "%choice%"=="AM" (set "DELETE_MODE=ALWAYS_MOVE" & goto DO_MOVE)
if /i "%choice%"=="N"  goto SKIP_DELETE
if /i "%choice%"=="S"  (set "DELETE_MODE=NEVER" & goto SKIP_DELETE)
goto SKIP_DELETE

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
echo [KEEP] Originals preserved in root. Merged files are in mergedBin.
goto CHECK_MULTIDISC

:CHECK_MULTIDISC
:: --- MULTI-DISC LST GENERATOR ---
set "cue_count=0"
for %%c in (*.cue) do set /a cue_count+=1
if %cue_count% GTR 1 (
    echo [PSIO] Multi-disc detected. Updating multidisc.lst...
    if exist "multidisc.lst" del "multidisc.lst"
    :: Shielding the command from quotes and ! via environment variables
    powershell -NoProfile -Command "Get-ChildItem *.cue | ForEach-Object { $c = Get-Content $_.FullName | Select-String 'FILE'; $c.Line.Split([char]34) | Where-Object { $_ -like '*.bin*' } | ForEach-Object { $_.Replace('mergedBin\','') } } | Out-File -FilePath 'multidisc.lst' -Encoding ascii"
)

popd
exit /b

:CLEAN_TRACKS
echo [CLEANUP] Removing original tracks...
:: Using a temporary ENV variable to pass the filename into PowerShell safely
set "PS_TARGET=%G_NAME_EXT%"
powershell -NoProfile -Command "$cue = Get-Content $env:PS_TARGET; foreach ($line in $cue) { if ($line -match 'FILE \"(.*)\" BINARY') { $file = $matches[1]; if (Test-Path $file) { Remove-Item -Path $file -Force } } }; Remove-Item -Path $env:PS_TARGET -Force"
exit /b

```

---

## 🛠️ Commands Breakdown

| Command | Function |
| --- | --- |
| `setlocal DisableDelayedExpansion` | **Logic**: Prevents the script from treating `!` in filenames (like *Rat Attack!*) as a variable marker, ensuring the full name reaches the tool. |
| `for /f "delims="` | **Apostrophe Safety**: By removing delimiters, the script treats a full line (including `'` and spaces) as a single string, preventing names like *Leapin' Lemurs* from being cut off. |
| `set "PS_TARGET=%G_NAME_EXT%"` | **Shielding**: Stores the filename in a system variable so PowerShell can read it directly from memory rather than as a text argument, which prevents "positional parameter" errors. |
| `findstr /v /i "mergedBin"` | <br>**Loop Filter**: Prevents the script from scanning the `mergedBin` subfolder, avoiding infinite loops.|
| `powershell -NoProfile` | <br>**Surgical Cleanup**: Modernized logic that reads the `.cue` and deletes only the specific tracks listed inside to protect other discs in the same folder.|
| `.Split([char]34)` | <br>**Agnostic Parsing**: Splits strings by double quotes (ASCII 34) to extract filenames for the `.lst` file regardless of internal name mismatches.|
| `move /y "mergedBin\*.*" .` | <br>**Finalization**: Relocates the newly merged files to the root of the game folder for PSIO cover art compatibility.|
| `Out-File -Encoding ascii` | <br>**PSIO Standard**: Saves the `multidisc.lst` in plain ASCII, the only format the PSIO hardware can reliably read.|

---

## Explaining the core code


### Check Multidisc subroutine
The PowerShell command inside the `:CHECK_MULTIDISC` subroutine is a complex "one-liner" designed to be a robust engine for PSIO's multi-disc requirements. It ensures that no matter how messy the internal names are, the `.lst` file is perfect.

Here is the breakdown of that specific command:

#### The Command

```powershell
Get-ChildItem *.cue | ForEach-Object { $c = Get-Content $_.FullName | Select-String 'FILE'; $c.Line.Split([char]34) | Where-Object { $_ -like '*.bin* Cory' } | ForEach-Object { $_.Replace('mergedBin\','') } } | Out-File -FilePath 'multidisc.lst' -Encoding ascii

```

#### Explanation by Segment:

1. **`Get-ChildItem *.cue`**
* Finds every `.cue` file in the current folder (e.g., Disc 1, Disc 2).


2. **`$c = Get-Content $_.FullName | Select-String 'FILE'`**
* Opens each `.cue` file and grabs only the lines containing the word `FILE`. This is where the actual name of the `.bin` file is stored.


3. **`.Split([char]34)`**
* **The Magic Part**: `[char]34` is the ASCII code for a **double quote (")**.
* Since `.cue` files store names as `FILE "Name of Game.bin" BINARY`, splitting by the quotes extracts the text inside the quotes perfectly, even if the filename contains spaces or parentheses that would break a normal Batch script.


4. **`Where-Object { $_ -like '*.bin*' }`**
* Filters the results to keep only the part of the string that is actually the `.bin` filename.


5. **`.Replace('mergedBin\','')`**
* **The Path Fixer**: Because the `binmerge` tool puts temporary files in the `mergedBin` folder, the strings might look like `mergedBin\Game.bin`.
* This strips that prefix away so the `multidisc.lst` contains only the clean filename (e.g., `Game.bin`), which is where the file will be after the script moves it to the root.


6. **`Out-File -FilePath 'multidisc.lst' -Encoding ascii`**
* Creates the final list. It uses **ASCII encoding** because the PSIO hardware is built on older standards and often cannot read modern `UTF-8` or `Unicode` text files.

#### Explanation of clean tracks subroutine
The `:CLEAN_TRACKS` subroutine is the script's "surgical tool." Its job is to delete the original multi-bin files only after a successful merge has been confirmed.

In older versions of the script, we used standard Batch `del` commands, but those often failed when filenames contained spaces, parentheses `()`, or brackets `[]`. By switching to a **PowerShell-driven subroutine**, we ensure 100% accuracy.

#### What it does (Step-by-Step):

1. **Context Awareness**: It is called only after the script verifies that the new, merged files exist in the `mergedBin` folder.
2. **Reads the Source**: It opens the original `.cue` file (`%FILENAME_EXT%`) to see exactly which `.bin` files were linked to that specific disc.
3. **Surgical Deletion**: It identifies each file listed in the `.cue` and deletes them one by one. This is vital for **Multi-Disc folders**: if you are cleaning up "Disc 1", this subroutine ensures "Disc 2" files remain untouched because they aren't listed in Disc 1's `.cue`.
4. **Self-Termination**: After all the associated `.bin` tracks are gone, it deletes the original `.cue` file itself.

#### The PowerShell Command Explained:

```powershell
powershell -Command "$cue = Get-Content '%FILENAME_EXT%'; foreach ($line in $cue) { if ($line -match 'FILE \"(.*)\" BINARY') { $file = $matches[1]; if (Test-Path \"$file\") { Remove-Item -Path \"$file\" -Force } } }; Remove-Item -Path '%FILENAME_EXT%' -Force"

```

* **`Get-Content '%FILENAME_EXT%'`**: Loads the text of the `.cue` file into memory.
* **`if ($line -match 'FILE \"(.*)\" BINARY')`**: Uses **Regular Expressions (Regex)** to find lines that define a file. The `(.*)` captures the exact text between the double quotes—this is the filename.
* **`$file = $matches[1]`**: Stores that captured filename (e.g., `Game (Track 1).bin`) into a variable.
* **`Test-Path \"$file\"`**: A safety check that asks, "Does this file actually exist on the hard drive?" before trying to delete it.
* **`Remove-Item -Path \"$file\" -Force`**: Deletes the track. The `-Force` flag ensures it bypasses "read-only" attributes.
* **`Remove-Item -Path '%FILENAME_EXT%' -Force`**: Finally, deletes the original `.cue` file that started the process.

---

## 🛡️ Handling Special Characters

The primary bug in standard batch scripts involves how Windows handles **Exclamation Points (`!`)** and **Single Quotes (`'`)**.

### The Exclamation Point Fix

In most scripts, `EnabledDelayedExpansion` is used to update counters. However, if a file is named `Shipwreckers!.cue`, the script sees the `!` and tries to find a variable named `Shipwreckers`. This script now defaults to `DisableDelayedExpansion` and uses a `call :PROCESS_GAME` structure to pass filenames as "Static Arguments," keeping the `!` as part of the text.

### The PowerShell "Env" Shield

When passing a name like `Akuji the Heartless (US).cue` to PowerShell, parentheses often cause "Positional Parameter" errors. To solve this, the script now sets a temporary environment variable:

```batch
set "PS_TARGET=%G_NAME_EXT%"

```

PowerShell then accesses this via `$env:PS_TARGET`. Because the filename is never "typed" directly into the PowerShell command string, characters like `(` and `'` cannot break the syntax.


## 🚀 How to Use

### Prerequisites

1. Place `binmerge.exe` in your **Root** folder (the folder containing all your game subfolders).
2. Ensure you have PowerShell installed (standard on Windows 10/11).

### Instructions

1. Run `merge_and_clean_bin_track.bat`.
2. The script will find the first multi-track game and merge it. It will then pause and ask:
* **Y (Yes)**: Deletes the old multi-bin tracks for the current game.
* **YM (Yes Move)**: Deletes old tracks **and** moves the new single `.bin/.cue` to the main folder. **(Recommended)**
* **A / AM (All)**: Same as above, but automates the choice for every game found afterwards.
* **N / S**: Keeps your original files exactly where they are.


3. **Multi-Disc Handling**: If a folder contains "Game (Disc 1).cue" and "Game (Disc 2).cue", the script processes them individually. The PowerShell cleanup ensures that when Disc 1 is cleaned, it **only** deletes the tracks belonging to Disc 1.

---

## 🔍 Troubleshooting

* **Special Characters**: If your folders have names like `Game [v1.1] (USA) {Redump}`, the script uses double-quotes and PowerShell matching to ensure these don't cause crashes.
* **Permission Errors**: If the script fails to delete files, try running the `.bat` as **Administrator**.
* **Binmerge.exe not found**: Ensure the `.exe` is in the same folder as the `.bat` file, or update the `EXE_PATH` in the script.

## ⚠️ PSIO Users - Important Note

For **PSIO (PlayStation Input Output)** users, the **[YM]** or **[AM]** options are highly recommended.

PSIO requires a specific folder structure to display cover art correctly. By choosing **Move**, the script places the consolidated `.bin` and `.cue` files directly in the game's root folder. This allows the [PSIO Library Cover Downloader](https://ncirocco.github.io/PSIO-Library/) to scan your folders and match the filenames to its database without manual renaming.