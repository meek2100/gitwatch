{
  runCommandNoCC,
  lib,
  makeWrapper,

  git,
  openssh,
  inotify-tools,
<<<<<<< HEAD
  flock,
  coreutils,
  procps,
=======
>>>>>>> master
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
<<<<<<< HEAD
      --prefix PATH ':' ${
=======
      --prefix PATH ';' ${
>>>>>>> master
        lib.makeBinPath [
          git
          inotify-tools
          openssh
<<<<<<< HEAD
          flock
          coreutils
          procps
=======
>>>>>>> master
        ]
      }
  ''
