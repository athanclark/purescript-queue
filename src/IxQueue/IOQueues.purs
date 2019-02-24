module IxQueue.IOQueues
  ( module IOQueues
  , new
  , callAsync
  , callAsyncEff
  , registerSync
  , registerSyncOnce
  ) where

import Queue.Types (readOnly, writeOnly, allowReading, allowWriting, Handler)
import IOQueues (IOQueues (..))
import IxQueue (IxQueue)
import IxQueue as IxQueue

import Prelude
import Data.Either (Either (..))
import Effect (Effect)
import Effect.Aff (Aff, makeAff, effectCanceler)




new:: forall input output
    . Effect (IOQueues IxQueue input output)
new= do
  input <- IxQueue.new
  output <- IxQueue.new
  pure (IOQueues {input: readOnly input,output: writeOnly output})



-- * Invoking

-- | Invoke the queue in `Aff`
callAsync :: forall input output
           . String
          -> IOQueues IxQueue input output
          -> input
          -> Aff output
callAsync k q@(IOQueues{output}) x =
  makeAff \resolve ->
    effectCanceler (void (IxQueue.del (allowReading output) k))
      <$ callAsyncEff k q (resolve <<< Right) x


-- | Invoke the queue in `Eff`
callAsyncEff :: forall input output
              . String
             -> IOQueues IxQueue input output
             -> Handler output
             -> input
             -> Effect Unit
callAsyncEff k (IOQueues {input,output}) f x = do
  IxQueue.once (allowReading output) k f
  IxQueue.put (allowWriting input) k x


-- * Binding

-- | For binding the receiver
registerSync :: forall input output
              . String
             -> IOQueues IxQueue input output
             -> (input -> Effect output)
             -> Effect Unit
registerSync k (IOQueues {input,output}) f = do
  IxQueue.on input k \x -> f x >>= IxQueue.put output k



-- | Bind a receiver only once
registerSyncOnce :: forall input output
                  . String
                 -> IOQueues IxQueue input output
                 -> (input -> Effect output)
                 -> Effect Unit
registerSyncOnce k (IOQueues {input,output}) f = do
  IxQueue.once input k \x -> f x >>= IxQueue.put output k
