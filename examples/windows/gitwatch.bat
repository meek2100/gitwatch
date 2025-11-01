@echo off
rem
rem gitwatch.bat - Windows wrapper for the gitwatch.sh WSL script
rem
rem This script finds the last argument (which must be the target path),
rem translates it to a WSL path, and passes all other arguments as-is.
rem

setlocal

set "all_args=%*"
set "options="
set "target_path="

rem Loop through all arguments, separating options from the final target path
:argloop
if "%~2"=="" goto found_last
set "options=%options% %1"
shift
goto argloop

:found_last
rem The last argument is the target path
set "target_path=%~1"

rem Check if a path was provided
if "%target_path%"=="" (
    rem No path provided, just run gitwatch (which will show the help message)
    wsl.exe -e /usr/local/bin/gitwatch %options%
    goto :eof
)

rem Translate the Windows path (e.g., C:\path) to a WSL path (e.g., /mnt/c/path)
FOR /F "usebackq tokens=*" %%i IN (`wsl.exe -e wslpath -a %target_path%`) DO SET "wsl_path=%%i"

rem Execute the real script inside WSL with the options and the *translated* path
wsl.exe -e /usr/local/bin/gitwatch.sh %options% "%wsl_path%"
