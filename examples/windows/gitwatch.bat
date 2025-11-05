@echo off
rem
rem gitwatch.bat - Windows wrapper for the gitwatch.sh WSL script
rem
rem This script finds the target path by identifying the last argument
rem that does not begin with a '-'. This allows flags to be placed
rem before or after the target path.
rem

setlocal

set "options="
set "target_path="
set "last_non_flag_arg="

rem Loop through all arguments to find the last non-flag
:argloop
if "%~1"=="" goto :process
rem Check if the argument is a flag (starts with -)
echo "%~1" | findstr /R /B /C:"-" >nul
if %errorlevel% equ 0 (
    rem It's an option/flag, add it to the options string
    set "options=%options% %1"
) else (
    rem It's not a flag. Store it as the *potential* target path.
    set "last_non_flag_arg=%~1"
)
shift
goto :argloop

:process
rem The last non-flag argument we found is the target path
set "target_path=%last_non_flag_arg%"

rem Check if a path was provided
if "%target_path%"=="" (
    rem No path provided, just run gitwatch (which will show the help message)
    wsl.exe -e /usr/local/bin/gitwatch.sh %options%
    goto :end
)

rem Translate the Windows path (e.g., C:\path) to a WSL path (e.g., /mnt/c/path)
FOR /F "usebackq tokens=*" %%i IN (`wsl.exe -e wslpath -a %target_path%`) DO SET "wsl_path=%%i"

rem Execute the real script inside WSL with the options and the *translated* path
wsl.exe -e /usr/local/bin/gitwatch.sh %options% "%wsl_path%"

:end
endlocal
