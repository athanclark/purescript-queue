module IxQueue.Aff where

import Queue.Scope (READ, WRITE)
import IxQueue.Internal (IxQueue, delIxQueue, onIxQueue, onceIxQueue, putIxQueue, newIxQueue, readOnly, writeOnly, allowReading, allowWriting)

import Prelude
import Data.Either (Either (..))
import Data.UUID (GENUUID, genUUID, UUID)
import Control.Monad.Aff (Aff, makeAff, Canceler (..))
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Ref (REF)



newtype IOQueues eff input output = IOQueues
  { input :: IxQueue (read :: READ) eff input
  , output :: IxQueue (write :: WRITE) eff output
  }


newIOQueues :: forall eff input output
             . Eff (ref :: REF | eff) (IOQueues (ref :: REF | eff) input output)
newIOQueues = do
  input <- newIxQueue
  output <- newIxQueue
  pure (IOQueues {input: readOnly input,output: writeOnly output})


newtype IOQueueKey = IOQueueKey UUID


callAsync :: forall eff input output
           . IOQueueKey
          -> IOQueues (ref :: REF | eff) input output
          -> input
          -> Aff (ref :: REF | eff) output
callAsync (IOQueueKey k) (IOQueues {input,output}) x =
  makeAff \resolve -> do
    onceIxQueue (allowReading output) (show k) \y ->
      resolve (Right y)
    putIxQueue (allowWriting input) (show k) x
    pure $ Canceler \e ->
      unit <$ liftEff (delIxQueue (allowReading output) (show k))



registerSyncOnce :: forall eff input output
                  . IOQueues (ref :: REF, uuid :: GENUUID | eff) input output
                 -> (input -> Eff (ref :: REF, uuid :: GENUUID | eff) output)
                 -> Eff (ref :: REF, uuid :: GENUUID | eff) IOQueueKey
registerSyncOnce (IOQueues {input,output}) f = do
  k <- genUUID
  onceIxQueue input (show k) \x ->
    putIxQueue output (show k) =<< f x
  pure (IOQueueKey k)


registerSync :: forall eff input output
              . IOQueues (ref :: REF, uuid :: GENUUID | eff) input output
             -> (input -> Eff (ref :: REF, uuid :: GENUUID | eff) output)
             -> Eff (ref :: REF, uuid :: GENUUID | eff) IOQueueKey
registerSync (IOQueues {input,output}) f = do
  k <- genUUID
  onIxQueue input (show k) \x ->
    putIxQueue output (show k) =<< f x
  pure (IOQueueKey k)
