module Queue.Aff where

import Queue.Internal (Queue, onceQueue, onQueue, putQueue, newQueue)

import Prelude
import Data.Either (Either (..))
import Control.Monad.Aff (Aff, makeAff, nonCanceler)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Ref (REF)



newtype IOQueues eff input output = IOQueues
  { input :: Queue eff input
  , output :: Queue eff output
  }


newIOQueues :: forall eff input output. Eff (ref :: REF | eff) (IOQueues (ref :: REF | eff) input output)
newIOQueues = do
  input <- newQueue
  output <- newQueue
  pure (IOQueues {input,output})


callAsync :: forall eff input output
           . IOQueues (ref :: REF | eff) input output
          -> input
          -> Aff (ref :: REF | eff) output
callAsync (IOQueues {input,output}) x =
  makeAff \resolve -> do
    onceQueue output \y -> resolve (Right y)
    putQueue input x
    pure nonCanceler



registerSyncOnce :: forall eff input output
                  . IOQueues (ref :: REF | eff) input output
                 -> (input -> Eff (ref :: REF | eff) output)
                 -> Eff (ref :: REF | eff) Unit
registerSyncOnce (IOQueues {input,output}) f =
  onceQueue input \x -> putQueue output =<< f x


registerSync :: forall eff input output
              . IOQueues (ref :: REF | eff) input output
             -> (input -> Eff (ref :: REF | eff) output)
             -> Eff (ref :: REF | eff) Unit
registerSync (IOQueues {input,output}) f =
  onQueue input \x -> putQueue output =<< f x
