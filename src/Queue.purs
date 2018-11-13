module Queue
  ( module Queue.Types
  , Queue (..)
  , new
  , put, putMany
  , on, once, draw
  , read, take, del, drain
  ) where

import Queue.Types (kind SCOPE, READ, WRITE, class QueueScope, Handler)

import Prelude (Unit, pure, bind, discard, unit, (<$>), (<<<))
import Data.Either (Either (..))
import Data.Maybe (Maybe (..))
import Data.Traversable (traverse_)
import Data.Array (head) as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty (singleton, toArray) as Array
import Data.Array.ST (push, pushAll, splice, thaw, unsafeFreeze, withArray) as Array
import Control.Monad.ST (ST)
import Control.Monad.ST (run) as ST
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Ref (Ref)
import Effect.Ref (read, write, new) as Ref




newtype Queue (rw :: # SCOPE) a = Queue (Ref (Either (Array a) (Array (Handler a))))


new :: forall a. Effect (Queue (read :: READ, write :: WRITE) a)
new = Queue <$> Ref.new (Left [])


instance queueScopeQueue :: QueueScope Queue where
  readOnly     (Queue q) = Queue q
  allowWriting (Queue q) = Queue q
  writeOnly    (Queue q) = Queue q
  allowReading (Queue q) = Queue q


-- | Supply a single input to the queue.
put :: forall rw a. Queue (write :: WRITE | rw) a -> a -> Effect Unit
put q x = putMany q (Array.singleton x)


-- | Supply many inputs in batch to the queue.
putMany :: forall rw a
         . Queue (write :: WRITE | rw) a
        -> NonEmptyArray a
        -> Effect Unit
putMany (Queue queue) xss = do
  ePH <- Ref.read queue
  case ePH of
    Left pending ->
      let pending' = ST.run (Array.withArray (Array.pushAll (Array.toArray xss)) pending)
      in  Ref.write (Left pending') queue
    Right hs -> traverse_ (\x -> traverse_ (\f -> f x) hs) xss


-- | Add a handler to the unindexed queue.
on :: forall rw a. Queue (read :: READ | rw) a -> Handler a -> Effect Unit
on (Queue queue) f = do
  ePH <- Ref.read queue
  case ePH of
    Left pending -> do
      Ref.write (Right [f]) queue
      traverse_ f pending
    Right handlers ->
      let handlers' = ST.run (Array.withArray (Array.push f) handlers)
      in  Ref.write (Right handlers') queue


-- | Treat this as the only handler, and on the next input, clear all handlers.
once :: forall rw a. Queue (read :: READ | rw) a -> Handler a -> Effect Unit
once q@(Queue queue) f' = do
  let f x = do
        del q
        f' x
  ePH <- Ref.read queue
  case ePH of
    Left pending ->
      let go :: forall r. ST r (Effect Unit)
          go = do
            a <- Array.thaw pending
            mx <- Array.splice 0 1 [] a
            case Array.head mx of
              Nothing -> pure (Ref.write (Right [f]) queue)
              Just x -> do
                xs <- Array.unsafeFreeze a
                pure do
                  f x
                  Ref.write (Left xs) queue
      in  ST.run go
    Right handlers ->
      let handlers' = ST.run (Array.withArray (Array.push f) handlers)
      in  Ref.write (Right handlers') queue


-- | Pull the next asynchronous value out of a queue. Doesn't affect existing handlers (they will all receive the value as well).
draw :: forall rw a. Queue (read :: READ | rw) a -> Aff a
draw q = makeAff \resolve -> do
  once q (resolve <<< Right)
  pure nonCanceler


-- | Read all pending values (if any), without removing them from the queue.
read :: forall rw a. Queue rw a -> Effect (Array a)
read (Queue queue) = do
  ePH <- Ref.read queue
  case ePH of
    Left pending -> pure pending
    Right _ -> pure []


-- | Take all pending values (if any) from the queue.
take :: forall rw a. Queue (write :: WRITE | rw) a -> Effect (Array a)
take (Queue queue) = do
  ePH <- Ref.read queue
  case ePH of
    Left pending -> do
      Ref.write (Left []) queue
      pure pending
    Right _ -> pure []


-- | Removes the registered callbacks, if any.
del :: forall rw a. Queue (read :: READ | rw) a -> Effect Unit
del (Queue queue) = do
  ePH <- Ref.read queue
  case ePH of
    Left _ -> pure unit
    Right _ -> Ref.write (Left []) queue

-- | Adds a listener that does nothing, and "drains" any pending messages.
drain :: forall rw a. Queue (read :: READ | rw) a -> Effect Unit
drain q =
  on q \_ -> pure unit
