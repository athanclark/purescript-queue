module Test.Main where

import Queue.Lossy (newQueue, putQueue, onQueueDelay)

import Prelude
import Data.Time.Duration (Milliseconds (..))
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Console (CONSOLE, log, logShow)

main :: Eff _ Unit
main = do
  n <- newQueue

  onQueueDelay n (Milliseconds 1000.0) \w -> logShow w

  putQueue n 1
  putQueue n 2
