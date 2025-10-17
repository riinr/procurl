{ pkgs, ...}:
{
  # Name your shell environment
  devshell.name = "proccurl";

  # create .gitignore
  files.gitignore.enable = true;
  # copy contents from https://github.com/github/gitignore
  # to our .gitignore
  files.gitignore.template."Global/Archives" = true;
  files.gitignore.template."Global/Backup"   = true;
  files.gitignore.template."Global/Diff"     = true;
  files.gitignore.pattern."*\n!/**/\n!*.*"   = true;

  # install a packages
  packages = [
    pkgs.curlFull.out
    "nim2"
    "binutils"
  ];

  # configure direnv .envrc file
  files.direnv.enable = true;

  files.alias.docs = ''
    # Compiles all docs
    find $PRJ_ROOT/src/proccurl/ -maxdepth 1 -name '*.nim' \
     -execdir nim doc {} \;
  '';

  files.alias.benchc = ''
    # Compiles all benchmarks
    find $PRJ_ROOT/bench -maxdepth 1 -name '*.nim' \
     -execdir nim c \
       --mm:arc \
       --passC:"-march=native" \
       -d:boring.benchruns:''${1:-50} \
       -d:boring.benchslots:''${2:-5} \
       -d:release  \
       -d:danger   \
       --opt:speed \
       {} \;
  '';
  files.alias.benchr = ''
    # Run all benchmarks
    for i in $(find $PRJ_ROOT/bench -maxdepth 1 -type f -executable); do
      echo $i
      $i
    done
  '';
  files.alias.ipcs = ''
    # Compile and RUN IPC main command as Server
    rm -rf /tmp/ipc-*.mmap
    nim c -o:/tmp/proccurl-ipc-main $PRJ_ROOT/src/proccurl/ipc.nim && \
      /tmp/proccurl-ipc-main 08x32 08x32
  '';
  files.alias.ipcc = ''
    # RUN IPC main command as Client (server must be running)
    /tmp/proccurl-ipc-main 08x32 08x32 /tmp/ipc-*.mmap
  '';
  files.alias.build = ''
    # BUILD proccurl
    nim c -d:nimDebugDlOpen -o:bin/proccurl src/proccurl.nim
  '';
  env = [
    { name = "LD_LIBRARY_PATH"; prefix = "${pkgs.curlFull.out}/lib";}
    { name = "PKG_CONFIG_PATH"; prefix = "${pkgs.curlFull.out}/lib/pkgconfig";}
  ];
}
