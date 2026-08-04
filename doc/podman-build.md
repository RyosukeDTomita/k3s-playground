# Nixを使わずPodmanでイメージを作る

`flake.nix`のNixビルドと比較するため、Podmanだけで同じアプリのイメージを作って
サイズを測った記録。

---

## 3構成の比較

| 構成 | ベースイメージ | イメージサイズ | バイナリ |
|---|---|---|---|
| Nix `dockerTools.buildLayeredImage` | なし(distroless) | **3.25MB** | 3.2MB |
| Podman `Containerfile.musl-static` | `scratch`(distroless) | 28.9MB | 28.9MB |
| Podman `Containerfile.glibc-dynamic` | `debian:bookworm-slim` | 91.6MB | 13.7MB |

3構成とも動作は同じ(`{"message":"Hello, Cloud Native!","pod":"..."}`を返す)。

イメージサイズの内訳が構成ごとに違う点に注意する。glibc動的版はイメージの大半
(77.9MB)がdebian-slimのベースイメージで、バイナリ自体は13.7MBと3つの中で最も小さい。
共有ライブラリを埋め込まないためで、その代わりベースイメージが必要になる。
musl静的版はベースが0でバイナリ1個だけだが、そのバイナリにlibc等が入るので28.9MBある。

### distroless度はNix版とPodman musl静的版で同等

`FROM scratch`はこれ以上ないほどdistrolessで、Nix版に劣らない。
`podman export | tar -tv`で中身を並べると、むしろPodman版のほうが
ディレクトリエントリすら無いぶんファイル数は少ない。

```
=== Podman musl-static ===
-rwxr-xr-x 28929576  hello-cloud-native

=== Nix版 ===
drwxr-xr-x        0  nix/
drwxr-xr-x        0  nix/store/
dr-xr-xr-x        0  nix/store/34b5...-hello-cloud-native-static-.../
dr-xr-xr-x        0  nix/store/34b5.../bin/
-r-xr-xr-x  3226176  nix/store/34b5.../bin/hello-cloud-native
```

どちらもシェルなし、libcなし、パッケージマネージャなし、`/etc`もない。
違いはNixがバイナリを`/nix/store/<hash>/bin/`という階層に置いていることだけ。

つまりdistroless化はPodman版でも達成済みで、それが91.6MB -> 28.9MBの正体。
残る28.9MB -> 3.2MBはdistrolessとは無関係で、バイナリ内部の未使用コードの話になる。

---

## 誤解しやすい点

### 静的リンクはバイナリを小さくしない

効果は逆向きで、静的リンクするとバイナリは**大きくなる**。

| | バイナリ | イメージ |
|---|---|---|
| glibc動的 | 13.7MB | 91.6MB |
| musl静的 | 28.9MB | 28.9MB |

動的リンク版のほうがバイナリは半分以下。libcもGMPも外部に置いているため。
静的リンクでイメージが軽くなるのは、共有ライブラリを供給するOSが不要になり
ベースイメージ(77.9MB)が丸ごと消えるから。「バイナリを小さくする技術」ではなく
「OSを不要にする技術」と捉えるとよい。

### GHC本体は成果物に入らない

コンパイラであるGHCがバイナリやイメージに含まれることはない。入るのは以下の2つ。

- RTS: GC・スケジューラ等のCコード。GHCでコンパイルした全バイナリに埋め込まれる
  (`doc/build.md`参照)
- boot library: `base`/`ghc-prim`/`bytestring`等のうち実際にリンクされた部分

`justStaticExecutables`の`disallowGhcReference`は「バイナリにGHCのstore pathへの
参照が残っていないか」を検査するもの。参照が残るとNixのクロージャがGHCを
引きずり込むのでそれを防いでいる。バイナリにGHCを埋め込む話ではない。

### muslにソースビルドは不要

musl静的リンク自体はghcupの配布バイナリでできる(本ドキュメントの成果物がそれ)。
nixpkgsのソースビルドが効いているのはmuslのためではなく`split_sections`のため。

### 2段階で効いている

- 静的リンクで91.6MB -> 28.9MB(OSを消した)。Podmanで再現できる
- split_sectionsで28.9MB -> 3.2MB(死蔵コードを消した)。Nix側の体制に依存する

---

## musl静的リンクはNix固有ではない

musl静的リンクは`pkgsStatic`のようなNixの機能に依存しない。必要なのは以下の2つで、
これらは直交する別々の軸になっている。

| 軸 | 決まる場所 |
|---|---|
| 静的リンク | GHCオプション`-optl-static`(リンカに`-static`を渡す) |
| musl | ビルド環境側(muslビルドのGHC bindist + muslのlibc) |

