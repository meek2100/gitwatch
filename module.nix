{
  lib,
  pkgs,
  config,
  ...
}:
let
  gitwatch = pkgs.callPackage ./gitwatch.nix { };
  getvar =
    flag: var: cfg:
    if cfg."${var}" != null && cfg."${var}" != "" && cfg."${var}" != false then
      "${flag} ${lib.strings.escapeShellArg (toString cfg."${var}")}"
    else
      "";
  getflag =
    flag: var: cfg:
    if cfg."${var}" then "${flag}" else "";
  mkSystemdService =
    name: cfg:
    lib.nameValuePair "gitwatch-${name}" (
      let
        branchArg = getvar "-b" "branch" cfg;
        remoteArg = getvar "-r" "remote" cfg;
        messageArg = getvar "-m" "message" cfg;
        dateFmtArg = getvar "-d" "dateFmt" cfg;
        sleepTimeArg = getvar "-s" "sleepTime" cfg;

        timeoutArg = getvar "-t" "timeout" cfg;
        excludePatternArg = getvar "-x" "excludePattern" cfg;
        globExcludePatternArg = getvar "-X" "globExcludePattern" cfg;
        eventsArg = getvar "-e" "events" cfg;
        gitDirArg = getvar "-g" "gitDir" cfg;
        logDiffLinesArg =
          if cfg.logDiffLines != null then
            getvar (if cfg.logDiffNoColor then "-L" else "-l") "logDiffLines" cfg
          else
            "";

        pullBeforePushFlag = getflag "-R" "pullBeforePush" cfg;
        skipIfMergingFlag = getflag "-M" "skipIfMerging" cfg;
        commitOnStartFlag = getflag "-f" "commitOnStart" cfg;
        useSyslogFlag = getflag "-S" "useSyslog" cfg;
        verboseFlag = getflag "-v" "verbose" cfg;
        quietFlag = getflag "-q" "quiet" cfg;
        passDiffsFlag = getflag "-C" "passDiffs" cfg;
        disableLockingFlag = getflag "-n" "disableLocking" cfg;
        logLineLengthEnv =
          if cfg.logLineLength != null then
            "GW_LOG_LINE_LENGTH=${lib.strings.escapeShellArg (toString cfg.logLineLength)}"
          else
            "";
        customCommandArgs =
          if cfg.customCommand != null then
            lib.strings.concatStringsSep " " (
              lib.lists.filter (s: s != "") [
                (getvar "-c" "customCommand" cfg)
                passDiffsFlag
              ]
            )
          else
            "";
        messageAndLogArgs =
          if cfg.customCommand != null then
            customCommandArgs
          else
            lib.strings.concatStringsSep " " (
              lib.lists.filter (s: s != "") [
                messageArg
                logDiffLinesArg
              ]
            );
        allArgs = lib.strings.concatStringsSep " " (
          lib.lists.filter (s: s != "") [
            remoteArg
            branchArg
            dateFmtArg
            sleepTimeArg
            timeoutArg
            excludePatternArg
            globExcludePatternArg
            eventsArg
            gitDirArg
            pullBeforePushFlag
            skipIfMergingFlag
            commitOnStartFlag
            useSyslogFlag
            (if cfg.quiet then quietFlag else verboseFlag)
            disableLockingFlag
            messageAndLogArgs
          (lib.strings.escapeShellArg cfg.path)
          ]
        );
        cloneBranchArg = if cfg.branch != null then "-b ${lib.strings.escapeShellArg cfg.branch}" else "";
        fetcher =
          if cfg.remote == null then
            "true"
          else
            ''
              if [ -n "${lib.strings.escapeShellArg cfg.remote}" ] && ! [ -d "${lib.strings.escapeShellArg cfg.path}" ]; then
                git clone ${cloneBranchArg} "${lib.strings.escapeShellArg cfg.remote}" "${lib.strings.escapeShellArg cfg.path}"
              fi
            '';
      in
      {
        inherit (cfg) enable;
        serviceConfig.Type = "simple";
        after = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        description = "gitwatch for ${name}";
        path =
          with pkgs;
          [
            gitwatch
            git
            openssh
            coreutils
            flock
          ]
          ++ lib.optionals pkgs.stdenv.isLinux [ inotify-tools ]
          ++ lib.optionals pkgs.stdenv.isDarwin [ fswatch ];
        script = ''
          ${fetcher}
          ${logLineLengthEnv} gitwatch ${allArgs}
        '';
        serviceConfig.User = cfg.user;
      }
    );
in
{
  options.services.gitwatch = lib.mkOption {
    description = ''
      A set of git repositories to watch for.
      See
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
        verbose = false;
        quiet = true;
        disableLocking = false;
        logLineLength = 100;
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
    type =
      with lib.types;
      attrsOf (submodule {
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
          quiet = lib.mkOption {
            description = "If true, suppress all stdout/stderr output (-q). Overrides 'verbose'.";
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
          # NEW: No-lock option
          disableLocking = lib.mkOption {
            description = "If true, disable file locking and bypass flock dependency check (-n).";
            type = bool;
            default = false;
          };
          sleepTime = lib.mkOption {
            description = "Time in seconds to wait after change detection (-s <secs>).";
            type = nullOr (oneOf [
              str
              int
            ]);
            default = null;
          };
          timeout = lib.mkOption {
            description = "Timeout in seconds for critical Git operations (commit, pull, push) (-t <secs>).";
            type = nullOr (oneOf [
              str
              int
            ]);
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
            type = nullOr (oneOf [
              str
              int
            ]);
            default = null;
          };
          logLineLength = lib.mkOption {
            description = "Set max line length for -l/-L commit logs (GW_LOG_LINE_LENGTH).";
            type = nullOr (oneOf [
              str
              int
            ]);
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
  config.systemd.services = lib.mapAttrs' mkSystemdService config.services.gitwatch;
}
