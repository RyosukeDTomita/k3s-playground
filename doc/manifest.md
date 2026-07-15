# このリポジトリのmanifest関連

manifests/service.yaml:14-18 を見ると、1つの Service に3つのポートが定義されています:

ports:
  - name: http
    port: 80         # ← ClusterIP(クラスタ内部)で受けるポート
    targetPort: 8080 # ← コンテナ側のポート
    nodePort: 30080  # ← ノード(ホスト)側のポート

流れを図にするとこう:

ブラウザ  →  localhost:30080  →  ClusterIP:80  →  Pod/コンテナ:8080
             (nodePort)         (port)           (targetPort)
             ホスト側の入口      クラスタ内の入口   実際のアプリ

- 8080 = アプリが実際に listen してるポート。deployment.yaml:28,31 の containerPort: 8080 / PORT="8080"、Service では targetPort: 8080。「コンテナ=80」ではなく 8080 です。
- 80 = Service の ClusterIP としての窓口ポート (port: 80)。クラスタ内の他 Pod が hello-cloud-native:80 で呼ぶときに使う。外からは関係ない。
- 30080 = type: NodePort なので、ホスト(ノード)側に開くポート。service.yaml:2 のコメント通り「ノードの30080番からアクセスできる」。

なぜ 30080 なのかというと、NodePort が使える範囲がデフォルトで 30000–32767 に制限されているからです。
