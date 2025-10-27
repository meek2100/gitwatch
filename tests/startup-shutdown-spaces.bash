# This inserts customs setup and teardown because of spaces in the file name

setup() {
  # Time to wait for gitwatch to respond
  # shellcheck disable=SC2034
  WAITTIME=4
  # Set up directory structure and initialize remote
  # Use a name with spaces for the main test directory
  testdir=$(mktemp -d "/tmp/temp space.XXXXX")
  # shellcheck disable=SC2164
  cd "$testdir"
  mkdir remote
  # shellcheck disable=SC2164
  cd remote
  git init -q --bare
  # shellcheck disable=SC2103
  cd ..

  # --- Add initial commit directly to the bare remote ---
  # Clone the bare repo temporarily
  git clone -q remote initial-setup-spaces
  cd initial-setup-spaces
  # Create and commit an initial file
  echo "initial setup with spaces" > initial_file.txt
  git add initial_file.txt
  git commit -q -m "Initial commit for space test setup"
  # Push back to the bare remote
  git push -q origin master
  # Go back up and remove the temporary clone
  cd ..
  rm -rf initial-setup-spaces
  # --- End initial commit ---

  # Now set up the local repo for the test, cloning INTO a directory with spaces
  # shellcheck disable=SC2164
  mkdir local
  # shellcheck disable=SC2164
  cd local
  # Clone into the directory named "rem with spaces"
  git clone -q ../remote "rem with spaces"
}

teardown() {
  echo '# Teardown started' >&3
  # Remove testing directories
  # shellcheck disable=SC2164
  cd /tmp

  # Kill background
  # process
  # Check if job %1 exists before trying to kill/fg
  if jobs %1 &> /dev/null; then
      kill -9 %1 || true # Ignore error if already gone
      fg %1 || true      # Ignore error if already gone
  fi


  # Use pkill to be more robust, especially on macOS
  # Send SIGTERM first, then SIGKILL if needed after a short wait
  if [ -n "${GITWATCH_PID:-}" ]; then
      pkill -15 -P "$GITWATCH_PID" || true # Try TERM first
      sleep 0.5
      pkill -9 -P "$GITWATCH_PID" || true # Force KILL if still running
  fi

  # Attempt to kill watchers cleanly
  pkill -15 inotifywait || true
  pkill -15 fswatch || true
  sleep 0.5
  pkill -9 inotifywait || true
  pkill -9 fswatch || true


  # Remove test directory (ensure quoting handles spaces)
  if [ -n "$testdir" ] && [ -d "$testdir" ]; then
    rm -rf "$testdir"
  fi

  echo '# Teardown complete' >&3
}
