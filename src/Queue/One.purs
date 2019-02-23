-- | Queues with at most one handler - this is useful for sending messages to a single, solitary
-- | handler (user interface component, websocket connection, what have you).


module Queue.One
  ( module Queue.Types
  , Queue (..)
  ) where


import Queue.Types
  ( kind SCOPE, READ, WRITE, class QueueScope, Handler, class QueueExtra, allowWriting, writeOnly
  , class Queue, new, putMany, popMany, take, on, once, del, read, length, put, pop, draw, drain)

import Prelude (Unit, pure, bind, unit, discard, (<$>), (<<<), (<$), ($))
import Data.Either (Either (..))
import Data.Maybe (Maybe (..))
import Data.Traversable (traverse_, for_)
import Data.Array (reverse, uncons, snoc, take, drop, length) as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty (singleton, fromArray, head, tail) as ArrayNE
import Control.Monad.ST (run) as ST
import Control.Monad.Rec.Class (forever)
import Effect (Effect)
import Effect.Aff (Aff, makeAff, error, killFiber, joinFiber, delay, forkAff, effectCanceler)
import Effect.Aff.AVar as AVar
import Effect.Ref (Ref)
import Effect.Ref (read, write, new) as Ref
import Effect.Class (liftEffect)


-- | Represents a singleton queue, with at-most __one__ handler.
newtype Queue (rw :: # SCOPE) a =
  Queue (Ref (Either (Array a) (Handler a)))


instance queueQueueOne :: Queue Queue where
  new = Queue <$> Ref.new (Left [])
  putMany (Queue queue) xss = do
    for_ xss \x -> do -- left-to-right
      ePH <- Ref.read queue
      case ePH of
        Left pending -> Ref.write (Left (Array.snoc pending x)) queue
        Right f -> f x
  popMany (Queue queue) n = do
    ePH <- Ref.read queue
    case ePH of
      Right _ -> pure []
      Left pending ->
        let pending' = Array.reverse pending
        in  Array.take n pending' <$ Ref.write (Left (Array.reverse (Array.drop n pending'))) queue
  takeMany (Queue queue) n = do
    ePH <- Ref.read queue
    case ePH of
      Right _ -> pure []
      Left pending -> Array.take n pending <$ Ref.write (Left (Array.drop n pending)) queue
  takeAll (Queue queue) = do
    ePH <- Ref.read queue
    case ePH of
      Right _ -> pure []
      Left pending -> pending <$ Ref.write (Left []) queue
  on (Queue queue) f = do
    ePH <- Ref.read queue
    case ePH of
      Left pending -> do
        Ref.write (Right f) queue
        traverse_ f pending
      Right _ ->
        Ref.write (Right f) queue
  once q@(Queue queue) f' = do
    let f x = do
          del q
          f' x
    ePH <- Ref.read queue
    case ePH of
      Left pending -> case Array.uncons pending of
        Nothing -> Ref.write (Right f) queue
        Just {head,tail} -> do
          f head
          Ref.write (Left tail) queue
      Right _ ->
        Ref.write (Right f) queue
  del (Queue queue) = do
    ePH <- Ref.read queue
    case ePH of
      Left _ -> pure unit
      Right _ -> Ref.write (Left []) queue
  read (Queue queue) = do
    ePH <- Ref.read queue
    case ePH of
      Left pending -> pure pending
      Right _ -> pure []
  length (Queue queue) = do
    ePH <- Ref.read queue
    pure $ case ePH of
      Right _ -> 0
      Left pending -> Array.length pending


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
