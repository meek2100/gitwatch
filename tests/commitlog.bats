#!/usr/bin/env bats

# Load bats-core helpers relative to the test file's location
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

load startup-shutdown

function commit_log_messages_working { #@test
    # Start up gitwatch with logging, see if works
    "${BATS_TEST_DIRNAME}"/../gitwatch.sh -v -l 10 "$testdir/local/remote" 3>&- &
    GITWATCH_PID=$!

    # Keeps kill message from printing to screen
    disown

    # Create a file, verify that it hasn't been added yet, then commit
    cd remote

    # According to inotify documentation, a race condition results if you write
    # to directory too soon after it has been created; hence, a short wait.
    sleep 1
    echo "line1" >> file1.txt

    # Wait a bit for inotify to figure out the file has changed, and do its add,
    # and commit
    sleep "$WAITTIME"

    # Make a new change
    echo "line2" >> file1.txt
    sleep "$WAITTIME"

    # Check commit log that the diff is in there
    run git log -1 --oneline
    [[ $output == *"file1.txt"* ]]
}

