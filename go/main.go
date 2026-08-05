// Hello, Cloud Native!をJSONで返すだけのバックエンド(Haskell版のGo移植)。
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
)

func main() {
	port := lookupPort()
	podName := lookupPodName()
	log.Printf("listening on port %d as %s", port, podName)

	// コンテナ内ではPID 1で動くが、Goランタイムが自前でシグナルを処理する
	// ためSIGTERMで終了はする。ただしデフォルトは異常終了(exit 143)扱い
	// なので、Haskell版と同じく正常終了(exit 0)にそろえる。
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM)
	go func() {
		<-sigCh
		os.Exit(0)
	}()

	http.HandleFunc("/", handler(podName))
	log.Fatal(http.ListenAndServe(":"+strconv.Itoa(port), nil))
}

// lookupPort はPORT環境変数からポート番号を取得する(未設定・不正値なら8080)。
func lookupPort() int {
	if p, err := strconv.Atoi(os.Getenv("PORT")); err == nil {
		return p
	}
	return 8080
}

// lookupPodName はHOSTNAME環境変数からPod名を取得する(未設定なら"unknown")。
// k8sではコンテナのホスト名=Pod名がHOSTNAMEに入るので、
// どのレプリカが応答したかをレスポンスで確認できる。
func lookupPodName() string {
	if name := os.Getenv("HOSTNAME"); name != "" {
		return name
	}
	return "unknown"
}

// handler はどのパスへのリクエストにも自分のPod名入りのJSONを返す。
func handler(podName string) http.HandlerFunc {
	body, err := json.Marshal(map[string]string{
		"message": "Hello, Cloud Native!",
		"pod":     podName,
	})
	if err != nil {
		log.Fatal(err)
	}
	return func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write(body)
	}
}
