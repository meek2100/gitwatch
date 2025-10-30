{ lib, pkgs, config, ... }:
let
  gitwatch = pkgs.callPackage ./gitwatch.nix { };
  # Helper to generate flag arguments for options that have values (e.g., -s 2)
  getvar = flag: var: cfg:
    # Check for null, empty string, and false for flexibility.
    # Escape value for shell safety.
    if cfg."${var}" != null && cfg."${var}" != "" && cfg."${var}" != false
    then "${flag} ${lib.strings.escapeShellArg (toString cfg."${var}")}"
    else "";
  # Helper to generate flag arguments for boolean options (e.g., -R)
  getflag = flag: var: cfg:
    if cfg."${var}"
    then "${flag}"
    else "";
  mkSystemdService = name: cfg: lib.nameValuePair
    "gitwatch-${name}"
    (
      let
        # Options with values
        branchArg = getvar "-b" "branch" cfg;
        remoteArg = getvar "-r" "remote" cfg;
        messageArg = getvar "-m" "message" cfg;
        dateFmtArg = getvar "-d" "dateFmt" cfg;
        sleepTimeArg = getvar "-s" "sleepTime" cfg;
        timeoutArg = getvar "-t" "timeout" cfg; # NEW: Timeout argument
        excludePatternArg = getvar "-x" "excludePattern" cfg;
        globExcludePatternArg = getvar "-X" "globExcludePattern" cfg;
        eventsArg = getvar "-e" "events" cfg;
        gitDirArg = getvar "-g" "gitDir" cfg;

        # Log diff line options (-l or -L)
        logDiffLinesArg = if cfg.logDiffLines != null
          then getvar (if cfg.logDiffNoColor then "-L" else "-l") "logDiffLines" cfg
          else "";

        # Boolean options (flags)
        pullBeforePushFlag = getflag "-R" "pullBeforePush" cfg;
        skipIfMergingFlag = getflag "-M" "skipIfMerging" cfg;
        commitOnStartFlag = getflag "-f" "commitOnStart" cfg;
        useSyslogFlag = getflag "-S" "useSyslog" cfg;
        verboseFlag = getflag "-v" "verbose" cfg;
        passDiffsFlag = getflag "-C" "passDiffs" cfg;
        # Custom command args (special handling to use -c and override -m/-l if present)
        customCommandArgs = if cfg.customCommand != null
          then lib.strings.concatStringsSep " " (lib.lists.filter (s: s != "") [
            (getvar "-c" "customCommand" cfg)
            passDiffsFlag
          ])
          else "";
        # Combine all arguments into a single string
        allArgs = lib.strings.concatStringsSep " " (lib.lists.filter (s: s != "") [
          remoteArg branchArg dateFmtArg sleepTimeArg timeoutArg excludePatternArg globExcludePatternArg eventsArg gitDirArg logDiffLinesArg # NEW: timeoutArg
          pullBeforePushFlag skipIfMergingFlag commitOnStartFlag useSyslogFlag verboseFlag
          # Special handling for commit message: custom command overrides -m
          (if cfg.customCommand != null then customCommandArgs else messageArg)
          # The path must be the last argument
          (lib.strings.escapeShellArg cfg.path)
        ]);
        # Determine initial fetch command (git clone)
        # Only include branchArg if it's set and we are cloning
        cloneBranchArg = if cfg.branch != null then "-b ${lib.strings.escapeShellArg cfg.branch}" else "";
        fetcher =
          if cfg.remote == null
          then "true"
          else ''
            if [ -n "${lib.strings.escapeShellArg cfg.remote}" ] && ! [ -d "${lib.strings.escapeShellArg cfg.path}" ]; then
              git clone ${cloneBranchArg} "${lib.strings.escapeShellArg cfg.remote}" "${lib.strings.escapeShellArg cfg.path}"
            fi
          '';
      in
      {
        inherit (cfg) enable;
        # Use simple for service type, as gitwatch handles backgrounding if necessary
        serviceConfig.Type = "simple";
        after = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        description = "gitwatch for ${name}";
        path = with pkgs;
        [
          gitwatch git openssh
          # NEW: Add coreutils (for timeout), flock, and watcher tools
          coreutils # Provides 'timeout'
          flock # For robust locking
        ] ++ lib.optionals pkgs.stdenv.isLinux [ inotify-tools ]
          ++ lib.optionals pkgs.stdenv.isDarwin [ fswatch ];
        script = ''
          ${fetcher}
          gitwatch ${allArgs}
        '';
        serviceConfig.User = cfg.user;
      }
    );
