-- | Un-indexed queues with a set of handlers - this is useful for broadcasting messages to a set of recipients,
-- | where removing them individually from the queue isn't necessary (but incremental additions are). This
-- | could be useful in interfaces where the list of handlers strictly increases, then gets wiped all at
-- | once if desired (i.e. a feed of social media posts).

module Queue
  ( module Queue.Types
  , Queue (..)
  , new
  ) where


import Queue.Types
  ( kind SCOPE, READ, WRITE, class QueueScope, Handler, class QueueExtra, allowWriting, writeOnly
  , class Queue, put, putMany, pop, popMany, take, takeAll, takeMany, on, once, del, read, length, draw, drain)

import Queue.Types (new) as Q

import Prelude (pure, bind, discard, unit, (<$>), (<$), ($))
import Data.Either (Either (..))
import Data.Maybe (Maybe (..))
import Data.Traversable (traverse_, for_)
import Data.Array (reverse, length, snoc, take, drop, uncons) as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty (snoc, singleton) as ArrayNE
import Control.Monad.Rec.Class (forever)
import Effect (Effect)
import Effect.Aff (forkAff, killFiber, joinFiber, delay, error)
import Effect.Aff.AVar (empty, tryTake, put) as AVar
import Effect.Class (liftEffect)
import Effect.Ref (Ref)
import Effect.Ref (read, write, new) as Ref


-- | Either a non empty set of handlers, or a possibly empty set of pending values.
newtype Queue (rw :: # SCOPE) a = Queue (Ref (Either (Array a) (NonEmptyArray (Handler a))))

new :: forall a. Effect (Queue (read :: READ, write :: WRITE) a)
new = Q.new


instance queueQueue :: Queue Queue where
  new = Queue <$> Ref.new (Left [])
  putMany (Queue queue) xss = do
    for_ xss \x -> do
      ePH <- Ref.read queue
      case ePH of
        Left pending -> Ref.write (Left (Array.snoc pending x)) queue
        Right hs -> traverse_ (\f -> f x) hs -- traverse through the handlers for each event passed
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
        Ref.write (Right (ArrayNE.singleton f)) queue
        traverse_ f pending
      Right handlers ->
        Ref.write (Right (ArrayNE.snoc handlers f)) queue
  once q@(Queue queue) f' = do
    let f x = do
          del q
          f' x
    ePH <- Ref.read queue
    case ePH of
      Left pending -> case Array.uncons pending of
        Nothing -> Ref.write (Right (ArrayNE.singleton f)) queue
        Just {head,tail} -> do
          f head
          Ref.write (Left tail) queue
      Right handlers ->
        Ref.write (Right (ArrayNE.snoc handlers f)) queue
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


instance queueScopeQueue :: QueueScope Queue where
  readOnly     (Queue q) = Queue q
  allowWriting (Queue q) = Queue q
  writeOnly    (Queue q) = Queue q
  allowReading (Queue q) = Queue q


instance queueExtraQueue :: QueueExtra Queue where
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
