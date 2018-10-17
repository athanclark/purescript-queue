module IxQueue.Aff
  ( IOQueues (..)
  , new
  , IOQueueKey
  , newKey
  , callAsync
  , callAsyncEff
  , registerSync
  , registerSyncOnce
  ) where

import Queue.Types (READ, WRITE, readOnly, writeOnly, allowReading, allowWriting, Handler)
import IxQueue (IxQueue)
import IxQueue as IxQueue

import Prelude
import Data.Either (Either (..))
import Data.UUID (genUUID, UUID)
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Aff (Aff, makeAff, Canceler (..))



newtype IOQueues input output = IOQueues
  { input :: IxQueue (read :: READ) input
  , output :: IxQueue (write :: WRITE) output
  }


new:: forall input output
    . Effect (IOQueues input output)
new= do
  input <- IxQueue.new
  output <- IxQueue.new
  pure (IOQueues {input: readOnly input,output: writeOnly output})


newtype IOQueueKey = IOQueueKey UUID

newKey :: Effect IOQueueKey
newKey = IOQueueKey <$> genUUID


-- * Invoking

-- | Invoke the queue in `Aff`
callAsync :: forall input output
           . IOQueueKey
          -> IOQueues input output
          -> input
          -> Aff output
callAsync (IOQueueKey k) (IOQueues {input,output}) x =
  makeAff \resolve -> do
    IxQueue.once (allowReading output) (show k) \y ->
      resolve (Right y)
    IxQueue.put (allowWriting input) (show k) x
    pure $ Canceler \e ->
      unit <$ liftEffect (IxQueue.del (allowReading output) (show k))


-- | Invoke the queue in `Eff`
callAsyncEff :: forall input output
              . IOQueueKey
             -> IOQueues input output
             -> Handler output
             -> input
             -> Effect Unit
callAsyncEff (IOQueueKey k) (IOQueues {input,output}) f x = do
  IxQueue.once (allowReading output) (show k) f
  IxQueue.put (allowWriting input) (show k) x


-- * Binding

-- | For binding the receiver
registerSync :: forall input output
              . IOQueues input output
             -> (input -> Effect output)
             -> Effect IOQueueKey
registerSync (IOQueues {input,output}) f = do
  k'@(IOQueueKey k) <- newKey
  IxQueue.on input (show k) \x ->
    IxQueue.put output (show k) =<< f x
  pure k'



-- | Bind a receiver only once
registerSyncOnce :: forall input output
                  . IOQueues input output
                 -> (input -> Effect output)
                 -> Effect IOQueueKey
registerSyncOnce (IOQueues {input,output}) f = do
  k'@(IOQueueKey k) <- newKey
  IxQueue.once input (show k) \x ->
    IxQueue.put output (show k) =<< f x
  pure k'
