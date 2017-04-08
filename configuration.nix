{ config ? null, pkgs ? null, ... }:

with pkgs.stdenv.lib; {
  imports = [ /etc/nixos/hardware-configuration.nix ];

  nixpkgs.config = {
    packageOverrides = pkgs: with pkgs.stdenv.lib;
      let

        libdrm = pkgs.libdrm.overrideAttrs(attrs: rec {
          name = "libdrm-2.4.79";
          src = pkgs.fetchurl {
            url = "http://dri.freedesktop.org/libdrm/${name}.tar.bz2";
            sha256 = "15xiwnicf7vl1l37k8nj0z496p7ln1qp8qws7q13ikiv54cz7an6";
          };
        });

        mesa = ((pkgs.mesa_noglu.override {
          # this is probably the default by now in nixpkgs
          # without it you get opengl 2.1 contexts
          enableTextureFloats = true;
          enableRadv = true; # this isn't really needed when setting 'vulkanDrivers'
          galliumDrivers = [ "radeonsi" ];
          driDrivers = [ "radeon" ];
          vulkanDrivers = [ "radeon" ];
          llvmPackages =
            let
              rev = "299814";
              fetch = name: sha256: pkgs.fetchsvn {
                url = "http://llvm.org/svn/llvm-project/${name}/trunk/";
                inherit rev sha256;
              };
              src = fetch "llvm" "0x5l9ryr209wpmcrkb5yn35g88sfvwswljd0k9q6ymyxh3hrydw9";
              compiler-rt_src = fetch "compiler-rt" "0smfm4xw0m8l49lzlqvxf0407h6nqgy0ld74qx8yw7asvyzldjsl";
            in {
              llvm = pkgs.llvmPackages_4.llvm.overrideAttrs(attrs: {
                name = "llvm-git";
                unpackPhase = ''
                  unpackFile ${src}
                  chmod -R u+w llvm-*
                  mv llvm-* llvm
                  sourceRoot=$PWD/llvm
                  unpackFile ${compiler-rt_src}
                  chmod -R u+w compiler-rt-*
                  mv compiler-rt-* $sourceRoot/projects/compiler-rt
                '';
                # this was the quickest hack to deal with the existing postPatch
                # script deleting these files later on
                postPatch = ''
                  touch test/CodeGen/AMDGPU/invalid-opencl-version-metadata1.ll
                  touch test/CodeGen/AMDGPU/invalid-opencl-version-metadata2.ll
                  touch test/CodeGen/AMDGPU/invalid-opencl-version-metadata3.ll
                  touch test/CodeGen/AMDGPU/runtime-metadata.ll
                '' + attrs.postPatch;
            });
          };
          libdrm = libdrm;
        }).overrideAttrs(attrs: {
          name = "mesa-git";
          src = pkgs.fetchgit {
            url = "https://anongit.freedesktop.org/git/mesa/mesa.git";
            rev = "098ca9949db35cbad92728b5d216aa37685b33ba";
            sha256 = "1pw2ymphmpxyjqk141vx2wxmkgh2scd3wdfkzwj0ggdf9jwl7fvm";
          };
          # this nixpkg version of this patch didn't apply cleanly
          # we should probably find a less fragile way of doing this
          patches = [ ./mesa-symlink-drivers.patch ];
          nativeBuildInputs = attrs.nativeBuildInputs ++ [ pkgs.bison pkgs.flex ];
        }));

      in {
        steam = pkgs.steam.override {
          # still needed?
          newStdcpp = true;
        };
        xorg = pkgs.xorg // {
          xorgserver = pkgs.xorg.xorgserver.override {
            libdrm = libdrm;
            mesa = mesa;
          };
          xf86videoamdgpu = pkgs.xorg.xf86videoamdgpu.override {
            libdrm = libdrm;
            mesa = mesa;
          };
        };
        mesa_drivers = mesa.drivers;
      };
  };

  boot.kernelPackages = pkgs.linuxPackages_testing;

  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.device = "nodev";

  hardware.opengl.driSupport32Bit = true; # needed for steam
  hardware.opengl.s3tcSupport = true; # use patented texture compressor

  services.xserver = {
    enable = true;
    videoDrivers = [ "amdgpu" ];
  };

}
