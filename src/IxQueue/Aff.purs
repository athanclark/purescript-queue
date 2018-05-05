module IxQueue.Aff
  ( IOQueues (..)
  , newIOQueues
  , IOQueueKey
  , newIOQueueKey
  , callAsync
  , callAsyncEff
  , registerSync
  , registerSyncOnce
  ) where

import Queue.Types (READ, WRITE, readOnly, writeOnly, allowReading, allowWriting)
import IxQueue (IxQueue, delIxQueue, onIxQueue, onceIxQueue, putIxQueue, newIxQueue)

import Prelude
import Data.Either (Either (..))
import Data.UUID (GENUUID, genUUID, UUID)
import Control.Monad.Aff (Aff, makeAff, Canceler (..))
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Ref (REF)



newtype IOQueues eff input output = IOQueues
  { input :: IxQueue input (read :: READ) eff
  , output :: IxQueue output (write :: WRITE) eff
  }


newIOQueues :: forall eff input output
             . Eff (ref :: REF | eff) (IOQueues (ref :: REF | eff) input output)
newIOQueues = do
  input <- newIxQueue
  output <- newIxQueue
  pure (IOQueues {input: readOnly input,output: writeOnly output})


newtype IOQueueKey = IOQueueKey UUID

newIOQueueKey :: forall eff. Eff (uuid :: GENUUID | eff) IOQueueKey
newIOQueueKey = IOQueueKey <$> genUUID


-- * Invoking

-- | Invoke the queue in `Aff`
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


-- | Invoke the queue in `Eff`
callAsyncEff :: forall eff input output
              . IOQueueKey
             -> IOQueues (ref :: REF | eff) input output
             -> (output -> Eff (ref :: REF | eff) Unit)
             -> input
             -> Eff (ref :: REF | eff) Unit
callAsyncEff (IOQueueKey k) (IOQueues {input,output}) f x = do
  onceIxQueue (allowReading output) (show k) f
  putIxQueue (allowWriting input) (show k) x


-- * Binding

-- | For binding the receiver
registerSync :: forall eff input output
              . IOQueues (ref :: REF, uuid :: GENUUID | eff) input output
             -> (input -> Eff (ref :: REF, uuid :: GENUUID | eff) output)
             -> Eff (ref :: REF, uuid :: GENUUID | eff) IOQueueKey
registerSync (IOQueues {input,output}) f = do
  k'@(IOQueueKey k) <- newIOQueueKey
  onIxQueue input (show k) \x ->
    putIxQueue output (show k) =<< f x
  pure k'



-- | Bind a receiver only once
registerSyncOnce :: forall eff input output
                  . IOQueues (ref :: REF, uuid :: GENUUID | eff) input output
                 -> (input -> Eff (ref :: REF, uuid :: GENUUID | eff) output)
                 -> Eff (ref :: REF, uuid :: GENUUID | eff) IOQueueKey
registerSyncOnce (IOQueues {input,output}) f = do
  k'@(IOQueueKey k) <- newIOQueueKey
  onceIxQueue input (show k) \x ->
    putIxQueue output (show k) =<< f x
  pure k'
