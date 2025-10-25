#!/usr/bin/env bats

# Load bats-core helpers relative to the test file's location
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

load startup-shutdown

function syncing_correctly { #@test
    # Start up gitwatch and see if commit and push happen automatically
    # after waiting two seconds
    ${BATS_TEST_DIRNAME}/../gitwatch.sh -v -r origin "$testdir/local/remote" 3>- &
    GITWATCH_PID=$!
    # Keeps kill message from printing to screen
    disown

    # Create a file, verify that it hasn't been added yet,
    # then commit and push
    cd remote

    # According to inotify documentation, a race condition results if you write
    # to directory too soon after it has been created;
    # hence, a short wait.
    sleep 1
    echo "line1" >> file1.txt

    # Wait a bit for inotify to figure out the file has changed, and do its add,
    # commit, and push.
    sleep $WAITTIME

    # Verify that push happened
    currentcommit=$(git rev-parse master)
    remotecommit=$(git rev-parse origin/master)
    [ "$currentcommit" = "$remotecommit" ]

    # Try making subdirectory with file
    lastcommit=$(git rev-parse master)
    mkdir subdir
    cd subdir
    echo "line2" >> file2.txt

    # Wait for the second commit triggered by file2.txt to complete
    sleep $WAITTIME

    # Verify that new commit has happened
    currentcommit=$(git rev-parse master)
    [ "$lastcommit" != "$currentcommit" ]

    # Verify that push happened
    currentcommit=$(git rev-parse master)
    remotecommit=$(git rev-parse origin/master)
    [ "$currentcommit" = "$remotecommit" ]


    # Try removing file to see if can work
    # Store commit before removal
    lastcommit=$(git rev-parse master)
    rm file2.txt

    # Wait for the commit triggered by the removal to complete
    sleep $WAITTIME

    # Verify that new commit has happened
    currentcommit=$(git rev-parse master)
    [ "$lastcommit" != "$currentcommit" ]

    # Verify that push happened
    currentcommit=$(git rev-parse master)
    remotecommit=$(git rev-parse origin/master)
    [ "$currentcommit" = "$remotecommit" ]

    # Teardown removes testing directories
    cd /tmp # Change out of test dir before teardown attempts removal
}
