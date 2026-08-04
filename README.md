# k3s-playground

k3sで遊ぶためのplayground。HaskellバックエンドをNixでビルドし、distrolessなコンテナイメージとしてk3sにデプロイする。

## ENVIRONMENT

- Nix(flakes有効)が必要。
- [Install k3s](https://k3s.io/)

```shell
curl -sfL https://get.k3s.io | sh -
# Check for Ready node, takes ~30 seconds
sudo k3s kubectl get node
```

### Haskell App

`app/Main.hs`: wai/warpで書いたHTTPサーバー。どのパスにも`{"message":"Hello, Cloud Native!","pod":"<Pod名>"}`をJSONで返す。`pod`は`HOSTNAME`環境変数(k8sではPod名が入る)から取るので、どのレプリカが応答したか確認できる。ポートは`PORT`環境変数で指定(デフォルト8080)。

---

## For Developer

### Format

```shell
nix fmt
```

### Build

imageサイズを小さくするため、musl完全静的バイナリをGHCで作成し、distrolessコンテナに配置している。

```shell
# distrolessコンテナイメージ(tar.gz)
# `nix build`が作るresult(バイナリのディレクトリ)と出力リンクが衝突しないよう-oで別名にする
nix build .#image -o result-image
```

初回の`nix build .#static`はmusl版GHCのソースビルドが走り数時間かかる。同じnixpkgs pinを使っている[acac-cli](https://github.com:RyosukeDTomita/acac-cli)のcachixキャッシュを設定すると大幅に短縮できる:

```shell
sudo sh -c 'printf "extra-substituters = https://acac.cachix.org\nextra-trusted-public-keys = acac.cachix.org-1:7lo6nw1q5Gp7yrgFU1GKjWCyxtPX0gcqUjxR21FDL10=\n" >> /etc/nix/nix.conf && systemctl restart nix-daemon'
```

#### (Nixを使わないビルドとのサイズ比較)

比較用にPodmanだけで同じアプリのイメージを作れる。`Containerfile.musl-static`が
musl静的 + `scratch`、`Containerfile.glibc-dynamic`がglibc動的 + debian-slim。

```shell
podman build -f Containerfile.musl-static -t hello-cloud-native:musl-static .
podman build -f Containerfile.glibc-dynamic -t hello-cloud-native:glibc-dynamic .
```

| 構成 | イメージサイズ |
|---|---|
| Nix `dockerTools.buildLayeredImage` | 3.25MB |
| Podman musl静的 + `scratch` | 28.9MB |
| Podman glibc動的 + debian-slim | 91.6MB |

musl静的リンク自体はNix固有ではなくPodmanでも再現できる。Nix版がさらに8.9倍
小さいのは、nixpkgsがGHC本体とboot libraryを`split_sections`付きでビルドしていて
未使用コードを落とせるため。詳細は[doc/podman-build.md](doc/podman-build.md)。

### (コンテナイメージの動作確認)

k3sに載せる前に軽く動作確認するためにpodmanを使う

```shell
nix build .#image -o result-image
podman load < result-image
podman run --rm -p 8080:8080 hello-cloud-native:latest
curl http://localhost:8080/
# {"message":"Hello, Cloud Native!","pod":"<コンテナのホスト名>"}
```

podmanはロード時にイメージ名を`docker.io/library/hello-cloud-native:latest`のような完全修飾名に正規化することがある。短縮名で見つからないときは`podman images`で実際の名前を確認する。


### k3sへのデプロイ

`manifests/`のマニフェストでデプロイする。

- `manifests/deployment.yaml`: Deployment(2レプリカ)。importしたローカルイメージを使うため`image: docker.io/library/hello-cloud-native:latest`(containerd内部の正規化名)+`imagePullPolicy: Never`を指定している。
- `manifests/service.yaml`: Service(NodePort 30080)。ノードの30080→ClusterIP 80→コンテナ8080に流れる。

ビルドからデプロイまでの一連の流れ:

```shell
# 1. イメージをビルド(すでにあれば不要)
nix build .#image -o result-image

# 2. k3s(containerd)にimport
zcat result-image | sudo k3s ctr images import -
sudo k3s crictl images | grep hello-cloud-native

# 3. マニフェストを適用
sudo k3s kubectl apply -f manifests/
sudo k3s kubectl get pods -l app=hello-cloud-native
```


数回叩くとpodの値が変わり、Serviceが2レプリカに振り分けているのが見える

```shell
# -w '\n'でリクエストごとに改行を入れる
for i in $(seq 5); do curl -s -w '\n' http://localhost:30080; done
```

### (アプリ修正時の更新)

再ビルド+再import後にPodを作り直させる(タグが`latest`のままなのでrestartしないと新イメージにならない):

```shell
nix build .#image -o result-image
zcat result-image | sudo k3s ctr images import -
sudo k3s kubectl rollout restart deployment/hello-cloud-native
```

---

## Clean up

```shell
podman stop -l
podman rmi hello-cloud-native:latest
sudo k3s kubectl delete -f manifests/
sudo systemctl disable --now k3s
```
