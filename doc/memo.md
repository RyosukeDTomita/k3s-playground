# 自分用メモ

## 用語整理

マシンの軸

- クラスター: 複数のマイクロサービスを載せる
  - コントロールプレーンノード: オーケストレーションする
    - etcd: クラスター情報を全管理するデータベース。
    - kube-apiserver: kubectlとやりとりする
    - kube-controller-manager: コントローラを統括管理・実行
    - kube-scheduler: Podをワーカーノードに割り当てる
    - cloud-controller-manager: クラウドサービスと連携に使用し、ノードが消えたらクラドAPIに問い合わせて確認するなど。オンプレには不要。
  - ワーカーノード
    - kubelet、kube-proxy、コンテナランタイム
    - Pod(レプリカ): ポッドテンプレートの雛形に基づいて作成
      - コンテナ
      - ボリューム

### 図1: どう動くか(概要)

公式図と同じ構成。kube-apiserverが中心(ハブ)で、他のコンポーネントは互いに直接喋らず必ずapiserverを経由する。

```mermaid
---
config:
  theme: base
  themeVariables:
    primaryTextColor: '#1a1a1a'
    lineColor: '#000000'
    edgeLabelBackground: '#ffffff'
    clusterBkg: '#fafafa'
    titleColor: '#1a1a1a'
---
flowchart LR
    subgraph canvas[" "]
        direction LR
        user["👤 開発者<br/>kubectl apply"]

        subgraph cp["コントロールプレーン(頭脳)"]
            direction TB
            ccm(("c-c-m<br/>cloud-controller-manager"))
            cm(("c-m<br/>kube-controller-manager"))
            sched(("sched<br/>kube-scheduler"))
            etcd[("etcd<br/>クラスターの正")]
            api(("api<br/>kube-apiserver"))

            cm --- api
            ccm --- api
            sched --- api
            api -- "② あるべき状態を保存" --- etcd
        end

        subgraph n1["ワーカーノード #1(手足)"]
            direction TB
            kubelet1(("kubelet"))
            proxy1(("k-proxy"))
            pods1["Pod / Pod / Pod"]
            kubelet1 -- "④ コンテナを起動" --> pods1
        end

        subgraph n2["ワーカーノード #2(手足)"]
            direction TB
            kubelet2(("kubelet"))
            proxy2(("k-proxy"))
            pods2["Pod / Pod"]
            kubelet2 --> pods2
        end

        user -- "① マニフェスト投入" --> api
        sched -. "③ 配置先ノードを決定" .-> api
        api -- "④ 担当Podを渡す<br/>⑥ 状態を報告" --- kubelet1
        api --- kubelet2
        api -- "⑤ Service情報" --- proxy1
        api --- proxy2
        cm -. "⑦ 差分があれば埋める" .-> api
        ccm -. "ノード死活確認" .-> cloudapi["☁ クラウドAPI<br/>オンプレでは不要"]
    end

    linkStyle default stroke:#000000,stroke-width:3px,color:#000000

    classDef ctrl fill:#cfe3fb,stroke:#2b6cb0,stroke-width:1px,color:#1a1a1a
    classDef hub fill:#90b8ec,stroke:#1a4f8a,stroke-width:3px,color:#1a1a1a
    classDef store fill:#e3d5f5,stroke:#6b46c1,stroke-width:1px,color:#1a1a1a
    classDef nodecomp fill:#cdead6,stroke:#2f855a,stroke-width:1px,color:#1a1a1a
    classDef app fill:#fbd38d,stroke:#b7791f,stroke-width:1px,color:#1a1a1a
    classDef external fill:#e8e8e8,stroke:#666666,stroke-width:1px,color:#1a1a1a
    classDef optional fill:#f0f0f0,stroke:#999999,stroke-width:1px,stroke-dasharray:4 3,color:#1a1a1a

    class api hub
    class cm,sched ctrl
    class ccm optional
    class etcd store
    class kubelet1,kubelet2,proxy1,proxy2 nodecomp
    class pods1,pods2 app
    class user,cloudapi external

    style canvas fill:#fafafa,stroke:#fafafa,color:#1a1a1a
    style cp fill:#eaf2fd,stroke:#2b6cb0,stroke-width:2px,color:#1a1a1a
    style n1 fill:#edf7f1,stroke:#2f855a,stroke-width:2px,color:#1a1a1a
    style n2 fill:#edf7f1,stroke:#2f855a,stroke-width:2px,color:#1a1a1a
```

Deployment適用時の流れ:

