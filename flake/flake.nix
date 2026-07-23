{
  inputs = {utils.url = "github:numtide/flake-utils";};
  outputs = {
    self,
    nixpkgs,
    utils,
  }:
    utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          cudaSupport = true;
          cudaCapabilities = nixpkgs.lib.optionals pkgs.stdenv.hostPlatform.isAarch ["7.2" "8.7"];
        };
      };
      cudaPackages = pkgs.cudaPackages_12_6;
      vaccel = pkgs.gcc13Stdenv.mkDerivation {
        src = pkgs.fetchgit {
          name = "vaccel-src";
          url = "https://github.com/TUM-DSE/vaccel";
          rev = "cc9942e6f5de46ff1f5eb139a208de5998024d64";
          hash = "sha256-r+oPz/6BBQol1+U31hP7J+bfaiU/PvagywzS2HoCNyQ=";
          fetchSubmodules = true;
          postFetch = ''
            cd "$out"
            export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

            ${nixpkgs.lib.getExe pkgs.meson} subprojects download
            find subprojects -type d -name .git -prune -execdir rm -r {} +
          '';
        };
        buildInputs = with pkgs; [git ninja meson pkg-config];

        preConfigure = ''
          substituteInPlace meson.build --replace "git submodule update --init >/dev/null && " ""
          echo "0.7.1-99">.version
        '';
        name = "vAccel";
      };
      myqemu = pkgs.qemu.overrideAttrs (finalAttrs: previousAttrs: {
        version = "9.1.0-rc3";
        src = pkgs.fetchurl {
          url = "https://download.qemu.org/qemu-${finalAttrs.version}.tar.xz";
          hash = "sha256-YLsH0tZQEWdRfFLLdxJTDSEuDkWFakFGRlnbuXGmX/0=";
        };
        # TODO switch to seperate repo
        patches = previousAttrs.patches ++ [./test.patch ./Allow_vAccel_legacy_device.patch];
        doCheck = false;
        buildInputs = previousAttrs.buildInputs ++ [vaccel];
        configureFlags =
          [
            "--disable-strip" # We'll strip ourselves after separating debug info.
            "--localstatedir=/var"
            "--sysconfdir=/etc"
            "--enable-virtfs"
          ]
          ++ nixpkgs.lib.optionals pkgs.stdenv.hostPlatform.isAarch ["--target-list=aarch64-softmmu"]
          ++ nixpkgs.lib.optionals pkgs.stdenv.hostPlatform.isx86_64 ["--target-list=x86_64-softmmu"];
      });
      myqemu-debug = pkgs.enableDebugging (myqemu.overrideAttrs (finalAttrs: previousAttrs: {
        configureFlags = previousAttrs.configureFlags ++ ["--enable-debug"];
        dontStrip = true;
        postFixup =
          previousAttrs.postFixup
          + ''
            find $out/bin -type f -executable ! -name '\.qemu*' -exec mv {} {}-debug \;
            rm $out/bin/qemu-kvm
          '';
      }));
      libsaxpy-vaccel = pkgs.stdenv.mkDerivation {
        name = "libsaxpy-vaccel";
        src = ./src;
        nativeBuildInputs = with pkgs;
        with cudaPackages; [
          cmake
          autoAddDriverRunpath
          cuda_nvcc
        ];
        buildInputs = with pkgs;
        with cudaPackages; [
          (nixpkgs.lib.getDev libcublas)
          (nixpkgs.lib.getLib libcublas)
          (nixpkgs.lib.getOutput "static" libcublas)
          cuda_cudart
          cuda_cccl
          vaccel
        ];
        cmakeFlags = [
          (nixpkgs.lib.cmakeBool "CMAKE_VERBOSE_MAKEFILE" true)
          (nixpkgs.lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" cudaPackages.flags.cmakeCudaArchitecturesString)
        ];
      };
      librknnrt = pkgs.stdenv.mkDerivation {
        name = "librknnrt";
        src = ../vaccel_plugins;
        dontBuild = true;
        installPhase = ''
          mkdir -p $out/lib
          cp librknnrt.so $out/lib/
        '';
      };
      vaccel-plugins-matmul = pkgs.stdenv.mkDerivation {
        name = "vaccel-plugins-matmul";
        src = ../vaccel_plugins;
        nativeBuildInputs = with pkgs;
        with cudaPackages; [
          cmake
          autoAddDriverRunpath
          autoPatchelfHook
          cuda_nvcc
        ];
        buildInputs = with pkgs;
        with cudaPackages; [
          (nixpkgs.lib.getDev libcublas)
          (nixpkgs.lib.getLib libcublas)
          (nixpkgs.lib.getOutput "static" libcublas)
          cuda_cudart
          cuda_cccl
          vaccel
          librknnrt
          stdenv.cc.cc.lib
        ];
        cmakeFlags = [
          (nixpkgs.lib.cmakeBool "CMAKE_VERBOSE_MAKEFILE" true)
          (nixpkgs.lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" cudaPackages.flags.cmakeCudaArchitecturesString)
        ];
      };
      # Paths to the built vAccel plugins, exported so a consuming flake (the
      # top-level lros-expe flake) can splice them into a combined devShell
      # instead of evaluating this flake as a second, separate `use flake`.
      # Guarded by isAarch, so on x86_64 they are empty strings and the plugin
      # derivations are never forced (pure eval stays cheap).
      pluginEnv = {
        VACCEL_PLUGINS_CUDA = nixpkgs.lib.optionalString pkgs.stdenv.hostPlatform.isAarch "${vaccel-plugins-matmul}/lib/libmatmulcuda.so";
        VACCEL_PLUGINS_RKNN = nixpkgs.lib.optionalString pkgs.stdenv.hostPlatform.isAarch "${vaccel-plugins-matmul}/lib/libmatmulrknn.so";
        VACCEL_PLUGINS_SAXPY = nixpkgs.lib.optionalString pkgs.stdenv.hostPlatform.isAarch "${libsaxpy-vaccel}/lib/libsaxpy.so";
      };
      devShell = (pkgs.mkShell.override {stdenv = pkgs.gcc13Stdenv;}) ({
        buildInputs = with pkgs;
          [
            kraft
            myqemu
            myqemu-debug
            gnumake
            pkg-config
            ncurses
            flex
            bison
            unzip
            vaccel

            cmake
            git
          ]
          ++ nixpkgs.lib.optionals pkgs.stdenv.hostPlatform.isAarch [
            libsaxpy-vaccel
            vaccel-plugins-matmul
            librknnrt
          ] ++
         ( with cudaPackages; [
           cuda_nvcc
           cuda_cudart
           cuda_cccl # <nv/target>
           libcublas
         ]);
      } // pluginEnv);
    in {
      inherit devShell pluginEnv cudaPackages pkgs;
      # Modern attribute path; `devShell` is kept above for standalone
      # `nix develop path:lros/flake` back-compat.
      devShells.default = devShell;
    });
}
