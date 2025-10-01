{
  inputs = {
    utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, utils}: utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs{
      		inherit system;
  		config = {
    			allowUnfree = true;
    			cudaSupport = true;
    			cudaCapabilities = [ "7.2" "8.7" ];
  		};
	};
      vaccel = pkgs.gcc13Stdenv.mkDerivation {
	src = pkgs.fetchgit {
		name="test";
		url = "https://github.com/TUM-DSE/vaccel";
		rev = "5d919a5366cc5ab06de7e24964f11389d7f96477";
		# TODO: Figure out why the hashes change
		hash = "sha256-RQk7IcH9Twf2zcggCrnd2PT5IcBJLDfGMdtqaRftPFw="; #if pkgs.stdenv.hostPlatform.isAarch then "sha256-Z6bfI2FQ2QpVusQpUE23errywPj20DIbTSAKh0qO1L4=" else "sha256-BfvdbdsCdgPso99s4A1BkSSp9dSKApqeTwMs7KpEa44=";
		fetchSubmodules = true;
		postFetch=''
			cd "$out"

      			export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt


     			${nixpkgs.lib.getExe pkgs.meson} subprojects download
			find subprojects -type d -name .git -prune -execdir rm -r {} +
		'';
	};
	buildInputs = with pkgs; [
		git
		ninja
		meson
		pkg-config	];

	preConfigure=''
		substituteInPlace meson.build --replace "git submodule update --init >/dev/null && " ""
		echo "0.7.1-99">.version
	'';
	name = "vAccel";
      };
      myqemu = pkgs.qemu.overrideAttrs(finalAttrs: previousAttrs: { 
      	version = "9.1.0-rc3"; 
	src = pkgs.fetchurl {
   		url = "https://download.qemu.org/qemu-${finalAttrs.version}.tar.xz";
    		hash = "sha256-YLsH0tZQEWdRfFLLdxJTDSEuDkWFakFGRlnbuXGmX/0=";
  	};
	# TODO switch to seperate repo
	patches = previousAttrs.patches ++ [./test.patch ./Allow_vAccel_legacy_device.patch];
	doCheck=false;
	buildInputs=previousAttrs.buildInputs ++ [vaccel];
	configureFlags = [
		"--disable-strip" # We'll strip ourselves after separating debug info.
		"--localstatedir=/var"
		"--sysconfdir=/etc"
		"--enable-virtfs"
	]
	++ nixpkgs.lib.optionals pkgs.stdenv.hostPlatform.isAarch [ "--target-list=aarch64-softmmu" ]
	++ nixpkgs.lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [ "--target-list=x86_64-softmmu" ];
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
                nativeBuildInputs = with pkgs; with pkgs.cudaPackages; [
                        cmake
                        autoAddDriverRunpath
                        cuda_nvcc
                ];
                buildInputs = with pkgs; with pkgs.cudaPackages; [
                                (nixpkgs.lib.getDev libcublas)
                                (nixpkgs.lib.getLib libcublas)
                                (nixpkgs.lib.getOutput "static" libcublas)
                                cuda_cudart
                                cuda_cccl
                                vaccel
                        ];
                cmakeFlags = [
                        (nixpkgs.lib.cmakeBool "CMAKE_VERBOSE_MAKEFILE" true)
                        (nixpkgs.lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" pkgs.cudaPackages.flags.cmakeCudaArchitecturesString)
                ];
        };
        vaccel-plugins-matmul = pkgs.stdenv.mkDerivation {
                name = "vaccel-plugins-matmul";
                src = ../vaccel_plugins;
                nativeBuildInputs = with pkgs; with pkgs.cudaPackages; [
                        cmake
                        autoAddDriverRunpath
                        cuda_nvcc
                ];
                buildInputs = with pkgs; with pkgs.cudaPackages; [
                                (nixpkgs.lib.getDev libcublas)
                                (nixpkgs.lib.getLib libcublas)
                                (nixpkgs.lib.getOutput "static" libcublas)
                                cuda_cudart
                                cuda_cccl
                                vaccel
                        ];
                cmakeFlags = [
                        (nixpkgs.lib.cmakeBool "CMAKE_VERBOSE_MAKEFILE" true)
                        (nixpkgs.lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" pkgs.cudaPackages.flags.cmakeCudaArchitecturesString)
                ];
        };

    in
    {
      devShell = (pkgs.mkShell.override { stdenv = pkgs.gcc13Stdenv; }) {
        buildInputs = with pkgs; [
		gcc13
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
	] ++ nixpkgs.lib.optionals pkgs.stdenv.hostPlatform.isAarch [ libsaxpy-vaccel vaccel-plugins-matmul ];

	VACCEL_PLUGINS= nixpkgs.lib.optionalString pkgs.stdenv.hostPlatform.isAarch "${vaccel-plugins-matmul}/lib/libcuda.so";
	VACCEL_PLUGINS_CUDA= nixpkgs.lib.optionalString pkgs.stdenv.hostPlatform.isAarch "${vaccel-plugins-matmul}/lib/libcuda.so";
	VACCEL_PLUGINS_RKNN= nixpkgs.lib.optionalString pkgs.stdenv.hostPlatform.isAarch "${vaccel-plugins-matmul}/lib/librknn.so";
	VACCEL_PLUGINS_SAXPY= nixpkgs.lib.optionalString pkgs.stdenv.hostPlatform.isAarch "${libsaxpy-vaccel}/lib/libsaxpy.so";
      };
    }
  );
}
