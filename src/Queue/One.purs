module Queue.One
  ( module Queue.Types
  , Queue (..), newQueue
  , putQueue, putManyQueue, onQueue, onceQueue, drawQueue, takeQueue, readQueue, delQueue, drainQueue
  ) where

import Queue.Types (kind SCOPE, READ, WRITE, class QueueScope, Handler)

import Prelude
import Data.Either (Either (..))
import Data.Maybe (Maybe (..))
import Data.Traversable (class Traversable, traverse_, for_)
import Data.Array as Array
import Data.NonEmpty (NonEmpty (..))
import Control.Monad.Aff (Aff, makeAff, nonCanceler)
import Control.Monad.Eff (Eff, kind Effect)
import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, writeRef)




newtype Queue (rw :: # SCOPE) (eff :: # Effect) a =
  Queue (Ref (Either (Array a) (Handler eff a)))


newQueue :: forall eff a. Eff (ref :: REF | eff) (Queue (read :: READ, write :: WRITE) (ref :: REF | eff) a)
newQueue = Queue <$> newRef (Left [])


instance queueScopeQueueOne :: QueueScope Queue where
  readOnly     (Queue q) = Queue q
  allowWriting (Queue q) = Queue q
  writeOnly    (Queue q) = Queue q
  allowReading (Queue q) = Queue q


putQueue :: forall rw eff a. Queue (write :: WRITE | rw) (ref :: REF | eff) a -> a -> Eff (ref :: REF | eff) Unit
putQueue q x = putManyQueue q (NonEmpty x [])


putManyQueue :: forall rw eff a t
              . Traversable t
             => Queue (write :: WRITE | rw) (ref :: REF | eff) a
             -> NonEmpty t a
             -> Eff (ref :: REF | eff) Unit
putManyQueue (Queue queue) xss = do
  for_ xss \x -> do
    ePH <- readRef queue
    case ePH of
      Left pending -> writeRef queue (Left (pending <> [x]))
      Right f -> f x


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
  let f x = do
        delQueue q
        f' x
  ePH <- readRef queue
  case ePH of
    Left pending -> do
      case Array.uncons pending of
        Nothing ->
          writeRef queue (Right f)
        Just {head,tail} -> do
          f' head
          writeRef queue (Left tail)
    Right _ ->
      writeRef queue (Right f)


drawQueue :: forall rw eff a. Queue (read :: READ | rw) (ref :: REF | eff) a -> Aff (ref :: REF | eff) a
drawQueue q = makeAff \resolve -> do
  onceQueue q (resolve <<< Right)
  pure nonCanceler


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



drainQueue :: forall rw eff a. Queue (read :: READ | rw) (ref :: REF | eff) a -> Eff (ref :: REF | eff) Unit
drainQueue q = onQueue q \_ -> pure unit