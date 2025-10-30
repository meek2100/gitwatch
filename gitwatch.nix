{
  runCommandNoCC,
  lib,
  makeWrapper,

  git,
  openssh,
  inotify-tools,
  flock,
  coreutils,
}:
runCommandNoCC "gitwatch"
  {
    nativeBuildInputs = [ makeWrapper ];
  }
  ''
    mkdir -p $out/bin
    dest="$out/bin/gitwatch"
    cp ${./gitwatch.sh} $dest
    chmod +x $dest
    patchShebangs $dest

    wrapProgram $dest \
      --prefix PATH ';'
      ${lib.makeBinPath [
        git
        inotify-tools
        openssh
        flock
        coreutils
      ]}
  ''
