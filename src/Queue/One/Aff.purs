module Queue.One.Aff where

import Queue.Types (READ, WRITE, readOnly, writeOnly, allowReading, allowWriting)
import Queue.One (Queue, onceQueue, onQueue, putQueue, newQueue)

import Prelude
import Data.Either (Either (..))
import Control.Monad.Aff (Aff, makeAff, nonCanceler)
import Control.Monad.Eff (Eff, kind Effect)
import Control.Monad.Eff.Ref (REF)



newtype IOQueues (eff :: # Effect) input output = IOQueues
  { input :: Queue input (read :: READ) eff
  , output :: Queue output (write :: WRITE) eff
  }


newIOQueues :: forall eff input output. Eff (ref :: REF | eff) (IOQueues (ref :: REF | eff) input output)
newIOQueues = do
  input <- readOnly <$> newQueue
  output <- writeOnly <$> newQueue
  pure (IOQueues {input,output})


-- * Invoking

-- | Invoke the queue in `Aff`
callAsync :: forall eff input output
           . IOQueues (ref :: REF | eff) input output
          -> input
          -> Aff (ref :: REF | eff) output
callAsync (IOQueues {input,output}) x =
  makeAff \resolve -> do
    onceQueue (allowReading output) \y -> resolve (Right y)
    putQueue (allowWriting input) x
    pure nonCanceler


-- | Invoke the queue in `Eff`
callAsyncEff :: forall eff input output
              . IOQueues (ref :: REF | eff) input output
             -> (output -> Eff (ref :: REF | eff) Unit)
             -> input
             -> Eff (ref :: REF | eff) Unit
callAsyncEff (IOQueues {input,output}) f x = do
  onceQueue (allowReading output) f
  putQueue (allowWriting input) x


-- * Binding

-- | For binding the receiver
registerSync :: forall eff input output
              . IOQueues (ref :: REF | eff) input output
             -> (input -> Eff (ref :: REF | eff) output)
             -> Eff (ref :: REF | eff) Unit
registerSync (IOQueues {input,output}) f =
  onQueue input \x -> putQueue output =<< f x



-- | Bind a receiver only once
registerSyncOnce :: forall eff input output
                    . IOQueues (ref :: REF | eff) input output
                  -> (input -> Eff (ref :: REF | eff) output)
                  -> Eff (ref :: REF | eff) Unit
registerSyncOnce (IOQueues {input,output}) f =
  onceQueue input \x -> putQueue output =<< f x