1. `kubectl apply`でマニフェストをkube-apiserverに投げる
2. kube-apiserverが「あるべき状態」をetcdに保存する(この時点ではまだ何も動いていない)
3. kube-schedulerが配置先ノードの決まっていないPodを見つけ、空きリソースを見てノードを決める
4. 対象ノードのkubeletがapiserver経由で自分の担当Podを受け取り、コンテナランタイムでコンテナを起動する
5. kube-proxyがService宛の通信をPodに流すためのルールをノードに設定する
6. kubeletが実際の状態をapiserverに報告し続ける
7. kube-controller-managerが「あるべき状態」と「実際の状態」を比べ、差があれば埋める(Podが落ちたら作り直す、など)

---

### 図2: 入れ子構造(登場人物と、実は何が中にいるか)

図1の登場人物が実際どこに属しているか。矢印なし。枠の入れ子と色の濃さがそのまま階層の深さ。

```mermaid
---
config:
  theme: base
  themeVariables:
    primaryTextColor: '#1a1a1a'
    lineColor: '#000000'
    edgeLabelBackground: '#ffffff'
    clusterBkg: '#fafafa'
    titleColor: '#1a1a1a'
---
flowchart TB
    subgraph cluster["クラスター — 複数のマイクロサービスを載せる"]
        direction TB

        subgraph cp["コントロールプレーンノード — オーケストレーションする"]
            direction TB
            etcd["etcd<br/>クラスター情報を全管理するDB<br/>k3sではSQLite"]
            api["kube-apiserver<br/>kubectlとやりとりする"]
            cm["kube-controller-manager<br/>コントローラを統括管理・実行"]
            sched["kube-scheduler<br/>Podをワーカーノードに割り当てる"]
            ccm["cloud-controller-manager<br/>クラウド連携用<br/>オンプレには不要"]
        end

        subgraph w1["ワーカーノード #1"]
            direction TB

            subgraph nodecomps["ノード自体の常駐コンポーネント"]
                direction TB
                kubelet["kubelet<br/>Podを起動・監視する"]
                proxy["kube-proxy<br/>Service宛通信をPodに流す"]
                runtime["コンテナランタイム<br/>k3sではcontainerd"]
            end

            subgraph pod["Pod(レプリカ) — Podテンプレートを雛形に作成"]
                direction TB
                container["コンテナ"]
                volume["ボリューム"]
            end

            nodecomps ~~~ pod
        end

        subgraph w2["ワーカーノード #2 ... (同じ構成がN台)"]
            direction TB
            etc["kubelet / kube-proxy / コンテナランタイム / Pod"]
        end

        cp ~~~ w1
        w1 ~~~ w2
    end

    classDef ctrl fill:#cfe3fb,stroke:#2b6cb0,stroke-width:1px,color:#1a1a1a
    classDef store fill:#e3d5f5,stroke:#6b46c1,stroke-width:1px,color:#1a1a1a
    classDef nodecomp fill:#cdead6,stroke:#2f855a,stroke-width:1px,color:#1a1a1a
    classDef app fill:#fbd38d,stroke:#b7791f,stroke-width:1px,color:#1a1a1a
    classDef optional fill:#f0f0f0,stroke:#999999,stroke-width:1px,stroke-dasharray:4 3,color:#1a1a1a

    class api,cm,sched ctrl
    class ccm optional
    class etcd,volume store
    class kubelet,proxy,runtime,etc nodecomp
    class container app

    style cluster fill:#f7f7f7,stroke:#333333,stroke-width:3px,color:#1a1a1a
    style cp fill:#eaf2fd,stroke:#2b6cb0,stroke-width:2px,color:#1a1a1a
    style w1 fill:#edf7f1,stroke:#2f855a,stroke-width:2px,color:#1a1a1a
    style w2 fill:#edf7f1,stroke:#2f855a,stroke-width:2px,stroke-dasharray:5 4,color:#1a1a1a
    style nodecomps fill:#e2f2e8,stroke:#2f855a,stroke-width:1px,stroke-dasharray:4 3,color:#1a1a1a
    style pod fill:#fdf0dc,stroke:#b7791f,stroke-width:2px,color:#1a1a1a
```

---

オブジェクトの軸

- デプロイメント: Podのデプロイを管理。マニフェストファイルに`kind: Deployment`に対応する?
  - レプリカセット: Podの数を管理する
    - Pod
- サービス: Podをまとめて管理する。ロードバランサー的にPodを管理する。サービス単位でクラスターIPがふられる

---

## マニフェスト

- DeploymentとServiceを粗結合にわけて書くようにできている(1つのファイルに書いても良い)
  - Podはアプリの更新時に再ビルドするのでDeploymentのライフサイクルは短い
  - Serviceは割と長生きする
  - Serviceのversionセレクタを切り替えるだけでBlue/Greenデプロイできる

---

## コマンド

- applyでマニフェスト適用
- get node get podのようにgetでチェック

---

## k3s

- etcd: sqLite
- コンテナランタイムはcontainerd
- k3sに限らず、k8sはイメージビルド機能はないので事前にイメージ作成が必要
