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
  putMany :: forall a rw. queue (write :: WRITE | rw) a -> Array a -> Effect Unit
  on :: forall a rw. queue (read :: READ | rw) a -> Handler a -> Effect Unit
  read :: forall a rw. queue rw a -> Effect (Array a)
  take :: forall a rw. queue (write :: WRITE | rw) a -> Effect (Array a)
  -- FUCK - uncons? unsnoc? take all, init? last?
  del :: forall a rw. queue (read :: READ | rw) a -> Effect Unit


put :: forall a rw. queue (write :: WRITE | rw) a -> a -> Effect Unit
put q x = putMany q [x]

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


-- | Pull the next asynchronous value out of a queue. Doesn't affect existing handlers (they will all receive the value as well). If this action is canceled, __all__ handlers will be removed from the queue.
draw :: forall rw a. Queue (read :: READ | rw) a -> Aff a
draw q = makeAff \resolve -> effectCanceler (del q) <$ once q (resolve <<< Right)


-- | Adds a listener that does nothing, and "drains" any pending messages.
drain :: forall rw a. Queue (read :: READ | rw) a -> Effect Unit
drain q =
  on q \_ -> pure unit