in
{
  options.services.gitwatch = lib.mkOption {
    description = ''
      A set of git repositories to watch for. See
      [gitwatch](https://github.com/gitwatch/gitwatch) for more.
    '';
    default = { };
    example = {
      my-repo = {
        enable = true;
        user = "user";
        path = "/home/user/watched-project";
        remote = "git@github.com:me/my-project.git";
        message = "Auto-commit by gitwatch on %d";
        pullBeforePush = true;
        skipIfMerging = true;
        sleepTime = 5;
        timeout = 120;
        useSyslog = true;
        verbose = true;
        logDiffLines = 10;
        gitDir = "/mnt/data/.git";
        globExcludePattern = "*.log,temp/";
      };
      disabled-repo = {
        enable = false;
        user = "user";
        path = "/home/user/disabled-project";
        remote = "git@github.com:me/my-old-project.git";
        branch = "autobranch";
      };
    };
    type = with lib.types; attrsOf (submodule {
      options = {
        enable = lib.mkEnableOption "watching for repo";
        path = lib.mkOption {
          description = "The path to repo in local machine";
          type = str;
        };
        user = lib.mkOption {
          description = "The name of services's user";
          type = str;
          default = "root";
        };
        remote = lib.mkOption {
          description = "Optional url of remote repository (-r).";
          type = nullOr str;
          default = null;
        };
        message = lib.mkOption {
          description = "Optional message to use in as commit message (-m).";
          type = nullOr str;
          default = null;
        };
        branch = lib.mkOption {
          description = "Optional branch in remote repository (-b).";
          type = nullOr str;
          default = null;
        };
        # NEW BOOLEAN OPTIONS (FLAGS)
        pullBeforePush = lib.mkOption {
          description = "If true, run 'git pull --rebase' before push (-R).";
          type = bool;
          default = false;
        };
        skipIfMerging = lib.mkOption {
          description = "If true, prevent commits when a merge is in progress (-M).";
          type = bool;
          default = false;
        };
        commitOnStart = lib.mkOption {
          description = "If true, commit pending changes on startup (-f).";
          type = bool;
          default = false;
        };
        useSyslog = lib.mkOption {
          description = "If true, log messages to syslog (-S).";
          type = bool;
          default = false;
        };
        verbose = lib.mkOption {
          description = "If true, enable verbose output for debugging (-v).";
          type = bool;
          default = false;
        };
        passDiffs = lib.mkOption {
          description = "If true, pipe file list to custom command (-C).";
          type = bool;
          default = false;
        };
        logDiffNoColor = lib.mkOption {
          description = "If true, logs diff lines without color (overrides -l to -L).";
          type = bool;
          default = false;
        };
        sleepTime = lib.mkOption {
          description = "Time in seconds to wait after change detection (-s <secs>).";
          type = nullOr (oneOf [ str int ]);
          default = null;
        };
        timeout = lib.mkOption { # NEW: Timeout option
          description = "Timeout in seconds for critical Git operations (commit, pull, push) (-t <secs>).";
          type = nullOr (oneOf [ str int ]);
          default = null;
        };
        dateFmt = lib.mkOption {
          description = "The format string for the commit timestamp (-d <fmt>).";
          type = nullOr str;
          default = null;
        };
        excludePattern = lib.mkOption {
          description = "Raw regex pattern to exclude from watching (-x <pattern>).";
          type = nullOr str;
          default = null;
        };
        globExcludePattern = lib.mkOption {
          description = "Comma-separated list of glob patterns to exclude (-X <pattern>).";
          type = nullOr str;
          default = null;
        };
        events = lib.mkOption {
          description = "Events passed to inotifywait/fswatch (-e <events>).";
          type = nullOr str;
          default = null;
        };
        gitDir = lib.mkOption {
          description = "Location of the .git directory, if stored elsewhere (-g).";
          type = nullOr str;
          default = null;
        };
        logDiffLines = lib.mkOption {
          description = "Log actual changes up to a given number of lines, 0 for unlimited (-l).";
          type = nullOr (oneOf [ str int ]);
          default = null;
        };
        customCommand = lib.mkOption {
          description = "Command to be run to generate a commit message (-c).";
          type = nullOr str;
          default = null;
        };
      };
    });
  };
  config.systemd.services =
    lib.mapAttrs' mkSystemdService config.services.gitwatch;
}
