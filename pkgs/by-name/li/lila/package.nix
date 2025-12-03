{
  fetchFromGitHub,
  sbt-with-scala-native,
  jdk21,
  makeWrapper,
  stdenv,
  lib,
  nixosTests,
  gawk,
}:

let
  # Shadow assigment so we only need to change this in one spot
  jdk = jdk21;

  # Phase 1: Dependencies (fixed output derivation with network access)
  lila-deps = stdenv.mkDerivation {
    pname = "lila-dependencies";
    version = "unstable-2025-11-29";

    src = fetchFromGitHub {
      owner = "lichess-org";
      repo = "lila";
      rev = "2f13798d82fd48a64be929f63bbb3acd9ca1eeb0";
      hash = "sha256-dNrSm3fr6gzWHnlhLHjtYoZMKKmFleaoCDxTe/ylgh4=";
    };

    nativeBuildInputs = [
      sbt-with-scala-native
      jdk
    ];

    buildPhase = ''
      runHook preBuild

      export HOME=$TMPDIR

      # Increase heap size to be large enough to compile this project
      export SBT_OPTS="-Xmx4G -Xss4M -XX:MaxMetaspaceSize=1G"
      export JAVA_OPTS="-Xmx4G -Xss4M"

      sbt compile

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out

      cp -r $HOME/.ivy2 $out/ivy
      cp -r $HOME/.sbt $out/sbt
      cp -r $HOME/.cache $out/cache

      runHook postInstall
    '';

    # Configure the derivation to have a fixed output
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-nMJVbeV9kPiB5BHWMpxBx+fpVPx5oX2S7p3JVRzrQIs=";
  };
in
# Phase 2: Use pre-fetched dependencies (no network access)
stdenv.mkDerivation (finalAttrs: {
  pname = "lila";
  version = "unstable-2025-11-29";

  nativeBuildInputs = [
    sbt-with-scala-native
    jdk
    makeWrapper
  ];

  src = fetchFromGitHub {
    owner = "lichess-org";
    repo = "lila";
    rev = "2f13798d82fd48a64be929f63bbb3acd9ca1eeb0";
    hash = "sha256-dNrSm3fr6gzWHnlhLHjtYoZMKKmFleaoCDxTe/ylgh4=";
  };

  preBuild = ''
    export HOME=$TMPDIR
    cp -r ${lila-deps}/ivy $HOME/.ivy2
    cp -r ${lila-deps}/sbt $HOME/.sbt
    cp -r ${lila-deps}/cache $HOME/.cache

    # Make the copied directories writable
    chmod -R u+w $HOME/.ivy2
    chmod -R u+w $HOME/.sbt
    chmod -R u+w $HOME/.cache
  '';

  buildPhase = ''
    runHook preBuild

    export SBT_OPTS="-Xmx4G -Xss4M -XX:MaxMetaspaceSize=1G"
    export JAVA_OPTS="-Xmx4G -Xss4M"

    sbt stage

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    mkdir -p $out/share/lila
    mkdir -p $out/share/lila/conf.examples

    # Copy the staged application
    cp -r target/universal/stage/* $out/share/lila/

    # Copy example configs (for reference, not used directly by the wrapper)
    cp -r ${finalAttrs.src}/conf/* $out/share/lila/conf.examples/

    # Make the binary executable
    chmod +x $out/share/lila/bin/lila

    # Create wrapper script that uses the correct Java version
    # Config files should be provided via command-line args or by the NixOS module
    makeWrapper $out/share/lila/bin/lila $out/bin/lila \
      --set JAVA_HOME ${jdk} \
      --prefix PATH : ${lib.makeBinPath [ jdk gawk ]}

    runHook postInstall
  '';

  passthru.tests = {
    inherit (nixosTests) lila;
  };

  meta = with lib; {
    description = "Free online chess game server for lichess.org";
    homepage = "https://github.com/lichess-org/lila";
    license = licenses.agpl3Plus;
    maintainers = with maintainers; [
      dolphindalt
    ];
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    mainProgram = "lila";
  };
})
