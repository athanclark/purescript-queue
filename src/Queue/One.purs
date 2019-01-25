-- | Queues with at most one handler - this is useful for sending messages to a single, solitary
-- | handler (user interface component, websocket connection, what have you).


module Queue.One
  ( module Queue.Types
  , Queue (..), new
  , put, putMany, get, on, once, draw, take, read, del, drain
  ) where


import Queue.Types (kind SCOPE, READ, WRITE, class QueueScope, Handler, class QueueExtra, allowWriting, writeOnly)

import Prelude (Unit, pure, bind, unit, discard, (<$>), (<<<), (<$), ($))
import Data.Either (Either (..))
import Data.Maybe (Maybe (..))
import Data.Traversable (traverse_, for_)
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty (singleton, fromArray, head, tail) as ArrayNE
import Data.Array.ST (push, withArray) as Array
import Control.Monad.ST (run) as ST
import Control.Monad.Rec.Class (forever)
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler, error, killFiber, joinFiber, delay, forkAff)
import Effect.Aff.AVar as AVar
import Effect.Ref (Ref)
import Effect.Ref (read, write, new) as Ref
import Effect.Class (liftEffect)


newtype Queue (rw :: # SCOPE) a =
  Queue (Ref (Either (Array a) (Handler a)))


new :: forall a. Effect (Queue (read :: READ, write :: WRITE) a)
new = Queue <$> Ref.new (Left [])


instance queueScopeQueueOne :: QueueScope Queue where
  readOnly     (Queue q) = Queue q
  allowWriting (Queue q) = Queue q
  writeOnly    (Queue q) = Queue q
  allowReading (Queue q) = Queue q


instance queueExtraQueueOne :: QueueExtra Queue where
  debounceStatic toWaitFurther output = do
    presented <- liftEffect new
    writingThread <- AVar.empty
    writer <- forkAff $ forever do
      x <- get presented
      newWriter <- forkAff do
        delay toWaitFurther
        liftEffect (put (allowWriting output) x)
      mInvoker <- AVar.tryTake writingThread
      case mInvoker of
        Nothing -> pure unit
        Just i -> killFiber (error "Killing writer") i
      forcePut newWriter writingThread
    pure {input: writeOnly presented, writer}
  throttleStatic toWaitFurther output = do
    presented <- liftEffect new
    writingThread <- AVar.empty
    writer <- forkAff $ forever do
      x <- get presented
      mInvoker <- AVar.tryTake writingThread
      case mInvoker of
        Nothing -> pure unit
        Just i -> joinFiber i
      newWriter <- forkAff do
        delay toWaitFurther
        liftEffect (put (allowWriting output) x)
      forcePut newWriter writingThread
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
      forcePut newWriter writingThread
    listener <- forkAff $ forever do
      y <- get presented
      mInvoker <- AVar.tryTake writingThread
      case mInvoker of
        Nothing -> pure unit
        Just i -> killFiber (error "Killing listener") i
      liftEffect (put (allowWriting output) y)
    pure {input: writeOnly presented, writer, listener}


forcePut :: forall a. a -> AVar.AVar a -> Aff Unit
forcePut x avar = do
  _ <- AVar.tryTake avar
  AVar.put x avar


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


get :: forall rw a. Queue (read :: READ | rw) a -> Aff a -- FIXME should be cancelable
get q = makeAff \resolve -> nonCanceler <$ on q (resolve <<< Right)


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
