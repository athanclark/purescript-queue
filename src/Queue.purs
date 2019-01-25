-- | Un-indexed queues with a set of handlers - this is useful for sending messages to a set of recipients,
-- | where removing them individually from the queue isn't necessary (but incremental additions are). This
-- | could be useful in interfaces where the list of handlers strictly increases, then gets wiped all at
-- | once if desired (i.e. a feed of social media posts).

module Queue
  ( module Queue.Types
  , Queue (..)
  , new
  , put, putMany
  , on, once, draw
  , read, take, del, drain
  ) where


import Queue.Types (kind SCOPE, READ, WRITE, class QueueScope, Handler, class QueueExtra, allowWriting, writeOnly)

import Prelude (Unit, pure, bind, discard, unit, (<$>), (<<<), (<$), ($))
import Data.Either (Either (..))
import Data.Maybe (Maybe (..))
import Data.Traversable (traverse_, for_)
import Data.Array (head) as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty (singleton) as Array
import Data.Array.ST (push, splice, thaw, unsafeFreeze, withArray) as Array
import Control.Monad.ST (ST)
import Control.Monad.ST (run) as ST
import Control.Monad.Rec.Class (forever)
import Effect (Effect)
import Effect.Aff (Aff, makeAff, effectCanceler, forkAff, killFiber, joinFiber, delay, error)
import Effect.Aff.AVar as AVar
import Effect.Class (liftEffect)
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


instance queueExtraQueueOne :: QueueExtra Queue where
  debounceStatic toWaitFurther output = do
    presented <- liftEffect new
    writingThread <- AVar.empty
    writer <- forkAff $ forever do
      x <- draw presented
      newWriter <- forkAff do
        delay toWaitFurther
        liftEffect (put (allowWriting output) x)
      mInvoker <- AVar.tryTake writingThread
      case mInvoker of
        Nothing -> pure unit
        Just i -> killFiber (error "Killing writer") i
      AVar.put newWriter writingThread
    pure {input: writeOnly presented, writer}
  throttleStatic toWaitFurther output = do
    presented <- liftEffect new
    writingThread <- AVar.empty
    writer <- forkAff $ forever do
      x <- draw presented
      mInvoker <- AVar.tryTake writingThread
      case mInvoker of
        Nothing -> pure unit
        Just i -> joinFiber i
      newWriter <- forkAff do
        delay toWaitFurther
        liftEffect (put (allowWriting output) x)
      AVar.put newWriter writingThread
    pure {input: writeOnly presented, writer}
  intersperseStatic timeBetween xM output = do
    presented <- liftEffect new
    writingThread <- AVar.empty
    writer <- forkAff $ forever do
      mInvoker <- AVar.tryTake writingThread
      case mInvoker of
        Nothing -> pure unit
        Just i -> joinFiber i
      newWriter <- forkAff do
        delay timeBetween
        x <- xM
        liftEffect (put (allowWriting output) x)
      AVar.put newWriter writingThread
    listener <- forkAff $ forever do
      y <- draw presented
      mInvoker <- AVar.tryTake writingThread
      case mInvoker of
        Nothing -> pure unit
        Just i -> killFiber (error "Killing listener") i
      liftEffect (put (allowWriting output) y)
    pure {input: writeOnly presented, writer, listener}


-- | Supply a single input to the queue.
put :: forall rw a. Queue (write :: WRITE | rw) a -> a -> Effect Unit
put q x = putMany q (Array.singleton x)


-- | Supply many inputs in batch to the queue.
putMany :: forall rw a
         . Queue (write :: WRITE | rw) a
        -> NonEmptyArray a
        -> Effect Unit
putMany (Queue queue) xss = do
  for_ xss \x -> do
    ePH <- Ref.read queue
    case ePH of
      Left pending ->
        let pending' = ST.run (Array.withArray (Array.push x) pending)
        in  Ref.write (Left pending') queue
      Right hs -> traverse_ (\f -> f x) hs


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


-- | Pull the next asynchronous value out of a queue. Doesn't affect existing handlers (they will all receive the value as well). If this action is canceled, __all__ handlers will be removed from the queue.
draw :: forall rw a. Queue (read :: READ | rw) a -> Aff a
draw q = makeAff \resolve -> effectCanceler (del q) <$ once q (resolve <<< Right)


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
