# このリポジトリのmanifest関連

## serviceとdeploymentの責務

| | Deployment | Service |
| ----------- | ----------------------------- | ------------------------------ |
| 担当 | **Podを作る・壊す・数を保つ** | **既にあるPodへ通信を届ける** |
| 動詞 | 縦(生成と更新) | 横(接続) |
| Podへの影響 | 作りも壊しもする | **一切触らない** |
| 実行主体 | kube-controller-manager | kube-proxy(各ノードのiptables) |

このリポジトリの YAML で言うと

```
deployment.yaml = 何を、何個、どう動かすか
  replicas: 2             (:9)   ← 数
  image:                  (:24)  ← 中身
  containerPort: 8080     (:28)  ← アプリのlistenポート
  resources / probes      (:33-)  ← 動かし方
  securityContext         (:47-)

service.yaml = どこから入って、どこへ流すか
  type: NodePort          (:10)  ← 入口の種類
  selector:               (:12)  ← 誰に流すか(ラベルで選ぶ)
  port / targetPort / nodePort (:15-18) ← 経路
```

### なぜ分かれているのか

Deployment が Pod を壊し続けるから、Service が必要になる

Pod は使い捨てで、作り直すたびに IP が変わる。\`(ClusterIP という仮想IPと DNS 名)を用意し、その裏で実際の Pod IP を差し替え続ける係がService

```
      安定した宛先                     使い捨ての実体
  Service(ClusterIP:80) ──selector──▶ Pod(IP変わる) ◀── Deployment が作り直す
        ↑ 変わらない                        ↑ 頻繁に入れ替わる
```

---

## serviceのport部分

manifests/service.yaml:14-18 を見ると、1つの Service に3つのポートが定義されています:

ports:

- name: http
  port: 80 # ← ClusterIP(クラスタ内部)で受けるポート
  targetPort: 8080 # ← コンテナ側のポート
  nodePort: 30080 # ← ノード(ホスト)側のポート

流れを図にするとこう:

ブラウザ → localhost:30080 → ClusterIP:80 → Pod/コンテナ:8080
(nodePort) (port) (targetPort)
ホスト側の入口 クラスタ内の入口 実際のアプリ

- 8080 = アプリが実際に listen してるポート。deployment.yaml:28,31 の containerPort: 8080 / PORT="8080"、Service では targetPort: 8080。「コンテナ=80」ではなく 8080 です。
- 80 = Service の ClusterIP としての窓口ポート (port: 80)。クラスタ内の他 Pod が hello-cloud-native:80 で呼ぶときに使う。外からは関係ない。
- 30080 = type: NodePort なので、ホスト(ノード)側に開くポート。service.yaml:2 のコメント通り「ノードの30080番からアクセスできる」。

なぜ 30080 なのかというと、NodePort が使える範囲がデフォルトで 30000–32767 に制限されているからです。
