module Queue.One
  ( module Queue.Types
  , Queue (..), new
  , put, putMany, on, once, draw, take, read, del, drain
  ) where

import Queue.Types (kind SCOPE, READ, WRITE, class QueueScope, Handler)

import Prelude (Unit, pure, bind, unit, discard, (<$>), (<<<))
import Data.Either (Either (..))
import Data.Maybe (Maybe (..))
import Data.Traversable (traverse_, for_)
import Data.Array (head) as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty (singleton, toArray, fromArray, head, tail) as ArrayNE
import Data.Array.ST (pushAll, push, splice, thaw, unsafeFreeze, withArray) as Array
import Control.Monad.ST (ST)
import Control.Monad.ST (run) as ST
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Ref (Ref)
import Effect.Ref (read, write, new) as Ref




newtype Queue (rw :: # SCOPE) a =
  Queue (Ref (Either (Array a) (Handler a)))


new :: forall a. Effect (Queue (read :: READ, write :: WRITE) a)
new = Queue <$> Ref.new (Left [])


instance queueScopeQueueOne :: QueueScope Queue where
  readOnly     (Queue q) = Queue q
  allowWriting (Queue q) = Queue q
  writeOnly    (Queue q) = Queue q
  allowReading (Queue q) = Queue q


-- | Supply a single input to the queue.
put :: forall rw a. Queue (write :: WRITE | rw) a -> a -> Effect Unit
put q x = putMany q (ArrayNE.singleton x)


-- | Supply many inputs in batch to the queue.
putMany:: forall rw a
        . Queue (write :: WRITE | rw) a
       -> NonEmptyArray a
       -> Effect Unit
putMany(Queue queue) xss = do
  for_ xss \x -> do
    ePH <- Ref.read queue
    case ePH of
      Left pending ->
        let pending' = ST.run (Array.withArray (Array.push x) pending)
        in  Ref.write (Left pending') queue
      Right f -> f x


-- | Assign the handler to the singleton queue.
on :: forall rw a. Queue (read :: READ | rw) a -> Handler a -> Effect Unit
on (Queue queue) f = do
  ePH <- Ref.read queue
  case ePH of
    Left pending -> do
      Ref.write (Right f) queue
      traverse_ f pending
    Right _ ->
      Ref.write (Right f) queue


-- | Run the handler only once for the next input before unassigning itself.
once :: forall rw a. Queue (read :: READ | rw) a -> Handler a -> Effect Unit
once q@(Queue queue) f' = do
  let f x = do
        del q
        f' x
  ePH <- Ref.read queue
  case ePH of
    Left pending -> case ArrayNE.fromArray pending of
      Nothing -> Ref.write (Right f) queue
      Just xss -> do
        f (ArrayNE.head xss)
        Ref.write (Left (ArrayNE.tail xss)) queue
    Right _ ->
      Ref.write (Right f) queue


-- | Pull a single asynchronous value out of a queue.
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
drain q = on q \_ -> pure unit
