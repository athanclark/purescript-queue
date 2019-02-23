module IOQueues where

import Queue.Types
  ( READ, WRITE, readOnly, writeOnly, allowReading, allowWriting, Handler
  , class Queue, class QueueScope, once, on, put)
import Queue.Types (new) as Q

import Prelude (Unit, bind, discard, (>>=), pure, (<$>), (<$), (<<<))
import Data.Either (Either (..))
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)


-- | Represents an asynchronously invokable function `input -> Aff output`
newtype IOQueues q input output = IOQueues
  { input :: q (read :: READ) input
  , output :: q (write :: WRITE) output
  }


new :: forall input output q. Queue q => QueueScope q => Effect (IOQueues q input output)
new = do
  input <- readOnly <$> Q.new
  output <- writeOnly <$> Q.new
  pure (IOQueues {input,output})

-- * Invoking

-- | Invoke the queue in `Aff`.
callAsync :: forall input output q
           . Queue q
          => QueueScope q
          => IOQueues q input output
          -> input
          -> Aff output
callAsync qs x = makeAff \resolve ->
  nonCanceler <$ callAsyncEff qs (resolve <<< Right) x


-- | Invoke the queue in `Eff`
callAsyncEff :: forall input output q
              . Queue q
             => QueueScope q
             => IOQueues q input output
             -> Handler output
             -> input
             -> Effect Unit
callAsyncEff (IOQueues {input,output}) f x = do
  once (allowReading output) f
  put (allowWriting input) x


-- * Binding

-- | For binding the receiver
registerSync :: forall input output q
              . Queue q
             => IOQueues q input output
             -> (input -> Effect output)
             -> Effect Unit
registerSync (IOQueues {input,output}) f =
  on input \x -> f x >>= put output


-- | Bind a receiver only once
registerSyncOnce :: forall input output q
                  . Queue q
                 => IOQueues q input output
                 -> (input -> Effect output)
                 -> Effect Unit
registerSyncOnce (IOQueues {input,output}) f =
  once input \x -> f x >>= put output
