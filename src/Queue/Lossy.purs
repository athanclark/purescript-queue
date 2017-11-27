module Queue.Lossy
  ( Queue, newQueue, putQueue, onQueue, onQueueDelay, readQueue, takeQueue
  ) where

import Prelude
import Data.Maybe (Maybe (..))
import Data.Traversable (traverse_)
import Data.Time.Duration (Milliseconds (..))
import Data.Int (round)
import Control.Monad.Eff (kind Effect, Eff)
import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, modifyRef, writeRef)
import Control.Monad.Eff.Timer (TIMER, setTimeout, clearTimeout)
import Signal (runSignal, sampleOn, constant)
import Signal.Channel (CHANNEL, Channel, channel, send, subscribe)



newtype Queue a = Queue
  { pending :: Ref (Maybe a)
  , chan    :: Ref (Maybe (Channel Unit))
  }


newQueue :: forall eff a
          . Eff ( channel :: CHANNEL
                , ref     :: REF
                | eff) (Queue a)
newQueue = do
  chan <- newRef Nothing
  pending <- newRef Nothing
  pure $ Queue {pending,chan}


-- | Signal the listener with a value - note that there can be any number of writers to the queue.
putQueue :: forall eff a
          . Queue a
         -> a
         -> Eff ( channel :: CHANNEL
                , ref     :: REF
                | eff) Unit
putQueue (Queue {pending,chan}) x = do
  modifyRef pending (\_ -> Just x)
  mc <- readRef chan
  case mc of
    Nothing -> pure unit
    Just c -> send c unit


-- | There should only be one listener at a time per queue - multiple readers would cause a race condition.
onQueue :: forall eff a
         . Queue a
        -> (a -> Eff ( channel :: CHANNEL
                     , ref     :: REF
                     | eff) Unit)
        -> Eff ( channel :: CHANNEL
               , ref     :: REF
               | eff) Unit
onQueue (Queue {pending,chan}) f = do
  c <- channel unit
  writeRef chan (Just c)
  runSignal $
    let go = do
          xs <- readRef pending
          writeRef pending Nothing
          traverse_ f xs
    in  subscribe c `sampleOn` constant go

-- | There should only be one listener at a time per queue - multiple readers would cause a race condition.
onQueueDelay :: forall eff a
         . Queue a
        -> Milliseconds
        -> (a -> Eff ( channel :: CHANNEL
                     , ref     :: REF
                     , timer   :: TIMER
                     | eff) Unit)
        -> Eff ( channel :: CHANNEL
               , ref     :: REF
               , timer   :: TIMER
               | eff) Unit
onQueueDelay (Queue {pending,chan}) (Milliseconds t) f = do
  c <- channel unit
  writeRef chan (Just c)

  threadRef <- newRef Nothing
  runSignal $
    let go = do
          mThread <- readRef threadRef
          case mThread of
            Nothing -> pure unit
            Just thread -> clearTimeout thread
          thread <- setTimeout (round t) do
            xs <- readRef pending
            writeRef pending Nothing
            traverse_ f xs
          writeRef threadRef (Just thread)
    in  subscribe c `sampleOn` constant go

-- | Read the entities in the queue without triggering the onQueue callback.
readQueue :: forall eff a
           . Queue a
          -> Eff ( ref :: REF
                 | eff) (Maybe a)
readQueue (Queue {pending}) =
  readRef pending

-- | Take the entities out of the queue without triggering the onQueue callback.
takeQueue :: forall eff a
           . Queue a
          -> Eff ( ref :: REF
                 | eff) (Maybe a)
takeQueue (Queue {pending}) = do
  xs <- readRef pending
  writeRef pending Nothing
  pure xs
