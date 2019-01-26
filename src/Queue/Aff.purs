module Queue.Aff where

import Queue.Types (READ, WRITE, readOnly, writeOnly, allowReading, allowWriting, Handler)
import Queue (Queue)
import Queue as Queue

import Prelude (Unit, bind, discard, (>>=), pure, (<$>))
import Data.Either (Either (..))
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)


-- | Represents an asynchronously invokable function `input -> Aff output`
newtype IOQueues input output = IOQueues
  { input :: Queue (read :: READ) input
  , output :: Queue (write :: WRITE) output
  , cancel :: Queue (read :: READ) Error
  }


new :: forall input output. Effect (IOQueues input output)
new = do
  input <- readOnly <$> Queue.new
  output <- writeOnly <$> Queue.new
  cancel <- readOnly <$> Queue.new
  pure (IOQueues {input,output,cancel})

-- * Invoking

-- | Invoke the queue in `Aff`.
callAsync :: forall input output
           . IOQueues input output
          -> input
          -> Aff output
callAsync qs@(IOQueues {output}) x = makeAff \resolve -> (Queue.del output, and fuckin like pop the last one? Check length to see if it was already consumed?) <$ callAsyncEff qs (resolve <<< Right) x
  x <- Queue.draw (allowReading output)
  makeAff \resolve -> do
    Queue.draw (allowReading output) \y -> resolve (Right y)
    Queue.put (allowWriting input) x
    pure nonCanceler


-- | Invoke the queue in `Eff`
callAsyncEff :: forall input output
              . IOQueues input output
             -> Handler output
             -> input
             -> Effect Unit
callAsyncEff (IOQueues {input,output}) f x = do
  Queue.once (allowReading output) f
  Queue.put (allowWriting input) x


-- * Binding

-- | For binding the receiver
registerSync :: forall input output
              . IOQueues input output
             -> (input -> Effect output)
             -> Effect Unit
registerSync (IOQueues {input,output}) f =
  Queue.on input \x -> f x >>= Queue.put output


-- | Bind a receiver only once
registerSyncOnce :: forall input output
                  . IOQueues input output
                 -> (input -> Effect output)
                 -> Effect Unit
registerSyncOnce (IOQueues {input,output}) f =
  Queue.once input \x -> f x >>= Queue.put output
