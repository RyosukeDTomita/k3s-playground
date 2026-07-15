{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wunused-imports #-}

-- | Hello, Cloud Native!をJSONで返すだけのバックエンド。
module Main (main) where

import Control.Concurrent (myThreadId)
import Control.Exception (throwTo)
import Data.Aeson (KeyValue ((.=)), encode, object)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Network.HTTP.Types (status200)
import Network.Wai (Application, responseLBS)
import Network.Wai.Handler.Warp (run)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (ExitSuccess))
import System.IO (BufferMode (LineBuffering), hSetBuffering, stdout)
import System.Posix.Signals (Handler (CatchOnce), installHandler, sigTERM)
import Text.Read (readMaybe)

main :: IO ()
main = do
  -- コンテナのログ(kubectl logs)にすぐ流れるよう行バッファリングにする。
  hSetBuffering stdout LineBuffering
  -- コンテナ内ではPID 1で動くためSIGTERMのデフォルト動作が無視される。
  -- ハンドラを入れないとk8sの停止時に猶予時間いっぱい待ってSIGKILLされる。
  mainThread <- myThreadId
  _ <- installHandler sigTERM (CatchOnce $ throwTo mainThread ExitSuccess) Nothing
  port <- lookupPort
  podName <- lookupPodName
  putStrLn $ "listening on port " <> show port <> " as " <> Text.unpack podName
  run port $ app podName

-- | PORT環境変数からポート番号を取得する(未設定・不正値なら8080)。
lookupPort :: IO Int
lookupPort = do
  maybePort <- lookupEnv "PORT"
  pure $ fromMaybe 8080 $ maybePort >>= readMaybe

-- | HOSTNAME環境変数からPod名を取得する(未設定なら"unknown")。
-- k8sではコンテナのホスト名=Pod名がHOSTNAMEに入るので、
-- どのレプリカが応答したかをレスポンスで確認できる。
lookupPodName :: IO Text
lookupPodName = do
  maybeName <- lookupEnv "HOSTNAME"
  pure $ maybe "unknown" Text.pack maybeName

-- | どのパスへのリクエストにも自分のPod名入りのJSONを返すApplication。
app :: Text -> Application
app podName _request respond =
  respond $ responseLBS status200 [("Content-Type", "application/json")] body
  where
    body =
      encode $
        object
          [ "message" .= ("Hello, Cloud Native!" :: Text),
            "pod" .= podName
          ]
