module Queue.Types where

import Prelude (Unit, pure, unit, (<$), (<$>), (<<<))
import Data.Array (head) as Array
import Data.Time.Duration (Milliseconds)
import Data.Maybe (Maybe)
import Data.Either (Either (Right))
import Data.Traversable (class Traversable)
import Effect (Effect)
import Effect.Aff (Aff, Fiber, makeAff, effectCanceler)


foreign import kind SCOPE

foreign import data READ :: SCOPE

foreign import data WRITE :: SCOPE

type Handler a = a -> Effect Unit


class QueueScope (q :: # SCOPE -> Type -> Type) where
  readOnly     :: forall rw a. q (read  :: READ  | rw) a -> q (read  :: READ)  a
  writeOnly    :: forall rw a. q (write :: WRITE | rw) a -> q (write :: WRITE) a
  allowWriting :: forall rw a. q (read  :: READ)  a -> q (read  :: READ  | rw) a
  allowReading :: forall rw a. q (write :: WRITE) a -> q (write :: WRITE | rw) a


class QueueExtra (queue :: # SCOPE -> Type -> Type) where
  -- | messages submitted before `debounceStatic`'s time period will be dropped
  debounceStatic :: forall a. Milliseconds -> queue (read :: READ) a -> Aff {input :: queue (write :: WRITE) a, writer :: Fiber Unit}
  -- | messages submitted before `throttleStatic`'s time period will be cached until the time has passed
  throttleStatic :: forall a. Milliseconds -> queue (read :: READ) a -> Aff {input :: queue (write :: WRITE) a, writer :: Fiber Unit}
  -- | messages submitted after `intersperseStatic`'s time period will be punctuated with messages generated by the parameter, like pings
  intersperseStatic :: forall a. Milliseconds -> Aff a -> queue (read :: READ) a -> Aff {input :: queue (write :: WRITE) a, writer :: Fiber Unit, listener :: Fiber Unit}

-- | Represents an un-indexed queue - such that identifying handlers is not supported.
class Queue (queue :: # SCOPE -> Type -> Type) where
  -- | Create a new, empty queue.
  new :: forall a. Effect (queue (read :: READ, write :: WRITE) a)
  -- | Pushes multiple values on the stack of pending values, or traverses through the handler(s).
  putMany :: forall a rw t. Traversable t => queue (write :: WRITE | rw) a -> t a -> Effect Unit -- traversable?
  -- | Pops as many values as indicated off the stack of pending values, if any, in the reverse
  -- | order they were added - i.e. youngest first.
  popMany :: forall a rw. queue (write :: WRITE | rw) a -> Int -> Effect (Array a)
  -- | Pops as many values as indicated off the stack of pending values, if any, in the same order
  -- | they were added - i.e. oldest first.
  takeMany :: forall a rw. queue (write :: WRITE | rw) a -> Int -> Effect (Array a)
  -- | Equivalent to `length q >>= takeMany q`, but without the overhead.
  takeAll :: forall a rw. queue (write :: WRITE | rw) a -> Effect (Array a)
  -- | Assign a handler to capture queue events.
  on :: forall a rw. queue (read :: READ | rw) a -> Handler a -> Effect Unit
  -- | Removes a handler after first run.
  once :: forall rw a. queue (read :: READ | rw) a -> Handler a -> Effect Unit
  -- | Removes all handlers from the queue, without affecting the cache.
  del :: forall a rw. queue (read :: READ | rw) a -> Effect Unit
  -- | Observes the values in the queue without deleting them.
  read :: forall a rw. queue rw a -> Effect (Array a)
  -- | Length of the cache.
  length :: forall a rw. queue rw a -> Effect Int

-- | Put only one event.
put :: forall a rw queue. Queue queue => queue (write :: WRITE | rw) a -> a -> Effect Unit
put q x = putMany q [x]

-- | Pop the latest added event.
pop :: forall a rw queue. Queue queue => queue (write :: WRITE | rw) a -> Effect (Maybe a)
pop q = Array.head <$> popMany q 1

-- | Take the first added event.
take :: forall a rw queue. Queue queue => queue (write :: WRITE | rw) a -> Effect (Maybe a)
take q = Array.head <$> takeMany q 1

-- | Pull the next asynchronous value out of a queue. Doesn't affect existing handlers
-- | (they will all receive the value as well). If this action is canceled, __all__
-- | handlers will be removed from the queue, because this interface is un-indexed.
draw :: forall rw a queue. Queue queue => queue (read :: READ | rw) a -> Aff a
draw q = makeAff \resolve -> effectCanceler (del q) <$ once q (resolve <<< Right)

-- | Adds a listener that does nothing, and "drains" any pending messages.
drain :: forall rw a queue. Queue queue => queue (read :: READ | rw) a -> Effect Unit
drain q = on q \_ -> pure unit
