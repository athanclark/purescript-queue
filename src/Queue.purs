module Queue
  ( module Queue.Types
  , Queue (..)
  , newQueue
  , putQueue, putManyQueue
  , onQueue, onceQueue, drawQueue
  , readQueue, takeQueue, delQueue, drainQueue
  ) where

import Queue.Types (kind SCOPE, READ, WRITE, class QueueScope, Handler)

import Prelude
import Data.Either (Either (..))
import Data.Maybe (Maybe (..))
import Data.Traversable (class Traversable, traverse_, for_)
import Data.Array as Array
import Data.NonEmpty (NonEmpty (..))
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Ref (Ref)
import Effect.Ref as Ref
-- import Control.Monad.Aff (Aff, makeAff, nonCanceler)
-- import Control.Monad.Eff (Eff, kind Effect)
-- import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, writeRef)




newtype Queue (rw :: # SCOPE) a = Queue (Ref (Either (Array a) (Array (Handler a))))


newQueue :: forall a. Effect (Queue (read :: READ, write :: WRITE) a)
newQueue = Queue <$> Ref.new (Left [])


instance queueScopeQueue :: QueueScope Queue where
  readOnly     (Queue q) = Queue q
  allowWriting (Queue q) = Queue q
  writeOnly    (Queue q) = Queue q
  allowReading (Queue q) = Queue q


put :: forall rw a. Queue (write :: WRITE | rw) a -> a -> Effect Unit
put q x = putMany q (NonEmpty x [])


putMany :: forall rw a t
         . Traversable t
        => Queue (write :: WRITE | rw) a
        -> NonEmpty t a
        -> Effect Unit
putMany (Queue queue) xss =
  for_ xss \x -> do
    ePH <- Ref.read queue
    case ePH of
      Left pending -> Ref.write queue (Left (pending <> [x]))
      Right hs -> traverse_ (\f -> f x) hs


on :: forall rw a. Queue (read :: READ | rw) a -> Handler a -> Effect Unit
on (Queue queue) f = do
  ePH <- Ref.read queue
  case ePH of
    Left pending -> do
      traverse_ f pending
      Ref.write queue (Right [f])
    Right handlers ->
      Ref.write queue (Right (handlers <> [f]))


-- | Treat this as the only handler, and on the next input, clear all handlers.
once :: forall rw a. Queue (read :: READ | rw) a -> Handler a -> Effect Unit
once q@(Queue queue) f' = do
  hasRun <- Ref.new false
  let f x = do
        del q
        f' x
  ePH <- Ref.read queue
  case ePH of
    Left pending -> do
      case Array.uncons pending of
        Nothing ->
          Ref.write queue (Right [f])
        Just {head,tail} -> do
          f' head
          Ref.write queue (Left tail)
    Right handlers ->
      Ref.write queue (Right (handlers <> [f]))


draw :: forall rw a. Queue (read :: READ | rw) a -> Aff a
draw q = makeAff \resolve -> do
  once q (resolve <<< Right)
  pure nonCanceler


read :: forall rw a. Queue rw a -> Effect (Array a)
read (Queue queue) = do
  ePH <- Ref.read queue
  case ePH of
    Left pending -> pure pending
    Right _ -> pure []


take :: forall rw a. Queue (write :: WRITE | rw) a -> Effect (Array a)
take (Queue queue) = do
  ePH <- Ref.read queue
  case ePH of
    Left pending -> do
      Ref.rite queue (Left [])
      pure pending
    Right _ -> pure []


-- | Removes the registered callbacks, if any.
del :: forall rw a. Queue (read :: READ | rw) a -> Effect Unit
del (Queue queue) = do
  ePH <- Ref.read queue
  case ePH of
    Left _ -> pure unit
    Right _ -> Ref.write queue (Left [])

-- | Adds a listener that does nothing, and "drains" any pending messages.
drain :: forall rw a. Queue (read :: READ | rw) a -> Effect Unit
drain q =
  on q \_ -> pure unit