`-optl-static`は「共有ライブラリではなく`.a`をリンクしろ」と言っているだけで、
どのlibcの`.a`を使うかは環境が決める。Debian上で`-optl-static`を付ければ
glibc静的バイナリになる(glibcは`getaddrinfo`等が実行時に`dlopen`を要求するため
完全静的を公式に推奨していない)。

muslの側はalpineベースイメージが担う。ghcupはalpineを検出して自動でmusl版
bindistを取ってくる:

```
downloading: https://downloads.haskell.org/~ghc/9.12.2/ghc-9.12.2-x86_64-alpine3_20-linux.tar.xz
downloading: .../cabal-install-3.16.1.0-x86_64-linux-musl-static.tar.xz
```

このalpine版GHCはRTSもboot libraryも全てmuslに対してコンパイル済みで、ここが
「muslである」ことの実体。GHCのフラグでは切り替えられない。

なお最終イメージにalpineは残らない。多段ビルドでalpineはビルド用の一時コンテナ
としてだけ使い、最終段は`FROM scratch`にしている。

---

## Nix版が8.9倍小さい理由

### まず何がサイズを占めているか

`size -A`でセクション別に比較する。どちらもmusl静的リンク済みのバイナリ同士。

| セクション | Nix | Podman | 差 |
|---|---|---|---|
| `.text`(機械語) | 2,526,500 | 24,710,958 | **+22.2MB** |
| `.data` | 320,924 | 3,295,504 | +3.0MB |
| `.rodata` | 299,699 | 830,716 | +0.5MB |
| その他 | 約84KB | 約101KB | +17KB |
| 合計 | 3,231,398 | 28,938,508 | +25.7MB |

`.text`だけで差の86%、`.text` + `.data`で98%を占める。`.data`にはHaskellのinfo tableや
静的クロージャが入るので実質コードの随伴物。つまり差の正体は**未使用関数の機械語が
まるごと残っていること**、それだけ。

muslもlibcもGMPも両方に同じだけ入っているので、この差には寄与していない。
「Nixだけ異常に軽い」のではなく「Podman版が未使用コードを捨てられていない」が正しい。

### なぜ捨てられないか

差はmusl/staticの有無ではない。Podman版も`file`で`statically linked`と出ており、
そこは再現できている。効いているのは**split-sectionsが3層すべてで有効かどうか**。

nixpkgsは以下をやっている。

### 1. GHC本体とboot libraryをsplit_sectionsでビルドしている

`pkgs/development/compilers/ghc/common-hadrian.nix:121`:

```nix
++ (if stdenv.targetPlatform.isWindows then [ "no_split_sections" ] else [ "split_sections" ]);
```

これが最大の要因。`base`/`ghc-prim`/`bytestring`等はGHCに同梱されており、それらが
split-sections付きでコンパイルされていないと、リンカの`--gc-sections`は未使用コードを
落とせない。セクションが関数単位に分かれていなければ捨てる粒度がないため。

`libHSbase.a`の`.text.*`セクション数を`objdump -h`で数えると差は歴然:

| GHC | `.text.*`セクション数 |
|---|---|
| 公式alpine bindist(ghcup) | **0** |
| Nix `pkgsStatic` | **7,083** |

### 2. 依存Haskellパッケージ全てに適用される

`pkgs/development/haskell-modules/generic-builder.nix:421`:

```nix
(enableFeature enableDeadCodeElimination "split-sections")
```

`enableDeadCodeElimination`はLinuxならデフォルトtrue(同`:133`)。

### 3. stripが有効

同`:422-423`:

```nix
(enableFeature (!dontStrip) "library-stripping")
(enableFeature (!dontStrip) "executable-stripping")
```

### justStaticExecutablesはバイナリではなくクロージャを削る

`pkgs/development/haskell-modules/lib/compose.nix:458-469`を見ると、これはバイナリを
小さくする関数ではない:

```nix
enableSharedExecutables = false;
isLibrary = false;
doHaddock = false;
postFixup = ... rm -rf $out/lib $out/nix-support $out/share/doc
disallowGhcReference = true;
```

削っているのはクロージャ、つまりイメージに同梱されるファイル群。
`disallowGhcReference`でGHC本体への参照が残っていればビルドを失敗させ、
`rm -rf $out/lib`で他のstore pathへのリンクを持ちうるディレクトリを消す。
`doc/build.md`のlibdw->elfutils->curlの連鎖を断つのがこれ。

### 整理

