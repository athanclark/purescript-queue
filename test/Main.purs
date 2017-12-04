module Test.Main where

import Queue.Aff (callAsync, registerSync, newIOQueues)

import Prelude
import Data.Either (Either (..))
import Control.Monad.Aff (runAff_)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Console (CONSOLE, log, logShow, errorShow)

main :: Eff _ Unit
main = do
  io <- newIOQueues

  registerSync io $ \x -> do
    log $ "Incrementing: " <> show x
    let r = x + 1
    log $ "Result: " <> show r
    pure r

  let call = callAsync io
      resolve eX = case eX of
        Left e -> errorShow e
        Right x -> logShow x

  runAff_ resolve $ do
    a <- call 1
    b <- call 10
    void $ call (a + b)
