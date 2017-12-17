module Queue.One
  ( module Queue.Scope
  , Queue, Handler, newQueue, readOnly, allowWriting, writeOnly, allowReading
  , putQueue, putManyQueue, onQueue, onceQueue, takeQueue, readQueue, delQueue
  ) where

import Queue.Scope (kind SCOPE, READ, WRITE)

import Prelude
import Data.Either (Either (..))
import Data.Maybe (Maybe (..))
import Data.Traversable (traverse_)
import Data.Array as Array
import Control.Monad.Eff (Eff, kind Effect)
import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, writeRef)




type Handler eff a = a -> Eff eff Unit

newtype Queue (rw :: # SCOPE) (eff :: # Effect) a =
  Queue (Ref (Either (Array a) (Handler eff a)))


newQueue :: forall eff a. Eff (ref :: REF | eff) (Queue (read :: READ, write :: WRITE) (ref :: REF | eff) a)
newQueue = Queue <$> newRef (Left [])


readOnly :: forall rw eff a. Queue (read :: READ | rw) eff a -> Queue (read :: READ) eff a
readOnly (Queue q) = Queue q

allowWriting :: forall rw eff a. Queue (read :: READ) eff a -> Queue (read :: READ | rw) eff a
allowWriting (Queue q) = Queue q

writeOnly :: forall rw eff a. Queue (write :: WRITE | rw) eff a -> Queue (write :: WRITE) eff a
writeOnly (Queue q) = Queue q

allowReading :: forall rw eff a. Queue (write :: WRITE) eff a -> Queue (write :: WRITE | rw) eff a
allowReading (Queue q) = Queue q


putQueue :: forall rw eff a. Queue (write :: WRITE | rw) (ref :: REF | eff) a -> a -> Eff (ref :: REF | eff) Unit
putQueue q x = putManyQueue q [x]


putManyQueue :: forall rw eff a. Queue (write :: WRITE | rw) (ref :: REF | eff) a -> Array a -> Eff (ref :: REF | eff) Unit
putManyQueue (Queue queue) xs = do
  ePH <- readRef queue
  case ePH of
    Left pending -> writeRef queue (Left (pending <> xs))
    Right f -> traverse_ f xs


onQueue :: forall rw eff a. Queue (read :: READ | rw) (ref :: REF | eff) a -> Handler (ref :: REF | eff) a -> Eff (ref :: REF | eff) Unit
onQueue (Queue queue) f = do
  ePH <- readRef queue
  case ePH of
    Left pending -> do
      traverse_ f pending
      writeRef queue (Right f)
    Right _ ->
      writeRef queue (Right f)


-- | Treat this as the only handler, and on the next input, clear all handlers.
onceQueue :: forall rw eff a. Queue (read :: READ | rw) (ref :: REF | eff) a -> Handler (ref :: REF | eff) a -> Eff (ref :: REF | eff) Unit
onceQueue q@(Queue queue) f' = do
  hasRun <- newRef false
  let f x = do
        r <- readRef hasRun
        unless r (f' x)
        writeRef hasRun true
        delQueue q
  ePH <- readRef queue
  case ePH of
    Left pending -> do
      case Array.uncons pending of
        Nothing ->
          writeRef queue (Right f)
        Just {head,tail} -> do
          f head
          writeRef queue (Left tail)
    Right _ ->
      writeRef queue (Right f)


readQueue :: forall rw eff a. Queue rw (ref :: REF | eff) a -> Eff (ref :: REF | eff) (Array a)
readQueue (Queue queue) = do
  ePH <- readRef queue
  case ePH of
    Left pending -> pure pending
    Right _ -> pure []


takeQueue :: forall rw eff a. Queue (write :: WRITE | rw) (ref :: REF | eff) a -> Eff (ref :: REF | eff) (Array a)
takeQueue (Queue queue) = do
  ePH <- readRef queue
  case ePH of
    Left pending -> do
      writeRef queue (Left [])
      pure pending
    Right _ -> pure []


-- | Removes the registered callbacks, if any.
delQueue :: forall rw eff a. Queue (read :: READ | rw) (ref :: REF | eff) a -> Eff (ref :: REF | eff) Unit
delQueue (Queue queue) = do
  ePH <- readRef queue
  case ePH of
    Left _ -> pure unit
    Right _ -> writeRef queue (Left [])
