module Queue
  ( Queue, newQueue, putQueue, putManyQueue, onQueue, readQueue, takeQueue
  ) where

import Prelude
import Data.Traversable (traverse_)
import Control.Monad.Eff (kind Effect, Eff)
import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, modifyRef, writeRef)
import Signal (runSignal, sampleOn, constant)
import Signal.Channel (CHANNEL, Channel, channel, send, subscribe)



newtype Queue a = Queue
  { pending :: Ref (Array a)
  , chan    :: Channel Unit
  }

newQueue :: forall eff a
          . Eff ( channel :: CHANNEL
                , ref     :: REF
                | eff) (Queue a)
newQueue = do
  chan <- channel unit
  pending <- newRef []
  pure $ Queue {pending,chan}


-- | Signal the listener with a value - note that there can be any number of writers to the queue.
putQueue :: forall eff a
          . Queue a
         -> a
         -> Eff ( channel :: CHANNEL
                , ref     :: REF
                | eff) Unit
putQueue q x = putManyQueue q [x]

putManyQueue :: forall eff a
              . Queue a
             -> Array a
             -> Eff ( channel :: CHANNEL
                    , ref     :: REF
                    | eff) Unit
putManyQueue (Queue {pending,chan}) xs = do
  modifyRef pending (\ys -> ys <> xs)
  send chan unit


-- | There should only be one listener at a time per queue - multiple readers would cause a race condition.
onQueue :: forall eff a
         . Queue a
        -> (a -> Eff ( channel :: CHANNEL
                     , ref     :: REF
                     | eff) Unit)
        -> Eff ( channel :: CHANNEL
               , ref     :: REF
               | eff) Unit
onQueue (Queue {pending,chan}) f =
  runSignal $
    let go = do
          xs <- readRef pending
          writeRef pending []
          traverse_ f xs
    in  subscribe chan `sampleOn` constant go

-- | Read the entities in the queue without triggering the onQueue callback.
readQueue :: forall eff a
           . Queue a
          -> Eff ( ref :: REF
                 | eff) (Array a)
readQueue (Queue {pending}) =
  readRef pending

-- | Take the entities out of the queue without triggering the onQueue callback.
takeQueue :: forall eff a
           . Queue a
          -> Eff ( ref :: REF
                 | eff) (Array a)
takeQueue (Queue {pending}) = do
  xs <- readRef pending
  writeRef pending []
  pure xs
