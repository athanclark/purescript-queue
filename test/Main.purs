module Test.Main where

import Queue (newQueue, putQueue, onQueue)

import Prelude
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Console (CONSOLE, log)

main :: Eff _ Unit
main = do
  n <- newQueue

  onQueue n \_ -> log "1"

  putQueue n unit

  onQueue n \_ -> log "2"

  putQueue n unit