| 効果 | 担当 |
|---|---|
| バイナリ自体を小さく(3.2MB) | 1〜3のsplit-sections + strip |
| イメージ内のファイルを1個に | musl静的リンク + justStaticExecutables |

Podman側で再現できるのは2と3だけ。1はghcupが配布する公式bindistの
ビルド設定なので、こちらから制御できない。nixpkgsがGHCを自前でビルドしている
ことの効き目がここに出ている。

裏返すと、ghcupでもGHCをソースからhadrianの`split_sections`付きでビルドすれば
同じ結果になるはず。ただし数時間かかる(READMEのcachixキャッシュの話はまさに
そのコストのため)。Nixが軽いことの実体は「全部ソースからビルドする体制だから
コンパイラのビルドフラグまで選べる」という点にあり、Nix固有の魔法ではない。

### この話はドキュメントに書かれているか

ほぼ書かれていない。

- **dockerToolsのドキュメント**: `doc/build-helpers/images/dockertools.section.md`は
  `maxLayers`や`streamLayeredImage`といったイメージ構築の仕組みの話だけで、
  バイナリが小さい理由には触れていない。`doc/`ツリー全体を
  `split.sections|DeadCodeElimination`でgrepしてもヒットは1件だけで、
  それもdockerTools側ではなくHaskellのページ。
- **`doc/languages-frameworks/haskell.section.md:292`**: その1件がこれで、記述は3行。
  サイズへの影響量にも、GHC本体がsplit_sections付きでビルドされていることにも
  言及がない。

  > `enableDeadCodeElimination`
  > : Whether to enable linker based dead code elimination in GHC.
  > Enabled by default if supported.

- **同`:909-915`の`justStaticExecutables`**: こちらは明示的に
  「This dramatically reduces the **closure size** of the resulting derivation」と
  書いてあり、binary sizeではなくclosure sizeだと明記されている。さらに
  「executables are only statically linked against their Haskell dependencies, but
  will still link dynamically against libc, GMP」ともあり、`pkgsStatic`を使わない
  通常経路ではlibcは動的のままだと分かる。

イメージが小さくなること自体はnixpkgsのビルド方針から生まれる創発的な性質で、
オプション1行の説明としてしか文書化されていない。GHCをsplit_sections付きで
ビルドしている件はソースを読まないと分からない。

---

## 実測: 何が効いて何が効かなかったか

musl静的版のバイナリサイズ(バイト):

| 条件 | サイズ | 差分 |
|---|---|---|
| 素の`cabal build` | 45,728,264 | — |
| `strip`のみ | 28,929,640 | **-16.8MB** |
| `strip` + `-split-sections` | 28,929,576 | -64バイト |
| `strip` + `-split-sections` + `-optl-Wl,--gc-sections` | 28,929,576 | 0(バイト単位で同一) |

- **stripは効く**。45.7MB->28.9MBで、これが唯一の大きな削減。
- **`-split-sections`はほぼ無意味**。依存パッケージが再コンパイルされている
  (ビルドログで確認)にもかかわらず64バイトしか変わらない。
- **`--gc-sections`を明示しても1バイトも変わらない**。リンカフラグが渡っていない
  のが原因ではなく、boot library側にセクションが分かれていないため落とせるものが
  無い、という上記の結論を裏付ける。

---

## ハマった点

### ncurses-staticだけではGHCが起動しない

alpineに`ncurses-static`(`.a`のみ)を入れてもGHCコンパイラ自体が起動しない:

```
Error loading shared library libncursesw.so.6: No such file or directory
  (needed by /opt/.ghcup/ghc/9.12.2/lib/ghc-9.12.2/bin/./ghc-9.12.2)
```

GHC本体がhaskeline/terminfo経由で`libncursesw.so.6`を動的に必要とするため、
共有ライブラリの`ncurses-libs`も要る。「生成物を静的にする話」と「コンパイラを
動かす話」は別物という例。

### debianにはUID 65534が既にいる

glibc版で`useradd --uid 65534`すると`UID 65534 is not unique`で失敗する。
debianには最初から`nobody`(65534)がいるので、ユーザー作成はせず`USER 65534:65534`と
数値で指定するだけでよい。

---

## 使い方

```shell
# musl静的 + scratch
podman build -f Containerfile.musl-static -t hello-cloud-native:musl-static .

# glibc動的 + debian-slim
podman build -f Containerfile.glibc-dynamic -t hello-cloud-native:glibc-dynamic .

podman images | grep hello-cloud-native
```

動作確認:

```shell
podman run --rm -d --name test -p 18080:8080 hello-cloud-native:musl-static
curl http://localhost:18080/
podman stop test
```
