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
        appSrc = pkgs.lib.fileset.toSource {
          root = ./.;
          fileset = pkgs.lib.fileset.unions [
            ./hello-cloud-native.cabal
            ./app
          ];
        };
        helloCloudNativeStatic = pkgs.haskell.lib.justStaticExecutables (
          pkgs.pkgsStatic.haskell.packages.ghc9122.callCabal2nix "hello-cloud-native" appSrc { }
        );
      in
      {
        formatter = treefmtEval.config.build.wrapper;

        # `nix build`でmusl静的バイナリを生成する(ローカル動作確認用)。
        packages.default = helloCloudNativeStatic;

        # `nix build .#image`でdistrolessなコンテナイメージ(tar.gz)を生成する。
        # ベースイメージなし: musl静的バイナリ1個だけが入る(シェルなし・glibcなし)。
        packages.image = pkgs.dockerTools.buildLayeredImage {
          name = "hello-cloud-native";
          tag = "latest";
          # イメージの作成日時。デフォルトはUnix epoch(1970-01-01)で
          # `docker images`に"56 years ago"と出るため、ビルド時刻を使う。
          # 注意: "now"にするとビルドごとに出力が変わり再現性は失われる
          #(hash固定を優先するなら"2026-07-16T00:00:00Z"のような固定値にする)。
          created = "now";
          config = {
            Cmd = [ "${helloCloudNativeStatic}/bin/hello-cloud-native" ];
            Env = [ "PORT=8080" ];
            ExposedPorts."8080/tcp" = { };
            # distroless流に非root(nobody)で実行する。
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
