@echo off
rem
rem gitwatch.bat - Windows wrapper for the gitwatch.sh WSL script
rem
rem This script finds the target path (the first argument not starting
rem with '-') and translates it to a WSL path, passing all other
rem arguments (flags) as-is, regardless of their position.
rem

setlocal

set "all_args=%*"
set "options="
set "target_path="

rem Loop through all arguments
:argloop
if "%~1"=="" goto :eof

rem Check if the argument is a flag (starts with -)
echo "%~1" | findstr /R /B /C:"-" >nul
if %errorlevel% equ 0 (
    rem It's an option/flag
    set "options=%options% %1"
) else (
    rem It's not a flag. Assume it's the target path.
    rem Only set the *first* non-flag argument as the path.
    if "%target_path%"=="" (
        set "target_path=%~1"
    ) else (
        rem This is a second non-flag argument, which is invalid.
        rem Pass it along; gitwatch.sh will show an error.
        set "options=%options% %1"
    )
)
shift
goto :argloop

:eof
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
