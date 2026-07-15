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
