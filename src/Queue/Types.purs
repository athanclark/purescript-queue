module Queue.Types where

import Prelude (Unit)
import Data.Time.Duration (Milliseconds)
import Effect (Effect)
import Effect.Aff (Aff, Fiber)


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
  debounceStatic :: forall a. Milliseconds -> queue (read :: READ) a -> Aff {input :: queue (write :: WRITE) a, writer :: Fiber Unit}
  throttleStatic :: forall a. Milliseconds -> queue (read :: READ) a -> Aff {input :: queue (write :: WRITE) a, writer :: Fiber Unit}
  intersperseStatic :: forall a. Milliseconds -> Aff a -> queue (read :: READ) a -> Aff {input :: queue (write :: WRITE) a, writer :: Fiber Unit, listener :: Fiber Unit}


class Queue (queue :: # SCOPE -> Type -> Type) where
  new :: forall a. Effect (queue (read :: READ, write :: WRITE) a)
  -- | Pushes multiple values on the stack of pending values, or traverses through the handler(s).
  putMany :: forall a rw. queue (write :: WRITE | rw) a -> Array a -> Effect Unit
  -- | Pops as many values as indicated off the stack of pending values, if any.
  popMany :: forall a rw. queue (write :: WRITE | rw) a -> Int -> Effect (Array a)
  -- | Equivalent to `length q >>= popMany q`, but without the overhead.
  take :: forall a rw. queue (write :: WRITE | rw) a -> Effect (Array a)
  on :: forall a rw. queue (read :: READ | rw) a -> Handler a -> Effect Unit
  once :: forall rw a. queue (read :: READ | rw) a -> Handler a -> Effect Unit
  del :: forall a rw. queue (read :: READ | rw) a -> Effect Unit
  read :: forall a rw. queue rw a -> Effect (Array a)
  length :: forall a rw. queue rw a -> Effect Int


put :: forall a rw. queue (write :: WRITE | rw) a -> a -> Effect Unit
put q x = putMany q [x]

pop :: forall a rw. queue (write :: WRITE | rw) a -> Effect (Maybe a)
pop q = Array.head <$> popMany q 1


-- | Pull the next asynchronous value out of a queue. Doesn't affect existing handlers (they will all receive the value as well). If this action is canceled, __all__ handlers will be removed from the queue.
draw :: forall rw a. Queue (read :: READ | rw) a -> Aff a
draw q = makeAff \resolve -> effectCanceler (del q) <$ once q (resolve <<< Right)


-- | Adds a listener that does nothing, and "drains" any pending messages.
drain :: forall rw a. Queue (read :: READ | rw) a -> Effect Unit
drain q = on q \_ -> pure unit
