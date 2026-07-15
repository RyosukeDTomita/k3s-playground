{
  description = "Haskell backend + distroless container image for k3s playground";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      treefmt-nix,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        hpkgs = pkgs.haskell.packages.ghc9122;
        treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
        # cabal パッケージのソースは Haskell 関連ファイルだけに限定する。
        # README や k8s マニフェスト等を変えてもビルドのハッシュが変わらず、
        # バイナリキャッシュが効き続けるようにするため。
        appSrc = pkgs.lib.fileset.toSource {
          root = ./.;
          fileset = pkgs.lib.fileset.unions [
            ./hello-cloud-native.cabal
            ./app
          ];
        };
        # justStaticExecutables で Haskell ライブラリを静的リンクし、
        # GHC 本体への参照を落としてクロージャを小さくする(glibc 等は動的リンクのまま)。
        helloCloudNative = pkgs.haskell.lib.justStaticExecutables (
          hpkgs.callCabal2nix "hello-cloud-native" appSrc { }
        );
        # musl 完全静的バイナリ。コンテナイメージにはこちらを載せる。
        # glibc 版は GHC RTS が libdw(elfutils)をリンクしていて curl 等まで
        # クロージャに入り66MBになるが、静的ならバイナリ1個で済む。
        helloCloudNativeStatic = pkgs.haskell.lib.justStaticExecutables (
          pkgs.pkgsStatic.haskell.packages.ghc9122.callCabal2nix "hello-cloud-native" appSrc { }
        );
      in
      {
        formatter = treefmtEval.config.build.wrapper;

        # `nix build` で実行バイナリを生成する(ローカル動作確認用)。
        packages.default = helloCloudNative;

        # `nix build .#static` で musl 静的バイナリを生成する。
        packages.static = helloCloudNativeStatic;

        # `nix build .#image` で distroless なコンテナイメージ(tar.gz)を生成する。
        # ベースイメージなし: musl 静的バイナリ1個だけが入る(シェルなし・glibc なし)。
        packages.image = pkgs.dockerTools.buildLayeredImage {
          name = "hello-cloud-native";
          tag = "latest";
          config = {
            Cmd = [ "${helloCloudNativeStatic}/bin/hello-cloud-native" ];
            Env = [ "PORT=8080" ];
            ExposedPorts."8080/tcp" = { };
            # distroless 流に非 root(nobody)で実行する。
            User = "65534:65534";
          };
        };

        devShells.default = pkgs.mkShell {
          packages = [
            treefmtEval.config.build.wrapper
            pkgs.zsh
            (hpkgs.ghcWithPackages (ps: [
              ps.aeson
              ps.wai
              ps.warp
              ps.http-types
            ]))
            hpkgs.haskell-language-server
            pkgs.cabal-install
          ];
        };
      }
    );
}
