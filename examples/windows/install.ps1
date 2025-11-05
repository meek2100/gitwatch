# Gitwatch for Windows (WSL) Installer Script
# This script must be run as Administrator.

# --- 1. Check for Administrator Privileges ---
Write-Host "Checking for Administrator privileges..."
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Warning "This script must be run as Administrator to install WSL and modify the system PATH."
  Write-Warning "Please re-run this script from an Administrator PowerShell terminal."
  Read-Host "Press Enter to exit..."
  exit 1
}
Write-Host "Administrator privileges confirmed." -ForegroundColor Green

# Define paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$GitwatchScriptSource = Join-Path $ScriptDir "gitwatch.sh"
$GitwatchWrapperSource = Join-Path $ScriptDir "gitwatch.bat"
$WslScriptPath = "/usr/local/bin/gitwatch"

# --- 2. Check and Install WSL ---
Write-Host "Checking for WSL..."
try {
  $wslStatus = wsl.exe -l -q
  Write-Host "WSL is already installed." -ForegroundColor Green
}
catch {
  Write-Host "WSL not found. Installing WSL (this may take several minutes and require a reboot)..."
  try {
    # --install is non-interactive and installs the default Ubuntu distribution
    wsl.exe --install
    Write-Host "WSL installation complete. You may need to reboot your computer after this script finishes." -ForegroundColor Green
  }
  catch {
    Write-Error "WSL installation failed. Please install WSL manually and re-run this script."
    Read-Host "Press Enter to exit..."
    exit 1
  }
}

# --- 3. Detect Distro and Install Dependencies Inside WSL ---
Write-Host "Detecting WSL distribution and installing dependencies..."
try {
  # Check /etc/os-release to find the package manager
  $osRelease = wsl.exe -e cat /etc/os-release
  $pkgManager = ""

  if ($osRelease -like "*ID=ubuntu*" -or $osRelease -like "*ID=debian*") {
    $pkgManager = "apt-get"
  }
  elseif ($osRelease -like "*ID=fedora*" -or $osRelease -like "*ID=rhel*" -or $osRelease -like "*ID=centos*") {
    $pkgManager = "dnf" # or yum
  }
  elseif ($osRelease -like "*ID=alpine*") {
    $pkgManager = "apk"
  }
  elseif ($osRelease -like "*ID=sles*" -or $osRelease -like "*ID=opensuse*") {
    $pkgManager = "zypper"
  }

  $dependencies = "git coreutils util-linux inotify-tools"

  if ($pkgManager -eq "apt-get") {
    Write-Host "Debian-based distro detected. Installing dependencies ($dependencies) using apt-get..."
    wsl.exe -e sudo apt-get update
    wsl.exe -e sudo apt-get install -y $dependencies
  }
  elseif ($pkgManager -eq "dnf") {
    Write-Host "Fedora-based distro detected. Installing dependencies ($dependencies) using dnf..."
    wsl.exe -e sudo dnf install -y $dependencies
  }
  elseif ($pkgManager -eq "apk") {
    Write-Host "Alpine distro detected. Installing dependencies ($dependencies) using apk..."
    wsl.exe -e sudo apk add $dependencies
  }
  elseif ($pkgManager -eq "zypper") {
    Write-Host "SUSE-based distro detected. Installing dependencies ($dependencies) using zypper..."
    wsl.exe -e sudo zypper install -y $dependencies
  }
  else {
    Write-Warning "Could not automatically detect a supported package manager (apt-get, dnf, apk, zypper)."
    Write-Warning "Attempting to use 'apt-get'..."
    wsl.exe -e sudo apt-get update
    wsl.exe -e sudo apt-get install -y $dependencies
    Write-Warning "If the above command failed, please install the following dependencies in your WSL distro manually: $dependencies"
  }

  Write-Host "WSL dependencies installed successfully." -ForegroundColor Green
}
catch {
  Write-Error "Failed to install dependencies in WSL. Please check your internet connection and install them manually: $dependencies"
  Read-Host "Press Enter to exit..."
  exit 1
}

# --- 4. Install gitwatch.sh into WSL ---
Write-Host "Installing gitwatch.sh into WSL at $WslScriptPath..."
if (-NOT (Test-Path $GitwatchScriptSource)) {
  Write-Error "Could not find 'gitwatch.sh' in the installer directory."
  Write-Error "Please ensure 'gitwatch.sh' is in the same folder as 'install.ps1'."
  Read-Host "Press Enter to exit..."
  exit 1
}
try {
  # Copy the script into WSL and make it executable
  # We must use wslpath to get the correct path for the 'cp' command
  $wslSourcePath = wsl.exe -e wslpath -a $GitwatchScriptSource
  wsl.exe -e sudo cp $wslSourcePath $WslScriptPath
  wsl.exe -e sudo chmod +x $WslScriptPath
  Write-Host "gitwatch.sh installed successfully in WSL." -ForegroundColor Green
}
catch {
  Write-Error "Failed to copy gitwatch.sh into WSL."
  Read-Host "Press Enter to exit..."
  exit 1
}

# --- 5. Install the gitwatch.bat Wrapper on Windows ---
$InstallDir = "C:\Program Files\gitwatch"
$WrapperDest = Join-Path $InstallDir "gitwatch.bat"
Write-Host "Installing gitwatch.bat wrapper to $WrapperDest..."
if (-NOT (Test-Path $GitwatchWrapperSource)) {
  Write-Error "Could not find 'gitwatch.bat' in the installer directory."
  Write-Error "Please ensure 'gitwatch.bat' is in the same folder as 'install.ps1'."
  Read-Host "Press Enter to exit..."
  exit 1
}

New-Item -Path $InstallDir -ItemType Directory -Force
Copy-Item -Path $GitwatchWrapperSource -Destination $WrapperDest -Force

# --- 6. Add Wrapper to Windows System PATH ---
Write-Host "Adding $InstallDir to the system PATH..."
try {
  $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  if ($currentPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$InstallDir", "Machine")
    Write-Host "System PATH updated. You may need to restart your terminal." -ForegroundColor Green
  }
  else {
    Write-Host "$InstallDir is already in the system PATH."
  }
}
catch {
  Write-Error "Failed to update the system PATH. Please add '$InstallDir' to your PATH manually."
}

Write-Host ""
Write-Host "Gitwatch for Windows installation is complete!" -ForegroundColor Cyan
Write-Host "You can now run 'gitwatch' from any new PowerShell or Command Prompt window."
Read-Host "Press Enter to exit..."
